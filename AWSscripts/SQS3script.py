# Instructions

# python SQS3script.py --s3bucket <bucket name>  --acnumber <account number>  --sqsname <sqs queue name> --user <user name>
# s3bucket, acnumber parameters are mandatory, sqsname and user are optional

# This script assumes that the aws credentials are created at ~/.aws/credentials by running aws configure on command line
# region examples: us-east-1, us-west-2 etc.


import boto.sqs.connection
import boto3
import json
import os
import re
import sys
import urllib
import StringIO

from boto.exception import BotoServerError, S3ResponseError

import argparse

SQS_QUEUE_POLICY_TEMPLATE = """{
              "Version": "2008-10-17",
              "Id": "PolicyExample",
              "Statement": [
                {
                  "Sid": "example-statement-ID",
                  "Effect": "Allow",
                  "Principal": {
                    "AWS": "*"
                  },
                  "Action": "SQS:SendMessage",
                  "Resource": "arn:aws:sqs:%(region)s:%(acnumber)s:%(queue_name)s",
                  "Condition": {
                    "ArnLike": {
                      "aws:SourceArn": %(source_arn)s
                    }
                  }
                },
                {
                  "Sid": "GiveAccessToLoggly",
                  "Effect": "Allow",
                  "Principal": {
                    "AWS": "arn:aws:iam::%(acnumber)s:root"
                  },
                  "Action": "SQS:*",
                  "Resource": "arn:aws:sqs:%(region)s:%(acnumber)s:%(queue_name)s"
                }
              ]
            }"""

USER_POLICY_TEMPLATE = """{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "Sidtest",
                    "Effect": "Allow",
                    "Action": [
                        "sqs:*"
                    ],
                    "Resource": [
                        "%(sqs_resource)s"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action":[
                    "s3:ListBucket",
                    "s3:GetObject",
                    "s3:GetBucketLocation"
                 ],
                    "Resource": [
                      "%(s3_resource)s"
                    ]
                }
            ]
            }"""


def put_bucket_notification_config(client, region, s3bucket, acnumber, sqs_queue_name):
    client.put_bucket_notification_configuration(
        Bucket=s3bucket,
        NotificationConfiguration={
            "QueueConfigurations": [{
                "Id": "Notification",
                "Events": ["s3:ObjectCreated:*"],
                "QueueArn": "arn:aws:sqs:" + region + ":" + acnumber + ":" + sqs_queue_name
            }],
        }
    )


def get_source_arn_with_appended_bucket(queue_attr, s3bucket):
    start = '\"aws:SourceArn\":'
    end = '}}}'
    result = re.search('%s(.*)%s' % (start, end), queue_attr).group(1)

    leftbracketremoved = result.replace('[', '')
    rightbracketremoved = leftbracketremoved.replace(']', '')

    return '[' + rightbracketremoved + ',' + '\"arn:aws:s3:*:*:' + s3bucket + '\"' + ']'


def set_sqs_queue_policy(conn, region, acnumber, queue_name, source_arn):
    queue_policy = SQS_QUEUE_POLICY_TEMPLATE % (
        {"region": region, "acnumber": acnumber, "queue_name": queue_name, "source_arn": source_arn})

    parsed = json.loads(queue_policy)

    conn.set_queue_attribute(queue_name, 'Policy', json.dumps(parsed))


def add_bucket_to_queue_policy(conn, client, region, acnumber, queue_name, s3bucket):
    queue_attr_raw = conn.get_queue_attributes(queue_name, attribute='All')
    queue_attr = str(queue_attr_raw)

    if 'arn:aws:s3' in queue_attr:
        if "arn:aws:s3:*:*:" + s3bucket in queue_attr:
            print 'Given bucket already exists in queue\'s policy'
        else:
            # append the bucket to the existing policy
            print "A bucket already exists in this queue's policy, appending this bucket to it"

            source_arn = get_source_arn_with_appended_bucket(queue_attr, s3bucket)
            set_sqs_queue_policy(conn, region, acnumber, queue_name, source_arn)
            put_bucket_notification_config(client, region, s3bucket, acnumber, queue_name)
    else:
        set_sqs_queue_policy(conn, region, acnumber, queue_name, "arn:aws:s3:*:*:" + s3bucket)
        put_bucket_notification_config(client, region, s3bucket, acnumber, queue_name)


def get_policy_resources(iam, user):
    existing_policy = str(iam.get_user_policy(user, 'LogglyUserPolicy'))
    existing_policy_decoded = urllib.unquote(existing_policy)

    s3Buckets = []
    sqsQueues = []

    response = iam.get_all_access_keys(user, max_items=1)

    s = StringIO.StringIO(existing_policy_decoded)
    for line in s:
        if 'arn:aws:sqs' in line:
            sqsQueues.append(line.strip().replace(",", ""))
        if 'arn:aws:s3' in line:
            s3Buckets.append(line.strip().replace(",", ""))

    # append current s3bucket and sqs queue
    sqsQueues.append('\"arn:aws:sqs:%s:%s:%s\"' % (region, acnumber, sqsname,))
    s3Buckets.append('\"arn:aws:s3:::%s/*\"' % (s3bucket))
    s3Buckets.append('\"arn:aws:s3:::%s\"' % (s3bucket))

    sqsQueuesString = ""
    for entry in sqsQueues:
        sqsQueuesString = sqsQueuesString + entry + ",\n"

    s3BucketsString = ""
    for entry in s3Buckets:
        s3BucketsString = s3BucketsString + entry + ",\n"

    return sqsQueuesString, s3BucketsString


