# Instructions

# python SQS3script.py --s3bucket <bucket name>  --acnumber <account number>  --sqsname <sqs queue name> --user <user name>
# s3bucket, acnumber parameters are mandatory, sqsname and user are optional

# This script assumes that the aws credentials are created at ~/.aws/credentials by running aws configure on command line
# region examples: us-east-1, us-west-2 etc.


import boto
import boto.sqs
import boto.sqs.connection
import boto3
import json
import os
import re
import sys

from boto.sqs.connection import SQSConnection
from boto.sqs.message import Message
from boto.exception import BotoServerError, S3ResponseError

from optparse import OptionParser


parser = OptionParser()
parser.add_option("--acnumber", dest="acnumber",
                  help="account number")
parser.add_option("--s3bucket", dest="s3bucket",
                  help="s3 bucket name")
parser.add_option("--user", dest="user",
                  help="user")
parser.add_option("--sqsname", dest="sqsname",
                  help="sqsname")

(opts, args) = parser.parse_args()


s3bucket = opts.s3bucket
acnumber = opts.acnumber
sqsname = opts.sqsname
user = opts.user

conn = boto.connect_s3()

access_key=''
secret_key=''
bucket=''

with open(os.environ['HOME'] + '/.aws/credentials') as f:
    for line in f:
        if "aws_access_key_id" in line:
             access_key = line.split("=",1)[1].strip()
        if "aws_secret_access_key" in line:
             secret_key = line.split("=",1)[1].strip()

if not access_key:
    print "Please check your ~/.aws/credentials file and make sure that access key and secret access key are set. Run aws configure to set them up"

if not secret_key:
    print "Please check your ~/.aws/credentials file and make sure that access key and secret access key are set. Run aws configure to set them up"

try:
    bucket = conn.get_bucket(s3bucket)
except S3ResponseError, e:
    if "Not Found" in e:
        print e
        print 'S3 bucket ' + s3bucket + ' does not exist, please create it and run the script again'
        sys.exit()
    else:
        print e
        sys.exit()
    


region = bucket.get_location()

if region == '':
  region = 'us-east-1'

if not s3bucket:
    parser.error("S3 bucket name not provided")

if not acnumber:
    parser.error("Account number not provided")


conn = boto.sqs.connect_to_region(region, aws_access_key_id=access_key,  aws_secret_access_key=secret_key)
client = boto3.client('s3', region)
queue_name = conn.get_queue(sqsname)


if "None" not in str(queue_name):
    #queue exists
  
    queue_attr_raw = conn.get_queue_attributes(queue_name, attribute='All')
    queue_attr = str(queue_attr_raw) 

    if s3bucket in queue_attr:
      print 'Bucket already exists in queue\'s policy, moving on'

    elif 'arn:aws:s3' in queue_attr:
        # append the bucket to the existing policy
        print "A bucket already exists in this queue's policy, appending this bucket to it"
       
        start = '\"aws:SourceArn\":'
        end = '}}}'
        result = re.search('%s(.*)%s' % (start, end), queue_attr).group(1)
        
        
        leftbracketremoved = result.replace('[','')
        rightbracketremoved = leftbracketremoved.replace(']','')

        addon  = '[' + rightbracketremoved + ',' + '\"arn:aws:s3:*:*:' + s3bucket +'\"' +']'
        

        text = """ {
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
              "Resource": "arn:aws:sqs:%s:%s:%s",
              "Condition": {
                "ArnLike": {
                  "aws:SourceArn": %s   
                }
              }
            },
            {
              "Sid": "GiveAccessToLoggly",
              "Effect": "Allow",
              "Principal": {
                "AWS": "arn:aws:iam::%s:root"
              },
              "Action": "SQS:*",
              "Resource": "arn:aws:sqs:%s:%s:%s"
            }
          ]
        }
        """ % (region, acnumber, queue_name, addon, acnumber, region, acnumber, queue_name)

        
        parsed = json.loads(text)
       
        conn.set_queue_attribute(queue_name, 'Policy', json.dumps(parsed))

        # s3 bucket notification configuration 
        client = boto3.client('s3', region)


        response = client.put_bucket_notification_configuration(
            Bucket=s3bucket,
            NotificationConfiguration={ 
                "QueueConfigurations": [{
                 "Id": "Notification",
                 "Events": ["s3:ObjectCreated:*"],
                 "QueueArn": "arn:aws:sqs:" + region + ":" + acnumber + ":" + queue_name
            }],
            }
        )

        policy_json = """{
          "Id": "Policy1467278443739",
          "Version": "2012-10-17",
          "Statement": [
            {
              "Sid": "Stmt1467278441801",
              "Action": [
                "s3:GetObject"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s/*",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            },
            {
              "Sid": "Stmt14672784418012",
              "Action": [
                "s3:ListBucket"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            },
            {
              "Sid": "Stmt14672784418013",
              "Action": [
                "s3:GetBucketLocation"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            }
          ]
        }""" % (s3bucket, s3bucket, s3bucket,)

        response = bucket.set_policy(policy_json)

    else:
        conn.set_queue_attribute(queue_name, 'Policy', json.dumps({
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
              "Resource": "arn:aws:sqs:" + region + ":" + acnumber + ":" + sqsname,
              "Condition": {
                "ArnLike": {
                  "aws:SourceArn": "arn:aws:s3:*:*:" + s3bucket
                }
              }
            },
            {
              "Sid": "GiveAccessToLoggly",
              "Effect": "Allow",
              "Principal": {
                "AWS": "arn:aws:iam::" + acnumber + ":root"
              },
              "Action": "SQS:*",
              "Resource": "arn:aws:sqs:" + region + ":" + acnumber + ":" + sqsname
            }
          ]
        }))

        # s3 bucket notification configuration 
        client = boto3.client('s3', region)


        response = client.put_bucket_notification_configuration(
            Bucket=s3bucket,
            NotificationConfiguration={ 
                "QueueConfigurations": [{
                 "Id": "Notification",
                 "Events": ["s3:ObjectCreated:*"],
                 "QueueArn": "arn:aws:sqs:" + region + ":" + acnumber + ":" + sqsname
            }],
            }
        )

        policy_json = """{
          "Id": "Policy1467278443739",
          "Version": "2012-10-17",
          "Statement": [
            {
              "Sid": "Stmt1467278441801",
              "Action": [
                "s3:GetObject"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s/*",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            },
            {
              "Sid": "Stmt14672784418012",
              "Action": [
                "s3:ListBucket"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            },
            {
              "Sid": "Stmt14672784418013",
              "Action": [
                "s3:GetBucketLocation"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            }
          ]
        }""" % (s3bucket, s3bucket, s3bucket,)

        response = bucket.set_policy(policy_json)

