import argparse
import json
import sys

import boto3
import botocore


class AWS:
    """Encapsulates AWS session with resources (S3 bucket, SQS queue, IAM user)."""
    QUEUE_BUCKET_POLICY_JSON = """
    {
          "Effect": "Allow",
          "Principal": {
            "AWS": "*"
          },
          "Action": "SQS:SendMessage",
          "Resource": "%(queue_arn)s",
          "Condition": {
            "ArnLike": {
              "aws:SourceArn": "arn:aws:s3:::%(bucket_name)s"
            }
          }
    }
    """

    QUEUE_ACCOUNT_POLICY_JSON = """
        {
              "Effect": "Allow",
              "Principal": {
                "AWS": "arn:aws:iam::%(account_number)s:root"
              },
              "Action": [
                "sqs:ReceiveMessage",
                "sqs:GetQueueUrl",
                "sqs:GetQueueAttributes",
                "sqs:DeleteMessage"
              ],
              "Resource": "%(queue_arn)s"
        }
        """

    QUEUE_POLICY_WHOLE_JSON = """
        {
            "Version": "2012-10-17",
            "Statement": [%s, %s]
        }
        """ % (QUEUE_BUCKET_POLICY_JSON, QUEUE_ACCOUNT_POLICY_JSON)

    QUEUE_CONFIGURATIONS_JSON = """
    {
        "QueueConfigurations": [
            {
                "Id": "LogglyS3Notification",
                "Events": ["s3:ObjectCreated:*"],
                "QueueArn": "%(queue_arn)s"
            }
        ]
    }
    """

    USER_POLICY_BUCKET_JSON = """
    {
        "Effect": "Allow",
        "Action":[
            "s3:ListBucket",
            "s3:GetObject",
            "s3:GetBucketLocation"
         ],
        "Resource": [
          "arn:aws:s3:::%(bucket_name)s/*",
          "arn:aws:s3:::%(bucket_name)s"
        ]
    }
    """

    USER_POLICY_QUEUE_JSON = """
    {
        "Effect": "Allow",
        "Action": [
            "sqs:ReceiveMessage",
            "sqs:GetQueueUrl",
            "sqs:GetQueueAttributes",
            "sqs:DeleteMessage"
        ],
        "Resource": [
            "%(queue_arn)s"
        ]
    }
    """

    USER_POLICY_WHOLE_JSON = """{
        "Version": "2012-10-17",
        "Statement": [%s, %s]
    }
    """ % (USER_POLICY_BUCKET_JSON, USER_POLICY_QUEUE_JSON)

    class PolicyDocument:
        """Represents the JSON AWS policy."""

        def __init__(self, policy_document):
            self._policy_document = policy_document

        def get_policy(self):
            return self._policy_document

        def add_statement_or_resource(self, action, resource, statement_to_add):
            statement, index = self.get_statement(action)
            if not statement:
                # No statement contains required action, create a new statement.
                self.add_statement(statement_to_add)
            else:
                # Required action is contained in a statement, check resource.
                if not self.get_statement(action, resource)[0]:
                    # Required resource is missing, add it to the statement with the required action.
                    self.add_resource_to_statement(resource, index)

        def add_statement(self, statement, index=None):
            if index is not None:
                self._policy_document['Statement'][index] = statement
            else:
                self._policy_document['Statement'].append(statement)

        def get_statement(self, action=None, resource=None, effect='Allow'):
            """Returns a statement with matching action, resource and effect. For the resource and action it is
            sufficient if it is contained in the list. Statement index is also returned."""

            statements = self._policy_document['Statement']
            for s, i in zip(statements, range(0, len(statements))):
                if s['Effect'] != effect:
                    continue
                if action:
                    s['Action'] = self._make_lowercase(s['Action'])
                    action = self._make_lowercase(action)
                    if not self._compare_fields(s['Action'], action):
                        continue
                if resource:
                    if not self._compare_fields(s['Resource'], resource):
                        continue
                return s, i
            return None, None

        def add_resource_to_statement(self, resource, statement_index):
            statement = self._policy_document['Statement'][statement_index]
            try:
                if isinstance(statement['Resource'], list):
                    statement['Resource'].append(resource)
                else:
                    statement['Resource'] = [statement['Resource'], resource]
            except KeyError:
                statement['Resource'] = resource
            self.add_statement(statement, statement_index)

        def _compare_fields(self, statement_field, given_field):
            if isinstance(statement_field, list):
                if isinstance(given_field, list):
                    if set(statement_field) != set(given_field):
                        return False
                elif given_field not in statement_field:
                    return False
            elif statement_field != given_field:
                return False
            return True

        def _make_lowercase(self, field):
            if isinstance(field, list):
                for i, e in enumerate(field):
                    field[i] = e.lower()
            else:
                field = field.lower()
            return field

    def __init__(self, session, bucket, queue, user, account_id):
        self._session = session
        self._bucket = bucket
        self._queue = queue
        self._user = user
        self._account_id = account_id

    def set_queue_policy(self):
        try:
            queue_policy = json.loads(self._queue.attributes['Policy'])
        except KeyError:
            print('Queue policy not found, creating it')
            params_dict = {'queue_arn': self._queue.attributes['QueueArn'],
                           'bucket_name': self._bucket.name,
                           'account_number': self._account_id}
            self._queue.set_attributes(Attributes={'Policy': self.QUEUE_POLICY_WHOLE_JSON % params_dict})
            return
        pd = self.PolicyDocument(queue_policy)
        self._add_bucket_to_queue_policy(pd)
        self._add_account_access_to_queue_policy(pd)

    def set_bucket_notification(self):
        self._bucket.Notification().put(
            NotificationConfiguration=json.loads(
                self.QUEUE_CONFIGURATIONS_JSON % {'queue_arn': self._queue.attributes['QueueArn']}))

    def set_user_policy(self):
        policy_name = 'LogglyUserPolicy'
        try:
            policy = self._user.Policy(policy_name)
            policy.policy_document  # This raises exception on non existent policy.
        except botocore.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchEntity':
                print('Policy {} not found, creating it'.format(policy_name))
                params_dict = {'queue_arn': self._queue.attributes['QueueArn'], 'bucket_name': self._bucket.name}
                self._user.create_policy(
                    PolicyName=policy_name, PolicyDocument=self.USER_POLICY_WHOLE_JSON % params_dict)
                return
            else:
                raise e
        pd = self.PolicyDocument(policy.policy_document)
        self._add_bucket_to_user_policy(pd)
        self._add_queue_to_user_policy(pd)
        policy.put(PolicyDocument=json.dumps(pd.get_policy()))

    def _add_bucket_to_queue_policy(self, policy_document):
        statement, index = policy_document.get_statement(
            action='sqs:sendmessage', resource=self._queue.attributes['QueueArn'])
        if not statement:
            # Create a whole new statement.
            params_dict = {'queue_arn': self._queue.attributes['QueueArn'], 'bucket_name': self._bucket.name}
            policy_document.add_statement(json.loads(self.QUEUE_BUCKET_POLICY_JSON % params_dict))
        else:
            try:
                bucket_arn = statement['Condition']['ArnLike']['aws:SourceArn']
            except KeyError:
                # A statement with 'sqs:sendmessage' action already exists without ARN condition, no need to add the
                # bucket ARN.
                return
            if isinstance(bucket_arn, list):
                bucket_arn = ",".join(bucket_arn)
            if self._bucket.name in bucket_arn:
                print("Given bucket already exists in queue's policy")
                return
            else:
                # A statement with 'sqs:sendmessage' action and some ARN condition already exists,
                # just append the bucket ARN to its condition.
                bucket_arn += ',arn:aws:s3:::' + self._bucket.name
                statement['Condition']['ArnLike']['aws:SourceArn'] = bucket_arn.split(',')
                policy_document.add_statement(statement, index)
        self._queue.set_attributes(Attributes={'Policy': json.dumps(policy_document.get_policy())})

    def _add_account_access_to_queue_policy(self, policy_document):
        statement, _ = policy_document.get_statement(
            action='sqs:*', resource=self._queue.attributes['QueueArn'])
        if not statement:
            self._queue.add_permission(Label='AccountAccess', AWSAccountIds=[self._account_id], Actions=['*'])

    def _add_bucket_to_user_policy(self, policy_document):
        policy_document.add_statement_or_resource(["s3:ListBucket", "s3:GetObject", "s3:GetBucketLocation"],
                                                  'arn:aws:s3:::' + self._bucket.name,
                                                  self.USER_POLICY_BUCKET_JSON % {'bucket_name': self._bucket.name})
        policy_document.add_statement_or_resource(["s3:ListBucket", "s3:GetObject", "s3:GetBucketLocation"],
                                                  'arn:aws:s3:::' + self._bucket.name + '/*',
                                                  self.USER_POLICY_BUCKET_JSON % {'bucket_name': self._bucket.name})

    def _add_queue_to_user_policy(self, policy_document):
        queue_arn = self._queue.attributes['QueueArn']
        policy_document.add_statement_or_resource(
            'sqs:*', queue_arn, self.USER_POLICY_QUEUE_JSON % {'queue_arn': queue_arn})


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--acnumber", dest="acnumber", help="account number")
    parser.add_argument("--s3bucket", dest="s3bucket", help="s3 bucket name")
    parser.add_argument("--user", dest="user", default='loggly-s3-user', help="user")
    parser.add_argument("--admin", dest="admin", default="default", help="admin user name")
    parser.add_argument("--sqsname", dest="sqsname", default='loggly-s3-queue', help="sqsname")

    args = parser.parse_args()

    if not args.s3bucket:
        parser.error("S3 bucket name not provided")

    if not args.acnumber:
        parser.error("Account number not provided")

    if not args.acnumber.isdigit():
        parser.error("Please check your account number, it should only contain digits, no other characters.")

    return args


