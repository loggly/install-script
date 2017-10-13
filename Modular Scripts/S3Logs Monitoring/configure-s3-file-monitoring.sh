#!/bin/bash

echo "INFO: Downloading dependencies - configure-file-monitoring.sh"
curl -s -o configure-file-monitoring.sh https://www.loggly.com/install/configure-file-monitoring.sh
source configure-file-monitoring.sh "being-invoked"

##########  Variable Declarations - Start  ##########
#name of the current script
SCRIPT_NAME=configure-s3-file-monitoring.sh
#version of the current script
SCRIPT_VERSION=1.5

#s3 bucket name to configure
LOGGLY_S3_BUCKET_NAME=

#alias name, will be used as tag & state file name etc. provided by user
LOGGLY_S3_ALIAS=
FILE_ALIAS=
STATE_FILE_ALIAS=

#file as tag sent with the logs
LOGGLY_FILE_TAG="s3file"

#format name for the conf file. Can be set by calling script
CONF_FILE_FORMAT_NAME="LogglyFormatS3"

#file alias provided by the user
APP_TAG="\"s3file-alias\":\"\""

#name and location of syslog file
FILE_SYSLOG_CONFFILE=

#name and location of syslog backup file
FILE_SYSLOG_CONFFILE_BACKUP=

#holds variable if any of the file is configured
IS_ANY_FILE_CONFIGURED="false"

#value for temp directory
TEMP_DIR=

IS_S3CMD_CONFIGURED_BY_SCRIPT="false"

MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure a file is available at https://www.loggly.com/docs/file-monitoring/. Rsyslog troubleshooting instructions are available at https://www.loggly.com/docs/troubleshooting-rsyslog/"

##########  Variable Declarations - End  ##########

# executing the script for loggly to install and configure syslog
installLogglyConfForS3() {
  #log message indicating starting of Loggly configuration
  logMsgToConfigSysLog "INFO" "INFO: Initiating configure Loggly for file monitoring."

  #check if the provided alias is correct or not
  checkIfS3AliasAlreadyTaken

  #check if the linux environment is compatible for Loggly
  checkLinuxLogglyCompatibility

  #check if s3cmd utility is installed and configured
  checkIfS3cmdInstalledAndConfigured

  #check if s3bucket is valid
  checkIfValidS3Bucket

  #create temporary directory
  createTempDir

  #download S3 files from bucket to temp directory
  downloadS3Bucket

  #invoke file monitoring on each file after checking if it is a text file or not
  invokeS3FileMonitoring

  #install a cron job to sync the downloaded files after each 5 minutes
  installCronToSyncS3BucketPeriodically

  if [ "$IS_ANY_FILE_CONFIGURED" != "false" ]; then
    #check if s3 logs made it to loggly
    checkIfS3LogsMadeToLoggly
  else
    logMsgToConfigSysLog "WARN" "WARN: Did not find any files to configure. Nothing to do."
  fi

}

#executing script to remove loggly configuration for S3 files
removeLogglyConfForS3() {
  logMsgToConfigSysLog "INFO" "INFO: Initiating rollback."

  #check if the user has root permission to run this script
  checkIfUserHasRootPrivileges

  #check if the OS is supported by the script. If no, then exit
  checkIfSupportedOS

  #check if alias provided is the correct one
  checkIfS3AliasExist

  #remove file monitoring
  removeS3FileMonitoring

  #delete the s3 sync cron from the crontab
  deleteS3CronFromCrontab

  #delete temporary directory if exists
  TEMP_DIR=/tmp/s3monitoring/$LOGGLY_S3_ALIAS
  deleteTempDir

  #log success message
  logMsgToConfigSysLog "INFO" "INFO: Rollback completed."
}

