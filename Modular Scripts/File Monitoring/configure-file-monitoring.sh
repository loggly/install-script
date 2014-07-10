#!/bin/bash

#downloads configure-linux.sh
echo "INFO: Downloading dependencies - configure-linux.sh"
curl -s -o configure-linux.sh https://raw.githubusercontent.com/psquickitjayant/install-script/master/Linux%20Script/configure-linux.sh
source configure-linux.sh "being-invoked"

##########  Variable Declarations - Start  ##########
#name of the current script
SCRIPT_NAME=configure-file-monitoring.sh
#version of the current script
SCRIPT_VERSION=1.0

#file to monitor (contains complete path and file name) provided by user
LOGGLY_FILE_TO_MONITOR=

#alias name, will be used as tag & state file name etc. provided by user
LOGGLY_FILE_TO_MONITOR_ALIAS=

#file alias provided by the user
APP_TAG="\"file-alias\":\"\""

#name and location of syslog file
FILE_SYSLOG_CONFFILE=

#name and location of syslog backup file
FILE_SYSLOG_CONFFILE_BACKUP=

MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure a file is available at https://www.loggly.com/docs/file-monitoring/"

##########  Variable Declarations - End  ##########

# executing the script for loggly to install and configure syslog
installLogglyConfForFile()
{
	#log message indicating starting of Loggly configuration
	logMsgToConfigSysLog "INFO" "INFO: Initiating configure Loggly for file monitoring."

	#check if the linux environment is compatible for Loggly
	checkLinuxLogglyCompatibility

	#construct variables using filename and filealias
	constructVariables

	#check if file to monitor exists
	checkIfFileExist

	#check if the alias is already taken
	checkIfFileAliasExist

	#configure loggly for Linux
	installLogglyConf

	#check for the log file size
	checkLogFileSize $LOGGLY_FILE_TO_MONITOR

	#create 21<file alias>.conf file
	write21ConfFileContents

	#verify if the file logs made it to loggly
	checkIfFileLogsMadeToLoggly

	#log success message
	logMsgToConfigSysLog "SUCCESS" "SUCCESS: Successfully configured to send $LOGGLY_FILE_TO_MONITOR logs via Loggly."
}

#executing script to remove loggly configuration for File
removeLogglyConfForFile()
{
	logMsgToConfigSysLog "INFO" "INFO: Initiating rollback."

	#check if the user has root permission to run this script
	checkIfUserHasRootPrivileges

	#check if the OS is supported by the script. If no, then exit
	checkIfSupportedOS

	#construct variables using filename and filealias
	constructVariables

	#checks if the conf file exists. if not, then exit.
	checkIfConfFileExist

	#remove 21<file-alias>.conf file
	remove21ConfFile

	logMsgToConfigSysLog "INFO" "INFO: Rollback completed."
}

constructVariables()
{
	#conf file name
	FILE_SYSLOG_CONFFILE="$RSYSLOG_ETCDIR_CONF/21-filemonitoring-$LOGGLY_FILE_TO_MONITOR_ALIAS.conf"

	#conf file backup name
	FILE_SYSLOG_CONFFILE_BACKUP="$FILE_SYSLOG_CONFFILE.loggly.bk"

	#application tag
	APP_TAG="\"file-alias\":\"$LOGGLY_FILE_TO_MONITOR_ALIAS\""
}

#checks if the file to be monitored exist
checkIfFileExist()
{
	if [ -f "$LOGGLY_FILE_TO_MONITOR" ]; then
		logMsgToConfigSysLog "INFO" "INFO: File $LOGGLY_FILE_TO_MONITOR exists."
	else
		logMsgToConfigSysLog "ERROR" "ERROR: File $LOGGLY_FILE_TO_MONITOR does not exist. Kindly recheck."
		exit 1
	fi
}

#check if the file alias is already taken
checkIfFileAliasExist()
{
	if [ -f "$FILE_SYSLOG_CONFFILE" ]; then
		logMsgToConfigSysLog "WARN" "WARN: This file alias is already taken. You must choose a unique file alias for each file."
		while true; do
			read -p "Would you like to overwrite the configuration for this file alias (yes/no)?" yn
			case $yn in
				[Yy]* )
				logMsgToConfigSysLog "INFO" "INFO: Going to back up the conf file: $FILE_SYSLOG_CONFFILE to $FILE_SYSLOG_CONFFILE_BACKUP";
				sudo mv -f $FILE_SYSLOG_CONFFILE $FILE_SYSLOG_CONFFILE_BACKUP;
				break;;
				[Nn]* )
				logMsgToConfigSysLog "INFO" "INFO: Not overwriting the existing configuration. Exiting"
				exit 1
				break;;
				* ) echo "Please answer yes or no.";;
			esac
		done
	fi
}

