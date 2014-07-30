#!/bin/bash

#downloads configure-linux.sh
#echo "INFO: Downloading dependencies - configure-file-monitoring.sh"
#curl -s -o configure-linux.sh https://raw.githubusercontent.com/psquickitjayant/install-script/master/Linux%20Script/configure-linux.sh
source configure-file-monitoring.sh "being-invoked"

##########  Variable Declarations - Start  ##########
#name of the current script
SCRIPT_NAME=configure-s3-file-monitoring.sh
#version of the current script
SCRIPT_VERSION=1.0

#s3 bucket name to configure
LOGGLY_S3_BUCKET_NAME=

#s3 bucket file to configure
LOGGLY_S3_FILE_NAME=

#alias name, will be used as tag & state file name etc. provided by user
LOGGLY_S3_ALIAS=

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

MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure a file is available at https://www.loggly.com/docs/file-monitoring/"

##########  Variable Declarations - End  ##########

# executing the script for loggly to install and configure syslog
installLogglyConfForS3()
{
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

	#check if s3bucket file is valid
	checkIfValidS3File
	
	#configure loggly for Linux
	installLogglyConf
	
	#create temporary directory
	createTempDir

	#download S3 files from bucket to temp directory
	downloadS3Bucket

	#download S3 file to temp directory
	downloadS3File

	#invoke file monitoring on each file after checking if it is a text file or not
	invokeS3FileMonitoring
	
	if [ "$IS_ANY_FILE_CONFIGURED" != "false" ]; then
		#check if s3 logs made it to loggly
		checkIfS3LogsMadeToLoggly
	else
		logMsgToConfigSysLog "WARN" "WARN: Did not find any files to configure. Nothing to do."
	fi
	
	#delete temporary directory
	deleteTempDir
}


#executing script to remove loggly configuration for S3 files
removeLogglyConfForS3()
{
	logMsgToConfigSysLog "INFO" "INFO: Initiating rollback."

	#check if the user has root permission to run this script
	checkIfUserHasRootPrivileges

	#check if the OS is supported by the script. If no, then exit
	checkIfSupportedOS

	#check if alias provided is the correct one
	checkIfS3AliasExist

	#remove file monitoring
	removeS3FileMonitoring

	#log success message
	logMsgToConfigSysLog "INFO" "INFO: Rollback completed."
}