checkIfS3AliasAlreadyTaken() {
  if ls $RSYSLOG_ETCDIR_CONF/*$LOGGLY_S3_ALIAS.conf &>/dev/null; then
    logMsgToConfigSysLog "ERROR" "ERROR: $LOGGLY_S3_ALIAS is already taken. Please try with another one."
    exit 1
  fi
}

#check if s3cmd utility is installed and configured
checkIfS3cmdInstalledAndConfigured() {
  if hash s3cmd 2>/dev/null; then
    checkIfS3cmdConfigured
  else
    logMsgToConfigSysLog "INFO" "INFO: s3cmd is not present on your system. Setting it up on your system"
    downloadS3cmd
    configureS3cmd
  fi
}

#check if s3cmd utility is configured
checkIfS3cmdConfigured() {
  var=$(sudo s3cmd ls 2>/dev/null)
  if [ "$var" != "" ]; then
    if [ "$IS_S3CMD_CONFIGURED_BY_SCRIPT" == "false" ]; then
      logMsgToConfigSysLog "INFO" "INFO: s3cmd is already configured on your system"
    else
      logMsgToConfigSysLog "INFO" "INFO: s3cmd configured successfully"
    fi
  else
    if [ "$IS_S3CMD_CONFIGURED_BY_SCRIPT" == "false" ]; then
      logMsgToConfigSysLog "INFO" "INFO: s3cmd is not configured on your system. Trying to configure."
      configureS3cmd
    else
      logMsgToConfigSysLog "ERROR" "ERROR: s3cmd is not configured correctly. Please configure s3cmd using command s3cmd --configure"
      exit 1
    fi
  fi
}

#download and install s3cmd
downloadS3cmd() {
  #checking if the Linux is yum based or apt-get based
  YUM_BASED=$(command -v yum)
  APT_GET_BASED=$(command -v apt-get)

  if [ "$YUM_BASED" != "" ]; then
    sudo yum install s3cmd || {
      logMsgToConfigSysLog "ERROR" "ERROR: s3cmd installation failed on $LINUX_DIST. Please ensure you have EPEL installed."
      exit 1
    }
  elif [ "$APT_GET_BASED" != "" ]; then
    sudo apt-get install s3cmd || {
      logMsgToConfigSysLog "ERROR" "ERROR: s3cmd installation failed on $LINUX_DIST."
      exit 1
    }
  else
    logMsgToConfigSysLog "ERROR" "ERROR: s3cmd installation failed on $LINUX_DIST."
    exit 1
  fi
}

#configure s3cmd
configureS3cmd() {
  sudo s3cmd --configure
  IS_S3CMD_CONFIGURED_BY_SCRIPT="true"
  #check if s3cmd configured successfully now
  checkIfS3cmdConfigured
}

#check if s3bucket is valid
checkIfValidS3Bucket() {
  #check if valid Bucket name
  if [[ $LOGGLY_S3_BUCKET_NAME != s3://* ]]; then
    logMsgToConfigSysLog "Error" "Error: Invalid s3 Bucket name. Bucket name should start with 's3://'"
    exit 1
  fi

  if [ "$LOGGLY_S3_BUCKET_NAME" != "" ]; then
    logMsgToConfigSysLog "INFO" "INFO: Check if valid S3 Bucket name."
    BUCKET_INFO=$(sudo s3cmd ls -r $LOGGLY_S3_BUCKET_NAME 2>&1)
    case $BUCKET_INFO in
    ERROR*)
      #logging actual error message returned by s3cmd
      logMsgToConfigSysLog "ERROR" "$BUCKET_INFO"
      exit 1
      ;;
    "")
      logMsgToConfigSysLog "ERROR" "ERROR: No files found in the S3 Bucket $LOGGLY_S3_BUCKET_NAME."
      exit 1
      ;;
    *)
      logMsgToConfigSysLog "INFO" "INFO: '$LOGGLY_S3_BUCKET_NAME' is a valid Bucket and accessible."
      ;;
    esac
  fi
}

createTempDir() {
  TEMP_DIR=/tmp/s3monitoring/$LOGGLY_S3_ALIAS
  if [ -d "$TEMP_DIR" ]; then
    if [ "$(ls -A $TEMP_DIR)" ]; then
      logMsgToConfigSysLog "WARN" "WARN: There are some files/folders already present in $TEMP_DIR. If you continue, the files currently inside the $TEMP_DIR will also be configured to send logs to loggly."
      if [ "$SUPPRESS_PROMPT" == "false" ]; then
        while true; do
          read -p "Would you like to continue now anyway? (yes/no)" yn
          case $yn in
          [Yy]*)
            break
            ;;
          [Nn]*)
            logMsgToConfigSysLog "INFO" "INFO: Discontinuing with s3 file monitoring configuration."
            exit 1
            break
            ;;
          *) echo "Please answer yes or no." ;;
          esac
        done
      fi
    fi
  else
    if [ -d "/tmp/s3monitoring" ]; then
      mkdir /tmp/s3monitoring/$LOGGLY_S3_ALIAS
    else
      mkdir /tmp/s3monitoring
      mkdir /tmp/s3monitoring/$LOGGLY_S3_ALIAS
    fi
  fi
}

downloadS3Bucket() {
  if [ "$LOGGLY_S3_BUCKET_NAME" != "" ]; then
    #Files are downloaded in nested directory
    cd $TEMP_DIR
    echo "Downloading files, may take some time..."
    sudo s3cmd get -r -f $LOGGLY_S3_BUCKET_NAME >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      logMsgToConfigSysLog "ERROR" "ERROR: Error downloading files recursively from $LOGGLY_S3_BUCKET_NAME"
      exit 1
    fi
  fi
}

invokeS3FileMonitoring() {
  dir=/tmp/s3monitoring/$LOGGLY_S3_ALIAS
  LOGGLY_FILE_TO_MONITOR=$dir

  configureDirectoryFileMonitoring

  IS_ANY_FILE_CONFIGURED="true"

  if [ "$IS_ANY_FILE_CONFIGURED" != "false" ]; then
    restartRsyslog
  fi
}

installCronToSyncS3BucketPeriodically() {
  if [ "$SUPPRESS_PROMPT" == "false" ]; then
    while true; do
      read -p "Would you like install a Cron job to sync the files currently in your bucket every 5 minutes? (yes/no)" yn
      case $yn in
      [Yy]*)
        doS3CronInstallation
        break
        ;;
      [Nn]*)
        logMsgToConfigSysLog "INFO" "INFO: Skipping Cron installation."
        break
        ;;
      *) echo "Please answer yes or no." ;;
      esac
    done
  else
    doS3CronInstallation
  fi
}

doS3CronInstallation() {
  #copying .s3cfg file to /root so that it can be used by crontab for sync
  if ! sudo test -f "/root/.s3cfg"; then
    sudo cp $HOME/.s3cfg /root
  fi

  CRON_FILE="/tmp/s3monitoring/cron_$LOGGLY_S3_ALIAS"
  CRON_SYNC_PATH="/tmp/s3monitoring/$LOGGLY_S3_ALIAS"

  #checking if the provided s3 path if of directory or file
  IS_DIR="true"
  BUCKET_URL_LAST_VALUE=$(echo ${LOGGLY_S3_BUCKET_NAME##*/})

  if [ "$BUCKET_URL_LAST_VALUE" != "" ]; then
    for fle in $(find $CRON_SYNC_PATH -name $BUCKET_URL_LAST_VALUE); do
      if [ -f $fle ]; then
        IS_DIR="false"
        break
      fi
    done
  fi

  #adding file name to the sync folder as the bucket path is
  #provided upto a file
  if [ "$IS_DIR" == "false" ]; then
    CRON_SYNC_PATH="$CRON_SYNC_PATH/$BUCKET_URL_LAST_VALUE"
  fi

  logMsgToConfigSysLog "INFO" "INFO: Creating a Cron job to sync $LOGGLY_S3_BUCKET_NAME files to $CRON_SYNC_PATH in every five minutes."

  #setting up cron job
  CRON_JOB_TO_SYNC_S3_BUCKET="*/5 * * * * s3cmd sync $LOGGLY_S3_BUCKET_NAME --preserve $CRON_SYNC_PATH"

  EXISTING_CRONS=$(sudo crontab -l 2>&1)
  case $EXISTING_CRONS in
  no*) ;;

  *)
    echo "$EXISTING_CRONS" >>$CRON_FILE
    ;;
  esac

  echo "$CRON_JOB_TO_SYNC_S3_BUCKET" >>$CRON_FILE
  sudo crontab $CRON_FILE
  sudo rm -fr $CRON_FILE
}