def get_bucket(session, bucket_name):
    bucket = session.resource('s3').Bucket(bucket_name)
    if bucket.creation_date is None:
        region = boto3.session.Session().region_name
        print('\033[91m', 'S3 bucket {} does not exist, please create it and run the script again. Also, make sure the S3 bucket and the SQS queue are in the same region. Current session region: {}'.format(bucket_name, region))
        sys.exit(1)
    return bucket


def get_queue(session, queue_name):
    sqs = session.resource('sqs')
    try:
        queue = sqs.get_queue_by_name(QueueName=queue_name)
        print('Queue {} already exists'.format(queue_name))
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == 'AWS.SimpleQueueService.NonExistentQueue':
            print('Queue {} does not exist, creating it.'.format(queue_name))
            queue = sqs.create_queue(QueueName=queue_name)
            print('Queue url: {}'.format(queue.url))
        else:
            raise e
    print('Queue name\n{}'.format(queue_name))
    return queue


def get_user(session, user_name):
    iam = session.resource('iam')
    try:
        user = iam.User(user_name)
        user.arn  # This raises exception on non existent user.
        print('IAM user {} already exists'.format(user_name))
        print('Please provide the access key and secret key for the IAM user {} in the form fields'.format(user_name))
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchEntity':
            print("IAM user {} does not exist, creating it".format(user_name))
            user = iam.create_user(UserName=user_name)
            access_key_pair = user.create_access_key_pair()
            print("Access key for Loggly")
            print(access_key_pair.access_key_id)
            print("Secret key for Loggly")
            print(access_key_pair.secret_access_key)
            print('Please save the above credentials')
        else:
            raise e
    return user


def main():
    args = get_args()
    try:
        session = boto3.Session(profile_name=args.admin)
        bucket = get_bucket(session, args.s3bucket)
        queue = get_queue(session, args.sqsname)
        user = get_user(session, args.user)
        aws = AWS(session, bucket, queue, user, args.acnumber)
        aws.set_queue_policy()
        aws.set_bucket_notification()
        aws.set_user_policy()
    except Exception as e:
        print(e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