checkIfS3AliasAlreadyTaken()
{
	if ls $RSYSLOG_ETCDIR_CONF/*$LOGGLY_S3_ALIAS.conf &> /dev/null; then
		logMsgToConfigSysLog "ERROR" "ERROR: $LOGGLY_S3_ALIAS is already taken. Please try with another one."
		exit 1
	fi
}

#check if s3cmd utility is installed and configured
checkIfS3cmdInstalledAndConfigured()
{
	if hash s3cmd 2>/dev/null; then
		checkIfS3cmdConfigured
    else
        logMsgToConfigSysLog "INFO" "INFO: s3cmd is not present on your system. Setting it up on your system"
		downloadS3cmd
		configureS3cmd
    fi
}

#check if s3cmd utility is configured
checkIfS3cmdConfigured()
{
	var=$(s3cmd ls 2>/dev/null)
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
downloadS3cmd()
{
	#checking if the Linux is yum based or apt-get based
	YUM_BASED=$(command -v yum)
	APT_GET_BASED=$(command -v apt-get)
	
	if [ "$YUM_BASED" != "" ]; then
		sudo yum install s3cmd || { logMsgToConfigSysLog "ERROR" "ERROR: s3cmd installation failed on $LINUX_DIST. Please ensure you have EPEL installed." ; exit 1; }
	elif [ "$APT_GET_BASED" != "" ]; then
		sudo apt-get install s3cmd || { logMsgToConfigSysLog "ERROR" "ERROR: s3cmd installation failed on $LINUX_DIST." ; exit 1; }
	else
		logMsgToConfigSysLog "ERROR" "ERROR: s3cmd installation failed on $LINUX_DIST."
		exit 1
	fi
}

#configure s3cmd
configureS3cmd()
{
	s3cmd --configure
	IS_S3CMD_CONFIGURED_BY_SCRIPT="true"
	#check if s3cmd configured successfully now
	checkIfS3cmdConfigured
}

#check if s3bucket is valid
checkIfValidS3Bucket()
{
	if [ "$LOGGLY_S3_BUCKET_NAME" != "" ]; then
		logMsgToConfigSysLog "INFO" "INFO: Check if valid S3 Bucket name."
		sudo s3cmd ls -r $LOGGLY_S3_BUCKET_NAME > /dev/null 2>&1 || { logMsgToConfigSysLog "ERROR" "ERROR: Invalid S3 Bucket name" ; exit 1; }
	fi
}

checkIfValidS3File()
{
	if [ "$LOGGLY_S3_FILE_NAME" != "" ]; then
		logMsgToConfigSysLog "INFO" "INFO: Check if valid S3 file name."	
		sudo s3cmd ls $LOGGLY_S3_FILE_NAME > /dev/null 2>&1 || { logMsgToConfigSysLog "ERROR" "ERROR: Invalid S3 File name" ; exit 1; }
	fi
}

createTempDir()
{
	TEMP_DIR=/tmp/$LOGGLY_S3_ALIAS
	if [ -d "$TEMP_DIR" ]; then
		if [ "$(ls -A $TEMP_DIR)" ]; then
			logMsgToConfigSysLog "WARN" "WARN: There are some files/folders already present in $TEMP_DIR. If you continue, the files currently inside the $TEMP_DIR will also be configured to send logs to loggly."
			while true; do
				read -p "Would you like to continue now anyway? (yes/no)" yn
				case $yn in
					[Yy]* )
					break;;
					[Nn]* ) 
					logMsgToConfigSysLog "INFO" "INFO: Discontinuing with s3 file monitoring configuration."
					exit 1
					break;;
					* ) echo "Please answer yes or no.";;
				esac
			done
		fi		
	else
		mkdir /tmp/$LOGGLY_S3_ALIAS
	fi
}

downloadS3Bucket()
{
	if [ "$LOGGLY_S3_BUCKET_NAME" != "" ]; then
		#Files are downloaded in nested directory
		cd $TEMP_DIR
		echo "Downloading files, may take some time..."
		s3cmd get -r -f $LOGGLY_S3_BUCKET_NAME > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			logMsgToConfigSysLog "ERROR" "ERROR: Error downloading files recursively from $LOGGLY_S3_BUCKET_NAME"
			exit 1
		fi
	fi
}

downloadS3File()
{
	if [ "$LOGGLY_S3_FILE_NAME" != "" ]; then
		cd $TEMP_DIR
		echo "Downloading file, may take some time..."
		s3cmd get -f $LOGGLY_S3_FILE_NAME > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			logMsgToConfigSysLog "ERROR" "ERROR: Error downloading file $LOGGLY_S3_FILE_NAME"
			exit 1
		fi
	fi
}

invokeS3FileMonitoring()
{
	dir=/tmp/$LOGGLY_S3_ALIAS
	#TODO: Not supporting multiple files with same name in different directories
	#only supporting file with naming convention *.*
	for f in $(find $dir -name '*')
	do
		fileNameWithExt=${f##*/}
        uniqueFileName=$(echo "$fileNameWithExt" | tr . _)
		var=$(file $f)

		if [ ${var##*\ } == "text" -o ${var##*\ } == "Text" ]; then

			LOGGLY_FILE_TO_MONITOR_ALIAS=$uniqueFileName-$LOGGLY_S3_ALIAS
			LOGGLY_FILE_TO_MONITOR=$f
			constructFileVariables
			checkLogFileSize $LOGGLY_FILE_TO_MONITOR
			write21ConfFileContents
			IS_ANY_FILE_CONFIGURED="true"

		else
			logMsgToConfigSysLog "WARN" "WARN: File $fileNameWithExt is not a text file. Ignoring."
		fi
	done
	
	if [ "$IS_ANY_FILE_CONFIGURED" != "false" ]; then
		restartRsyslog
	fi
}

deleteTempDir()
{
	rm -fr $TEMP_DIR
}

checkIfS3LogsMadeToLoggly()
{
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
			logMsgToConfigSysLog "ERROR" "ERROR: Logs did not make to Loggly in time. Please check your token & network/firewall settings and retry."
			exit 1
		fi
	done

	if [ "$fileLatestLogCount" -gt "$fileInitialLogCount" ]; then
		if [ "$LOGGLY_S3_BUCKET_NAME" != "" ]; then
			logMsgToConfigSysLog "SUCCESS" "SUCCESS: Logs successfully transferred to Loggly! You are now sending $LOGGLY_S3_BUCKET_NAME bucket logs to Loggly."
		else
			logMsgToConfigSysLog "SUCCESS" "SUCCESS: Logs successfully transferred to Loggly! You are now sending $LOGGLY_S3_FILE_NAME logs to Loggly."
		fi
	fi
}

checkIfS3AliasExist()
{
	if ! ls $RSYSLOG_ETCDIR_CONF/*$LOGGLY_S3_ALIAS.conf &> /dev/null; then
		#logMsgToConfigSysLog "INFO" "INFO: $LOGGLY_S3_ALIAS found."
	#else
		logMsgToConfigSysLog "ERROR" "ERROR: $LOGGLY_S3_ALIAS does not exist. Please provide the correct s3 alias."
		exit 1
	fi
}

removeS3FileMonitoring()
{
	FILES=$RSYSLOG_ETCDIR_CONF/*$LOGGLY_S3_ALIAS.conf
	for f in $FILES
	do
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

#display usage syntax
usage()
{
cat << EOF
usage: configure-s3-file-monitoring [-a loggly auth account or subdomain] [-t loggly token (optional)] [-u username] [-p password (optional)] [-s3b s3bucketname or -s3f s3filename] [-s3l s3alias]
usage: configure-s3-file-monitoring [-a loggly auth account or subdomain] [-r to rollback] [-l filealias]
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
		-t | --token ) shift
			LOGGLY_AUTH_TOKEN=$1
			echo "AUTH TOKEN $LOGGLY_AUTH_TOKEN"
		;;
		-a | --account ) shift
			LOGGLY_ACCOUNT=$1
			echo "Loggly account or subdomain: $LOGGLY_ACCOUNT"
		;;
		-u | --username ) shift
			LOGGLY_USERNAME=$1
			echo "Username is set"
		;;
		-p | --password ) shift
			LOGGLY_PASSWORD=$1
		;;
		-r | --rollback )
			LOGGLY_ROLLBACK="true"
		;;
		-s3b | --s3bucketname ) shift
			LOGGLY_S3_BUCKET_NAME=$1
			echo "S3 Bucket Name: $LOGGLY_S3_BUCKET_NAME"
		;;
		-s3f | --s3filename ) shift
			LOGGLY_S3_FILE_NAME=$1
			echo "S3 File Name: $LOGGLY_S3_FILE_NAME"
		;;
		-s3l | --s3alias ) shift
			LOGGLY_S3_ALIAS=$1
			echo "File alias: $LOGGLY_S3_ALIAS"
		;;
		-h | --help)
		usage
		exit
          ;;
    esac
    shift
done
fi

if [ "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" -a "$LOGGLY_S3_ALIAS" != "" -a \( "$LOGGLY_S3_BUCKET_NAME" != "" -o "$LOGGLY_S3_FILE_NAME" != "" \) ]; then
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