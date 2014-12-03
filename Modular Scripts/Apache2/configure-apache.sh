#!/bin/bash

#downloads configure-linux.sh
echo "INFO: Downloading dependencies - configure-linux.sh"
curl -s -o configure-linux.sh https://www.loggly.com/install/configure-linux.sh
source configure-linux.sh "being-invoked"
	
##########  Variable Declarations - Start  ##########
#name of the current script
SCRIPT_NAME=configure-apache.sh
#version of the current script
SCRIPT_VERSION=1.5

#we have not found the apache version yet at this point in the script
APP_TAG="\"apache-version\":\"\""

#name of the service, in this case apache2
SERVICE=
#name of apache access log file
APACHE_ACCESS_LOG_FILE=
#name of apache error log file
APACHE_ERROR_LOG_FILE=
#name and location of apache syslog file
APACHE_SYSLOG_CONFFILE=$RSYSLOG_ETCDIR_CONF/21-apache.conf
#name and location of apache syslog backup file
APACHE_SYSLOG_CONFFILE_BACKUP=$RSYSLOG_ETCDIR_CONF/21-apache.conf.loggly.bk

#this variable will hold the path to the apache home
LOGGLY_APACHE_HOME=
#this variable will hold the value of the apache log folder
LOGGLY_APACHE_LOG_HOME=
#this variable will hold the users apache version
APACHE_VERSION=

MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure Apache2 is available at https://www.loggly.com/docs/sending-apache-logs/"

#this variable will hold if the check env function for linux is invoked
APACHE_ENV_VALIDATED="false"

#apache as tag sent with the logs
LOGGLY_FILE_TAG="apache"

#add tags to the logs
TAG=
##########  Variable Declarations - End  ##########

#check if apache environment is compatible for Loggly
checkApacheLogglyCompatibility()
{
	#check if the linux environment is compatible for Loggly
	checkLinuxLogglyCompatibility
	
	#check if apache2 is installed on unix system
	checkApacheDetails

	APACHE_ENV_VALIDATED="true"
}


# executing the script for loggly to install and configure syslog.
installLogglyConfForApache()
{
	#log message indicating starting of Loggly configuration
	logMsgToConfigSysLog "INFO" "INFO: Initiating Configure Loggly for Apache."
	
	#check if apache environment is compatible with Loggly
	if [ "$APACHE_ENV_VALIDATED" = "false" ]; then
		checkApacheLogglyCompatibility
	fi
	
	#configure loggly for Linux
	installLogglyConf
	
	#multiple tags
	addTagsInConfiguration
	
	#create 21apache.conf file
	write21ApacheConfFile
	
	#check for the apache log file size
	checkLogFileSize $LOGGLY_APACHE_LOG_HOME/$APACHE_ACCESS_LOG_FILE $LOGGLY_APACHE_LOG_HOME/$APACHE_ERROR_LOG_FILE
	
	#verify if the apache logs made it to loggly
	checkIfApacheLogsMadeToLoggly

	#log success message
	logMsgToConfigSysLog "SUCCESS" "SUCCESS: Apache successfully configured to send logs to Loggly."
}

#executing script to remove loggly configuration for Apache
removeLogglyConfForApache()
{
	logMsgToConfigSysLog "INFO" "INFO: Initiating rollback."

	#check if the user has root permission to run this script
	checkIfUserHasRootPrivileges

	#check if the OS is supported by the script. If no, then exit
	checkIfSupportedOS

	#check if apache2 is installed on unix system
	checkApacheDetails

	#remove 21apache.conf file
	remove21ApacheConfFile

	logMsgToConfigSysLog "INFO" "INFO: Rollback completed."
}