else: 
    # queue does not exist and no sqs queue name is passed
    if sqsname == None:
        sqsname = 'loggly-s3-queue'
    
    queue_name = conn.get_queue(sqsname)

    # Default queue already exists
    if queue_name!= None:
        queue_attr_raw = conn.get_queue_attributes(queue_name, attribute='All')
        queue_attr = str(queue_attr_raw) 

        if s3bucket in queue_attr:
          print 'Bucket already exists in queue\'s policy, moving on'

        else:
            # append the bucket to the existing policy
            print "A bucket already exists in this queue's policy, appending this bucket to it"
           
            start = '\"aws:SourceArn\":'
            end = '}}}'
            result = re.search('%s(.*)%s' % (start, end), queue_attr).group(1)
            
            
            leftbracketremoved = result.replace('[','')
            rightbracketremoved = leftbracketremoved.replace(']','')

            addon  = '[' + rightbracketremoved + ',' + '\"arn:aws:s3:*:*:' + s3bucket +'\"' +']'
            

            text = """ {
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
                  "Resource": "arn:aws:sqs:%s:%s:%s",
                  "Condition": {
                    "ArnLike": {
                      "aws:SourceArn": %s   
                    }
                  }
                },
                {
                  "Sid": "GiveAccessToLoggly",
                  "Effect": "Allow",
                  "Principal": {
                    "AWS": "arn:aws:iam::%s:root"
                  },
                  "Action": "SQS:*",
                  "Resource": "arn:aws:sqs:%s:%s:%s"
                }
              ]
            }
            """ % (region, acnumber, sqsname, addon, acnumber, region, acnumber, sqsname)

            
            parsed = json.loads(text)
           
            conn.set_queue_attribute(queue_name, 'Policy', json.dumps(parsed))

            # s3 bucket notification configuration 
            client = boto3.client('s3', region)


            response = client.put_bucket_notification_configuration(
                Bucket=s3bucket,
                NotificationConfiguration={ 
                    "QueueConfigurations": [{
                     "Id": "Notification",
                     "Events": ["s3:ObjectCreated:*"],
                     "QueueArn": "arn:aws:sqs:" + region + ":" + acnumber + ":" + sqsname
                }],
                }
            )

            policy_json = """{
              "Id": "Policy1467278443739",
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Sid": "Stmt1467278441801",
                  "Action": [
                    "s3:GetObject"
                  ],
                  "Effect": "Allow",
                  "Resource": "arn:aws:s3:::%s/*",
                  "Principal": {
                    "AWS": [
                      "*"
                    ]
                  }
                },
                {
                  "Sid": "Stmt14672784418012",
                  "Action": [
                    "s3:ListBucket"
                  ],
                  "Effect": "Allow",
                  "Resource": "arn:aws:s3:::%s",
                  "Principal": {
                    "AWS": [
                      "*"
                    ]
                  }
                },
                {
                  "Sid": "Stmt14672784418013",
                  "Action": [
                    "s3:GetBucketLocation"
                  ],
                  "Effect": "Allow",
                  "Resource": "arn:aws:s3:::%s",
                  "Principal": {
                    "AWS": [
                      "*"
                    ]
                  }
                }
              ]
            }""" % (s3bucket, s3bucket, s3bucket,)

            response = bucket.set_policy(policy_json) 

    else:
        # create the default queue or the queue passed as a parameter          
        q = conn.create_queue(sqsname)
        queue_name = conn.get_queue(sqsname)
  
        conn.set_queue_attribute(queue_name, 'Policy', json.dumps({
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
                  "Resource": "arn:aws:sqs:" + region + ":" + acnumber + ":" + sqsname,
                  "Condition": {
                    "ArnLike": {
                      "aws:SourceArn": "arn:aws:s3:*:*:" + s3bucket
                    }
                  }
                },
                {
                  "Sid": "GiveAccessToLoggly",
                  "Effect": "Allow",
                  "Principal": {
                    "AWS": "arn:aws:iam::" + acnumber + ":root"
                  },
                  "Action": "SQS:*",
                  "Resource": "arn:aws:sqs:" + region + ":" + acnumber + ":" + sqsname
                }
              ]
            }))

        # s3 bucket notification configuration 
        client = boto3.client('s3', region)

        response = client.put_bucket_notification_configuration(
            Bucket=s3bucket,
            NotificationConfiguration={ 
                "QueueConfigurations": [{
                 "Id": "Notification",
                 "Events": ["s3:ObjectCreated:*"],
                 "QueueArn": "arn:aws:sqs:" + region + ":" + acnumber + ":" + sqsname
            }],
            }
        )

        policy_json = """{
          "Id": "Policy1467278443739",
          "Version": "2012-10-17",
          "Statement": [
            {
              "Sid": "Stmt1467278441801",
              "Action": [
                "s3:GetObject"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s/*",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            },
            {
              "Sid": "Stmt14672784418012",
              "Action": [
                "s3:ListBucket"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            },
            {
              "Sid": "Stmt14672784418013",
              "Action": [
                "s3:GetBucketLocation"
              ],
              "Effect": "Allow",
              "Resource": "arn:aws:s3:::%s",
              "Principal": {
                "AWS": [
                  "*"
                ]
              }
            }
          ]
        }""" % (s3bucket, s3bucket, s3bucket,)

        response = bucket.set_policy(policy_json)