deleteTempDir() {
  if [ -d "$TEMP_DIR" ]; then
    sudo rm -fr $TEMP_DIR
  fi
}

checkIfS3LogsMadeToLoggly() {
  counter=1
  maxCounter=10

  fileInitialLogCount=0
  fileLatestLogCount=0
  queryParam="syslog.appName%3A%2A$LOGGLY_S3_ALIAS&from=-5m&until=now&size=1"

  queryUrl="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$queryParam"
  logMsgToConfigSysLog "INFO" "INFO: Search URL: $queryUrl"

  logMsgToConfigSysLog "INFO" "INFO: Verifying if the logs made it to Loggly."
  logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
  #get the final count of file logs for past 5 minutes
  searchAndFetch fileLatestLogCount "$queryUrl"
  let counter=$counter+1

  while [ "$fileLatestLogCount" -le "$fileInitialLogCount" ]; do
    echo "INFO: Did not find the test log message in Loggly's search yet. Waiting for 30 secs."
    sleep 30
    echo "INFO: Done waiting. Verifying again."
    logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
    searchAndFetch fileLatestLogCount "$queryUrl"
    let counter=$counter+1
    if [ "$counter" -gt "$maxCounter" ]; then
      logMsgToConfigSysLog "ERROR" "ERROR: S3 logs did not make to Loggly in time. Please check network and firewall settings and retry."
      exit 1
    fi
  done

  if [ "$fileLatestLogCount" -gt "$fileInitialLogCount" ]; then
    if [ "$LOGGLY_S3_BUCKET_NAME" != "" ]; then
      logMsgToConfigSysLog "SUCCESS" "SUCCESS: Logs successfully transferred to Loggly! You are now sending $LOGGLY_S3_BUCKET_NAME logs to Loggly."

    fi
  fi
}