#identify if apache2 is installed on your system and is available as a service
checkApacheDetails()
{
	getApacheServiceName
	
	#verify if apache is installed as service
	if [ ! -f /etc/init.d/$SERVICE ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Apache is not configured as a service"
		exit 1
	fi
	
	#get the version of apache installed
	getApacheVersion
	
	#check if apache is supported
	checkIfSupportedApacheVersion
	
	#set all the required apache variables by this script
	setApacheVariables
}

#Get the apache service name on various linux flavors
getApacheServiceName()
{
	#checking if the Linux is yum based or apt-get based
	YUM_BASED=$(command -v yum)
	APT_GET_BASED=$(command -v apt-get)
	
	if [ "$YUM_BASED" != "" ]; then
		SERVICE="httpd"
		APACHE_ACCESS_LOG_FILE="access_log"
		APACHE_ERROR_LOG_FILE="error_log"
	
	elif [ "$APT_GET_BASED" != "" ]; then
		SERVICE="apache2"
		APACHE_ACCESS_LOG_FILE="access.log"
		APACHE_ERROR_LOG_FILE="error.log"
	fi
}

#sets apache variables which will be used across various functions
setApacheVariables()
{
	LOGGLY_APACHE_LOG_HOME=/var/log/$SERVICE
}

#gets the version of apache installed on the unix box
getApacheVersion()
{
	APACHE_VERSION=$($SERVICE -v | grep "Server version: Apache")
	APACHE_VERSION=${APACHE_VERSION#*/}
	APACHE_VERSION=${APACHE_VERSION% *}
	APACHE_VERSION=$APACHE_VERSION | tr -d ' '
	APP_TAG="\"apache-version\":\"$APACHE_VERSION\""
	logMsgToConfigSysLog "INFO" "INFO: Apache version: $APACHE_VERSION"
}

#checks if the apache version is supported by this script, currently the script
#only supports apache2
checkIfSupportedApacheVersion()
{
	apacheMajorVersion=${APACHE_VERSION%%.*}
	if [[ ($apacheMajorVersion -ne 2 ) ]]; then
		logMsgToConfigSysLog "ERROR" "ERROR: This script only supports Apache version 2."
		exit 1
	fi
}

checkLogFileSize()
{
	accessFileSize=$(wc -c "$1" | cut -f 1 -d ' ')
	errorFileSize=$(wc -c "$2" | cut -f 1 -d ' ')
	fileSize=$((accessFileSize+errorFileSize))
	if [ $fileSize -ge 102400000 ]; then
		if [ "$SUPPRESS_PROMPT" == "false" ]; then
			while true; do
				read -p "WARN: There are currently large log files which may use up your allowed volume. Please rotate your logs before continuing. Would you like to continue now anyway? (yes/no)" yn
				case $yn in
					[Yy]* )
					logMsgToConfigSysLog "INFO" "INFO: Current apache logs size is $fileSize bytes. Continuing with Apache Loggly configuration.";
					break;;
					[Nn]* ) 
					logMsgToConfigSysLog "INFO" "INFO: Current apache logs size is $fileSize bytes. Discontinuing with Apache Loggly configuration."
					exit 1
					break;;
					* ) echo "Please answer yes or no.";;
				esac
			done
		else
			logMsgToConfigSysLog "WARN" "WARN: There are currently large log files which may use up your allowed volume."
			logMsgToConfigSysLog "INFO" "INFO: Current apache logs size is $fileSize bytes. Continuing with Apache Loggly configuration."
		fi
	elif [ $fileSize -eq 0 ]; then
		logMsgToConfigSysLog "WARN" "WARN: There are no recent logs from Apache there so won't be any sent to Loggly. You can generate some logs by visiting a page on your web server."
		exit 1
	fi	
}