print "Queue Name"
print sqsname

iam = boto.connect_iam(access_key, secret_key)


if user != None and user != '':
    
    try:
        response  = iam.get_user(user)
        if 'get_user_response' in response:
            print 'User already exists, use a different user name'
            sys.exit()
        
    except BotoServerError, e:
        if "The user with name" in e.message and "cannot be found" in e.message :
    
            # create an IAM user
            response = iam.create_user(user)

            # create an access key
            iam.create_access_key(user)
            response = iam.create_access_key(user)
            loggly_access_key = response.access_key_id
            loggly_secret_key = response.secret_access_key

            print "Access key for Loggly"

            print loggly_access_key

            print "Secret key for Loggly"

            print loggly_secret_key


            policy_json = """{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "Sidtest",
                    "Effect": "Allow",
                    "Action": [
                        "sqs:*"
                    ],
                    "Resource": [
                        "arn:aws:sqs:%s:%s:%s"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action":[
                    "s3:ListBucket",
                    "s3:GetObject",
                    "s3:GetBucketLocation"
                 ],
                    "Resource": ["arn:aws:s3:::%s"]
                }
            ]
            }""" % (region, acnumber, sqsname, s3bucket,)


            response = iam.put_user_policy(user,
                                           'TestPolicy',
                                           policy_json)
        else: 
            
            print(e.message)     

else:   
    # create an IAM user
    user = 'loggly-s3-user'

    try:
        response  = iam.get_user(user)
        if 'get_user_response' in response:
            print 'The default user \'loggly-s3-user\' which the script creates already exists, please pass a different user name with --user parameter'
            sys.exit()
        
    except BotoServerError, e:
        if "The user with name" in e.message and "cannot be found" in e.message :

            response = iam.create_user(user)

            # create an access key
            iam.create_access_key(user)
            response = iam.create_access_key(user)
            loggly_access_key = response.access_key_id
            loggly_secret_key = response.secret_access_key

            print "Access key for Loggly"

            print loggly_access_key

            print "Secret key for Loggly"

            print loggly_secret_key

            policy_json = """{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "Sidtest",
                    "Effect": "Allow",
                    "Action": [
                        "sqs:*"
                    ],
                    "Resource": [
                        "arn:aws:sqs:%s:%s:%s"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action":[
                    "s3:ListBucket",
                    "s3:GetObject",
                    "s3:GetBucketLocation"
                 ],
                    "Resource": ["arn:aws:s3:::%s"]
                }
            ]
            }""" % (region, acnumber, sqsname, s3bucket,)

            response = iam.put_user_policy(user,
                                           'TestPolicy',
                                           policy_json)