checkIfS3AliasExist() {
  if ! ls $RSYSLOG_ETCDIR_CONF/*$LOGGLY_S3_ALIAS.conf &>/dev/null; then
    #logMsgToConfigSysLog "INFO" "INFO: $LOGGLY_S3_ALIAS found."
    #else
    logMsgToConfigSysLog "ERROR" "ERROR: $LOGGLY_S3_ALIAS does not exist. Please provide the correct s3 alias."
    exit 1
  fi
}

removeS3FileMonitoring() {
  FILES=$RSYSLOG_ETCDIR_CONF/*$LOGGLY_S3_ALIAS.conf
  for f in $FILES; do
    aliasName=${f##*/}
    aliasName=${aliasName%.*}
    aliasName=${aliasName#21-filemonitoring-}

    LOGGLY_FILE_TO_MONITOR_ALIAS=$aliasName
    constructFileVariables
    remove21ConfFile
  done
  echo "INFO: Removed all the modified files."
  restartRsyslog
}

deleteS3CronFromCrontab() {
  logMsgToConfigSysLog "INFO" "INFO: Deleting sync Cron."
  sudo crontab -l | grep -v "/tmp/s3monitoring/$LOGGLY_S3_ALIAS" | crontab -
}

#display usage syntax
usage() {
  cat <<EOF
usage: configure-s3-file-monitoring [-a loggly auth account or subdomain] [-t loggly token (optional)] [-u username] [-p password (optional)] [-s3url s3bucketname ] [-s3l s3alias] [-s suppress prompts {optional)]
usage: configure-s3-file-monitoring [-a loggly auth account or subdomain] [-r to rollback] [-s3l s3alias]
usage: configure-s3-file-monitoring [-h for help]
EOF
}

##########  Get Inputs from User - Start  ##########

if [ $# -eq 0 ]; then
  usage
  exit
else
  while [ "$1" != "" ]; do
    case $1 in
    -t | --token)
      shift
      LOGGLY_AUTH_TOKEN=$1
      echo "AUTH TOKEN $LOGGLY_AUTH_TOKEN"
      ;;
    -a | --account)
      shift
      LOGGLY_ACCOUNT=$1
      echo "Loggly account or subdomain: $LOGGLY_ACCOUNT"
      ;;
    -u | --username)
      shift
      LOGGLY_USERNAME=$1
      echo "Username is set"
      ;;
    -p | --password)
      shift
      LOGGLY_PASSWORD=$1
      ;;
    -r | --rollback)
      LOGGLY_ROLLBACK="true"
      ;;
    -s3url | --s3bucketname)
      shift
      LOGGLY_S3_BUCKET_NAME=$1
      echo "S3 Bucket Name: $LOGGLY_S3_BUCKET_NAME"
      ;;

    -s3l | --s3alias)
      shift
      LOGGLY_S3_ALIAS=$1
      FILE_ALIAS=$LOGGLY_S3_ALIAS
      STATE_FILE_ALIAS=$LOGGLY_S3_ALIAS
      echo "File alias: $FILE_ALIAS"
      ;;
    -s | --suppress)
      SUPPRESS_PROMPT="true"
      ;;
    -h | --help)
      usage
      exit
      ;;
    esac
    shift
  done
fi

if [ "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" -a "$LOGGLY_S3_ALIAS" != "" -a \( "$LOGGLY_S3_BUCKET_NAME" != "" \) ]; then
  if [ "$LOGGLY_PASSWORD" = "" ]; then
    getPassword
  fi
  installLogglyConfForS3
elif [ "$LOGGLY_ROLLBACK" != "" -a "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_S3_ALIAS" != "" ]; then
  removeLogglyConfForS3
else
  usage
fi
##########  Get Inputs from User - End  ##########