write21ApacheConfFile()
{
	#Create apache syslog config file if it doesn't exist
	echo "INFO: Checking if apache sysconf file $APACHE_SYSLOG_CONFFILE exist."
	if [ -f "$APACHE_SYSLOG_CONFFILE" ]; then
	   
	   logMsgToConfigSysLog "WARN" "WARN: Apache syslog file $APACHE_SYSLOG_CONFFILE already exist."
	   if [ "$SUPPRESS_PROMPT" == "false" ]; then
			while true; do
				read -p "Do you wish to override $APACHE_SYSLOG_CONFFILE? (yes/no)" yn
				case $yn in
					[Yy]* )
					logMsgToConfigSysLog "INFO" "INFO: Going to back up the conf file: $APACHE_SYSLOG_CONFFILE to $APACHE_SYSLOG_CONFFILE_BACKUP";
					sudo mv -f $APACHE_SYSLOG_CONFFILE $APACHE_SYSLOG_CONFFILE_BACKUP;
					write21ApacheFileContents;
					break;;
					[Nn]* ) break;;
					* ) echo "Please answer yes or no.";;
				esac
			done
	   else
			logMsgToConfigSysLog "INFO" "INFO: Going to back up the conf file: $APACHE_SYSLOG_CONFFILE to $APACHE_SYSLOG_CONFFILE_BACKUP";
			sudo mv -f $APACHE_SYSLOG_CONFFILE $APACHE_SYSLOG_CONFFILE_BACKUP;
			write21ApacheFileContents;
	   fi
	else
		write21ApacheFileContents
	fi
}

addTagsInConfiguration()
{
	#split tags by comman(,)
	IFS=, read -a array <<< "$LOGGLY_FILE_TAG"
	for i in "${array[@]}"
	do
		TAG="$TAG tag=\\\"$i\\\" "
	done
}
#function to write the contents of apache syslog config file
write21ApacheFileContents()
{
	logMsgToConfigSysLog "INFO" "INFO: Creating file $APACHE_SYSLOG_CONFFILE"
	sudo touch $APACHE_SYSLOG_CONFFILE
	sudo chmod o+w $APACHE_SYSLOG_CONFFILE

	imfileStr="\$ModLoad imfile
	\$InputFilePollInterval 10 
	\$WorkDirectory $RSYSLOG_DIR
	"
	if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
		imfileStr+="\$PrivDropToGroup adm
		"
	fi

	imfileStr+="
	# Apache access file:
	\$InputFileName $LOGGLY_APACHE_LOG_HOME/$APACHE_ACCESS_LOG_FILE
	\$InputFileTag apache-access:
	\$InputFileStateFile stat-apache-access
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor

	#Apache Error file: 
	\$InputFileName $LOGGLY_APACHE_LOG_HOME/$APACHE_ERROR_LOG_FILE
	\$InputFileTag apache-error:
	\$InputFileStateFile stat-apache-error
	\$InputFileSeverity error
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor

	#Add a tag for apache events
	\$template LogglyFormatApache,\"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$LOGGLY_AUTH_TOKEN@41058 $TAG] %msg%\n\"

	if \$programname == 'apache-access' then @@logs-01.loggly.com:514;LogglyFormatApache
	if \$programname == 'apache-access' then ~
	if \$programname == 'apache-error' then @@logs-01.loggly.com:514;LogglyFormatApache
	if \$programname == 'apache-error' then ~
	"

	#change the apache-21 file to variable from above and also take the directory of the apache log file.
sudo cat << EOIPFW >> $APACHE_SYSLOG_CONFFILE
$imfileStr
EOIPFW

	restartRsyslog
}