def set_user_policy(iam, user, sqs_resource, s3_resource):
    policy_json = USER_POLICY_TEMPLATE % ({"sqs_resource": sqs_resource, "s3_resource": s3_resource})
    iam.put_user_policy(user, 'LogglyUserPolicy', policy_json)


def create_user_and_access_keys(iam, user):
    # create an IAM user
    iam.create_user(user)

    # create an access key
    response = iam.create_access_key(user)
    loggly_access_key = response.access_key_id
    loggly_secret_key = response.secret_access_key

    print "Access key for Loggly"
    print loggly_access_key

    print "Secret key for Loggly"
    print loggly_secret_key

    print ""
    print "Please save the above credentials"


parser = argparse.ArgumentParser()
parser.add_argument("--acnumber", dest="acnumber",
                  help="account number")
parser.add_argument("--s3bucket", dest="s3bucket",
                  help="s3 bucket name")
parser.add_argument("--user", dest="user",
                  help="user")
parser.add_argument("--admin", dest="admin",
                  help="admin user name")
parser.add_argument("--sqsname", dest="sqsname",
                  help="sqsname")

opts = parser.parse_args()

s3bucket = opts.s3bucket
acnumber = opts.acnumber
sqsname = opts.sqsname
user = opts.user
admin = opts.admin

if not s3bucket:
    parser.error("S3 bucket name not provided")

if not acnumber:
    parser.error("Account number not provided")

if not acnumber.isdigit():
    parser.error("Please check your account number, it should only contain digits, no other characters.")

conn = boto.connect_s3()

access_key = ''
secret_key = ''
bucket = ''

credentials_name = admin if admin else "default"
home = os.path.expanduser("~")

with open(home + '/.aws/credentials') as f:
    for line in f:
        if credentials_name in line:
            for line in f:
                if "aws_access_key_id" in line:
                    access_key = line.split("=", 1)[1].strip()
                if "aws_secret_access_key" in line:
                    secret_key = line.split("=", 1)[1].strip()
                    break

if not access_key:
    print "AWS access key is not set. Please make sure to execute 'aws configure' before this script"
    sys.exit()

if not secret_key:
    print "AWS secret key is not set. Please make sure to execute 'aws configure' before this script"
    sys.exit()

try:
    bucket = conn.get_bucket(s3bucket)
except S3ResponseError, e:
    print e
    if "Not Found" in e:
        print 'S3 bucket ' + s3bucket + ' does not exist, please create it and run the script again'
    elif "Forbidden":
        print "Access to AWS is forbidden, please make sure to execute 'aws configure' before this script"
    sys.exit()

region = bucket.get_location()

if region == '':
    region = 'us-east-1'

conn = boto.sqs.connect_to_region(region, aws_access_key_id=access_key, aws_secret_access_key=secret_key)
client = boto3.client('s3', region)
queue_name = conn.get_queue(sqsname)

if queue_name is not None:
    # queue exists
    add_bucket_to_queue_policy(conn, client, region, acnumber, queue_name, s3bucket)
else:
    # queue does not exist and no sqs queue name is passed
    if sqsname == None:
        sqsname = 'loggly-s3-queue'

    queue_name = conn.get_queue(sqsname)

    # Default queue already exists
    if queue_name != None:
        add_bucket_to_queue_policy(conn, client, region, acnumber, queue_name, s3bucket)
    else:
        # create the default queue or the queue passed as a parameter
        q = conn.create_queue(sqsname)
        queue_name = conn.get_queue(sqsname)

        add_bucket_to_queue_policy(conn, client, region, acnumber, queue_name, s3bucket)

print "Queue Name"
print sqsname

iam = boto.connect_iam(access_key, secret_key)

if user is None or user == '':
    user = 'loggly-s3-user'
try:
    response = iam.get_user(user)
    if 'get_user_response' in response:
        print 'IAM user %s already exists, appending the sqs queue and s3 bucket to this IAM user\'s policy' % user

        sqs_resource, s3_resource = get_policy_resources(iam, user)
        set_user_policy(iam, user, sqs_resource, s3_resource)

        print ""
        print 'Appended! Please provide the access key and secret key for the IAM user %s in the form fields' % user

except BotoServerError, e:
    if "The user with name" in e.message and "cannot be found" in e.message:

        create_user_and_access_keys(iam, user)
        set_user_policy(iam, user, "arn:aws:sqs:%s:%s:%s" % (region, acnumber, sqsname),
                        "arn:aws:s3:::%(bucket)s/*,\narn:aws:s3:::%(bucket)s" % ({"bucket": s3bucket}))
    else:
        print(e.message)