#check the size of the log file. If the size is greater than 100MB give a warning to the user. If the file size is 0
#then exit
checkLogFileSize()
{
	monitorFileSize=$(wc -c "$1" | cut -f 1 -d ' ')
	if [ $monitorFileSize -ge 102400000 ]; then
		logMsgToConfigSysLog "INFO" "INFO: "
		while true; do
			read -p "WARN: There are currently large log files which may use up your allowed volume. Please rotate your logs before continuing. Would you like to continue now anyway? (yes/no)" yn
			case $yn in
				[Yy]* )
				logMsgToConfigSysLog "INFO" "INFO: Current size of $LOGGLY_FILE_TO_MONITOR is $monitorFileSize bytes. Continuing with File Loggly configuration.";
				break;;
				[Nn]* )
				logMsgToConfigSysLog "INFO" "INFO: Current size of $LOGGLY_FILE_TO_MONITOR is $monitorFileSize bytes. Discontinuing with File Loggly configuration."
				exit 1
				break;;
				* ) echo "Please answer yes or no.";;
			esac
		done
	elif [ $monitorFileSize -eq 0 ]; then
		logMsgToConfigSysLog "WARN" "WARN: There are no recent $LOGGLY_FILE_TO_MONITOR log files so verification may not succeed. Exiting."
		exit 1
	else
		logMsgToConfigSysLog "INFO" "INFO: File size of $LOGGLY_FILE_TO_MONITOR is $monitorFileSize bytes."
	fi
}

#function to write the contents of syslog config file
write21ConfFileContents()
{
	logMsgToConfigSysLog "INFO" "INFO: Creating file $FILE_SYSLOG_CONFFILE"
	sudo touch $FILE_SYSLOG_CONFFILE
	sudo chmod o+w $FILE_SYSLOG_CONFFILE

	imfileStr="\$ModLoad imfile
	\$InputFilePollInterval 10
	\$WorkDirectory $RSYSLOG_DIR
	"
	if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
		imfileStr+="\$PrivDropToGroup adm
		"
	fi

	imfileStr+="
	# File access file:
	\$InputFileName $LOGGLY_FILE_TO_MONITOR
	\$InputFileTag $LOGGLY_FILE_TO_MONITOR_ALIAS:
	\$InputFileStateFile stat-$LOGGLY_FILE_TO_MONITOR_ALIAS
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor

	#Add a tag for file events
	\$template LogglyFormatFile,\"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$LOGGLY_AUTH_TOKEN@41058 tag=\\\"file\\\"] %msg%\n\"

	if \$programname == '$LOGGLY_FILE_TO_MONITOR_ALIAS' then @@logs-01.loggly.com:514;LogglyFormatFile
	if \$programname == '$LOGGLY_FILE_TO_MONITOR_ALIAS' then ~
	"

	#write to 21-<file-alias>.conf file
sudo cat << EOIPFW >> $FILE_SYSLOG_CONFFILE
$imfileStr
EOIPFW

	restartRsyslog
}

#checks if the apache logs made to loggly
checkIfFileLogsMadeToLoggly()
{
	counter=1
	maxCounter=10

	fileInitialLogCount=0
	fileLatestLogCount=0
	queryParam="syslog.appName%3A$LOGGLY_FILE_TO_MONITOR_ALIAS&from=-15m&until=now&size=1"

	queryUrl="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$queryParam"
	logMsgToConfigSysLog "INFO" "INFO: Search URL: $queryUrl"

	logMsgToConfigSysLog "INFO" "INFO: Getting initial log count."
	#get the initial count of file logs for past 15 minutes
	searchAndFetch fileInitialLogCount "$queryUrl"

	logMsgToConfigSysLog "INFO" "INFO: Verifying if the logs made it to Loggly."
	logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
	#get the final count of file logs for past 15 minutes
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
		logMsgToConfigSysLog "SUCCESS" "SUCCESS: Logs successfully transferred to Loggly! You are now sending $LOGGLY_FILE_TO_MONITOR logs to Loggly."
		exit 0
	fi
}

#checks if the conf file exist. Name of conf file is constructed using the file alias name provided
checkIfConfFileExist()
{
	if [ ! -f "$FILE_SYSLOG_CONFFILE" ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Invalid File Alias provided."
		exit 1
	fi
}

#remove 21<filemonitoring>.conf file
remove21ConfFile()
{
	echo "INFO: Deleting the loggly file syslog conf file."
	if [ -f "$FILE_SYSLOG_CONFFILE" ]; then
		sudo rm -rf "$FILE_SYSLOG_CONFFILE"
	fi
	echo "INFO: Removed all the modified files."
	restartRsyslog
}

#display usage syntax
usage()
{
cat << EOF
usage: configure-file [-a loggly auth account or subdomain] [-t loggly token (optional)] [-u username] [-p password (optional)] [-f filename] [-l filealias]
usage: configure-file [-a loggly auth account or subdomain] [-r to rollback] [-l filealias]
usage: configure-file [-h for help]
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
	  -f | --filename ) shift
		  #LOGGLY_FILE_TO_MONITOR=$1
		  LOGGLY_FILE_TO_MONITOR=$(readlink -f $1)
		  echo "File to monitor: $LOGGLY_FILE_TO_MONITOR"
		  ;;
	  -l | --filealias ) shift
		  LOGGLY_FILE_TO_MONITOR_ALIAS=$1
		  echo "File alias: $LOGGLY_FILE_TO_MONITOR_ALIAS"
		  ;;
      -h | --help)
          usage
          exit
          ;;
    esac
    shift
done
fi

if [ "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" -a "$LOGGLY_FILE_TO_MONITOR" != "" -a "$LOGGLY_FILE_TO_MONITOR_ALIAS" != "" ]; then
	if [ "$LOGGLY_PASSWORD" = "" ]; then
		getPassword
	fi
    installLogglyConfForFile
elif [ "$LOGGLY_ROLLBACK" != "" -a "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_FILE_TO_MONITOR_ALIAS" != "" ]; then
    removeLogglyConfForFile
else
	usage
fi

##########  Get Inputs from User - End  ##########