#checks if the apache logs made to loggly
checkIfApacheLogsMadeToLoggly()
{
	counter=1
	maxCounter=10

	apacheInitialLogCount=0
	apacheLatestLogCount=0
	
	TAGS=
	IFS=, read -a array <<< "$LOGGLY_FILE_TAG"
	for i in "${array[@]}"
	do
		if [ "$TAGS" == "" ]; then
			TAGS="tag%3A$i" 
		else
			TAGS="$TAGS%20tag%3A$i"
		fi
	done
	
	queryParam="$TAGS&from=-15m&until=now&size=1"
	queryUrl="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$queryParam"
	logMsgToConfigSysLog "INFO" "INFO: Search URL: $queryUrl"

	logMsgToConfigSysLog "INFO" "INFO: Getting initial apache log count."
	#get the initial count of apache logs for past 15 minutes
	searchAndFetch apacheInitialLogCount "$queryUrl"

	logMsgToConfigSysLog "INFO" "INFO: Verifying if the apache logs made it to Loggly."
	logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
	#get the final count of apache logs for past 15 minutes
	searchAndFetch apacheLatestLogCount "$queryUrl"
	let counter=$counter+1

	while [ "$apacheLatestLogCount" -le "$apacheInitialLogCount" ]; do
		echo "INFO: Did not find the test log message in Loggly's search yet. Waiting for 30 secs."
		sleep 30
		echo "INFO: Done waiting. Verifying again."
		logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
		searchAndFetch apacheLatestLogCount "$queryUrl"
		let counter=$counter+1
		if [ "$counter" -gt "$maxCounter" ]; then
			logMsgToConfigSysLog  "ERROR" "ERROR: Apache logs did not make to Loggly in time. Please check network and firewall settings and retry."
            exit 1
		fi
	done

	if [ "$apacheLatestLogCount" -gt "$apacheInitialLogCount" ]; then
		logMsgToConfigSysLog "INFO" "INFO: Apache logs successfully transferred to Loggly! You are now sending Apache logs to Loggly."
		checkIfLogsAreParsedInLoggly
	fi
}
#verifying if the logs are being parsed or not
checkIfLogsAreParsedInLoggly()
{
	apacheInitialLogCount=0
	TAG_PARSER=
	IFS=, read -a array <<< "$LOGGLY_FILE_TAG"
	
	for i in "${array[@]}"
	do
		TAG_PARSER="$TAG_PARSER%20tag%3A$i "
	done
	queryParam="logtype%3Aapache$TAG_PARSER&from=-15m&until=now&size=1"
	queryUrl="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$queryParam"
	searchAndFetch apacheInitialLogCount "$queryUrl"
	logMsgToConfigSysLog "INFO" "INFO: Verifying if the Apache logs are parsed in Loggly."
	if [ "$apacheInitialLogCount" -gt 0 ]; then  
		logMsgToConfigSysLog "INFO" "INFO: Apache logs successfully parsed in Loggly!"
	else
		logMsgToConfigSysLog "WARN" "WARN: We received your logs but they do not appear to use one of our automatically parsed formats. You can still do full text search and counts on these logs, but you won't be able to use our field explorer. Please consider switching to one of our automated formats https://www.loggly.com/docs/automated-parsing/"
	fi
}

#remove 21apache.conf file
remove21ApacheConfFile()
{
	echo "INFO: Deleting the loggly apache syslog conf file."
	if [ -f "$APACHE_SYSLOG_CONFFILE" ]; then
		sudo rm -rf "$APACHE_SYSLOG_CONFFILE"
	fi
	echo "INFO: Removed all the modified files."
	restartRsyslog
}

#display usage syntax
usage()
{
cat << EOF
usage: configure-apache [-a loggly auth account or subdomain] [-t loggly token (optional)] [-u username] [-p password (optional)] [-tag filetag1,filetag2 (optional)] [-s suppress prompts {optional)]
usage: configure-apache [-a loggly auth account or subdomain] [-r to rollback]
usage: configure-apache [-h for help]
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
	  -tag| --filetag ) shift
		  LOGGLY_FILE_TAG=$1
		  echo "File tag: $LOGGLY_FILE_TAG"
		  ;;
      -r | --rollback )
		  LOGGLY_ROLLBACK="true"
          ;;
	  -s | --suppress )
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

if [ "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" ]; then
	if [ "$LOGGLY_PASSWORD" = "" ]; then
		getPassword
	fi
    installLogglyConfForApache
elif [ "$LOGGLY_ROLLBACK" != "" -a "$LOGGLY_ACCOUNT" != "" ]; then
    removeLogglyConfForApache
else
	usage
fi

##########  Get Inputs from User - End  ##########
