#!/bin/bash

#downloads configure-linux.sh
echo "INFO: Downloading dependencies - configure-linux.sh"
curl -s -o configure-linux.sh https://www.loggly.com/install/configure-linux.sh
source configure-linux.sh "being-invoked"
	
##########  Variable Declarations - Start  ##########
#name of the current script
SCRIPT_NAME=configure-nginx.sh
#version of the current script
SCRIPT_VERSION=1.3

#we have not found the nginx version yet at this point in the script
APP_TAG="\"nginx-version\":\"\""

#name of the service, in this case nginx
SERVICE="nginx"
#name of nginx access log file
NGINX_ACCESS_LOG_FILE="access.log"
#name of nginx error log file
NGINX_ERROR_LOG_FILE="error.log"
#name and location of nginx syslog file
NGINX_SYSLOG_CONFFILE=$RSYSLOG_ETCDIR_CONF/21-nginx.conf
#name and location of nginx syslog backup file
NGINX_SYSLOG_CONFFILE_BACKUP=$RSYSLOG_ETCDIR_CONF/21-nginx.conf.loggly.bk

#this variable will hold the path to the nginx home
LOGGLY_NGINX_HOME=
#this variable will hold the value of the nginx log folder
LOGGLY_NGINX_LOG_HOME=
#this variable will hold the users nginx version
NGINX_VERSION=

MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure nginx is available at https://www.loggly.com/docs/nginx-server-logs#manual"

#this variable will hold if the check env function for linux is invoked
NGINX_ENV_VALIDATED="false"

#apache as tag sent with the logs
LOGGLY_FILE_TAG="nginx"

#add tags to the logs
TAG=

##########  Variable Declarations - End  ##########

#check if nginx environment is compatible for Loggly
checkNginxLogglyCompatibility()
{
	#check if the linux environment is compatible for Loggly
	checkLinuxLogglyCompatibility
	
	#check if nginx is installed on unix system
	checkNginxDetails

	NGINX_ENV_VALIDATED="true"
}


# executing the script for loggly to install and configure syslog.
installLogglyConfForNginx()
{
	#log message indicating starting of Loggly configuration
	logMsgToConfigSysLog "INFO" "INFO: Initiating Configure Loggly for Nginx."
	
	#check if nginx environment is compatible with Loggly
	if [ "$NGINX_ENV_VALIDATED" = "false" ]; then
		checkNginxLogglyCompatibility
	fi
	
	#configure loggly for Linux
	installLogglyConf

	#multiple tags
	addTagsInConfiguration

	#create 21nginx.conf file
	write21NginxConfFile
	
	#check for the nginx log file size
	checkLogFileSize $LOGGLY_NGINX_LOG_HOME/$NGINX_ACCESS_LOG_FILE $LOGGLY_NGINX_LOG_HOME/$NGINX_ERROR_LOG_FILE
	
	#verify if the nginx logs made it to loggly
	checkIfNginxLogsMadeToLoggly
	
	#log success message
	logMsgToConfigSysLog "SUCCESS" "SUCCESS: Nginx successfully configured to send logs to Loggly."
}

#executing script to remove loggly configuration for Nginx
removeLogglyConfForNginx()
{
	logMsgToConfigSysLog "INFO" "INFO: Initiating rollback."

	#check if the user has root permission to run this script
	checkIfUserHasRootPrivileges

	#check if the OS is supported by the script. If no, then exit
	checkIfSupportedOS

	#check if nginx is installed on unix system
	checkNginxDetails

	#remove 21nginx.conf file
	remove21NginxConfFile

	logMsgToConfigSysLog "INFO" "INFO: Rollback completed."
}

#checks if log rotation is enabled on the selected file
checkIfLogRotationEnabled()
{
	if [[ $(grep -r "/var/log/$SERVICE/*." /etc/logrotate.d/$SERVICE) ]]; then
		logMsgToConfigSysLog "WARN" "WARN: Log rotation is enabled on $LOGGLY_NGINX_LOG_HOME/$NGINX_ACCESS_LOG_FILE and $LOGGLY_NGINX_LOG_HOME/$NGINX_ERROR_LOG_FILE.  Please follow instructions here to update logrotate https://www.loggly.com/docs/log-rotate"
	fi
}

#identify if nginx is installed on your system and is available as a service
checkNginxDetails()
{	
	#verify if nginx is installed as service
	if [ ! -f /etc/init.d/$SERVICE ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Nginx is not configured as a service"
		exit 1
	fi
	
	#get the version of nginx installed
	getNginxVersion
	
	#set all the required nginx variables by this script
	setNginxVariables
	
	#to check logrotation
	checkIfLogRotationEnabled
}


#sets nginx variables which will be used across various functions
setNginxVariables()
{
	LOGGLY_NGINX_LOG_HOME=/var/log/$SERVICE
}

#gets the version of nginx installed on the unix box
getNginxVersion()
{	
	NGINX_VERSION=$(nginx -v 2>&1)
	NGINX_VERSION=${NGINX_VERSION#*/}	
	APP_TAG="\"nginx-version\":\"$NGINX_VERSION\""
	logMsgToConfigSysLog "INFO" "INFO: nginx version: $NGINX_VERSION"
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
					logMsgToConfigSysLog "INFO" "INFO: Current nginx logs size is $fileSize bytes. Continuing with nginx Loggly configuration.";
					break;;
					[Nn]* ) 
					logMsgToConfigSysLog "INFO" "INFO: Current nginx logs size is $fileSize bytes. Discontinuing with nginx Loggly configuration."
					exit 1
					break;;
					* ) echo "Please answer yes or no.";;
				esac
			done
		else
			logMsgToConfigSysLog "WARN" "WARN: There are currently large log files which may use up your allowed volume."
			logMsgToConfigSysLog "INFO" "INFO: Current nginx logs size is $fileSize bytes. Continuing with nginx Loggly configuration.";
		fi
	elif [ $fileSize -eq 0 ]; then
		logMsgToConfigSysLog "WARN" "WARN: There are no recent logs from nginx there so won't be any sent to Loggly. You can generate some logs by visiting a page on your web server."
		exit 1
	fi	
}

write21NginxConfFile()
{
	#Create nginx syslog config file if it doesn't exist
	echo "INFO: Checking if nginx sysconf file $NGINX_SYSLOG_CONFFILE exist."
	if [ -f "$NGINX_SYSLOG_CONFFILE" ]; then
		logMsgToConfigSysLog "WARN" "WARN: nginx syslog file $NGINX_SYSLOG_CONFFILE already exist."
		if [ "$SUPPRESS_PROMPT" == "false" ]; then
		   while true; do
				read -p "Do you wish to override $NGINX_SYSLOG_CONFFILE? (yes/no)" yn
				case $yn in
					[Yy]* )
					logMsgToConfigSysLog "INFO" "INFO: Going to back up the conf file: $NGINX_SYSLOG_CONFFILE to $NGINX_SYSLOG_CONFFILE_BACKUP";
					sudo mv -f $NGINX_SYSLOG_CONFFILE $NGINX_SYSLOG_CONFFILE_BACKUP;
					write21NginxFileContents;
					break;;
					[Nn]* ) break;;
					* ) echo "Please answer yes or no.";;
				esac
			done
	   else
			logMsgToConfigSysLog "INFO" "INFO: Going to back up the conf file: $NGINX_SYSLOG_CONFFILE to $NGINX_SYSLOG_CONFFILE_BACKUP";
			sudo mv -f $NGINX_SYSLOG_CONFFILE $NGINX_SYSLOG_CONFFILE_BACKUP;
			write21NginxFileContents;
	   fi
	else
		write21NginxFileContents
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
#function to write the contents of nginx syslog config file
write21NginxFileContents()
{
	logMsgToConfigSysLog "INFO" "INFO: Creating file $NGINX_SYSLOG_CONFFILE"
	sudo touch $NGINX_SYSLOG_CONFFILE
	sudo chmod o+w $NGINX_SYSLOG_CONFFILE

	imfileStr="\$ModLoad imfile
	\$InputFilePollInterval 10 
	\$WorkDirectory $RSYSLOG_DIR
	"
	if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
		imfileStr+="\$PrivDropToGroup adm
		"
	fi

	imfileStr+="
	# nginx access file:
	\$InputFileName $LOGGLY_NGINX_LOG_HOME/$NGINX_ACCESS_LOG_FILE
	\$InputFileTag nginx-access:
	\$InputFileStateFile stat-nginx-access
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor

	#nginx Error file: 
	\$InputFileName $LOGGLY_NGINX_LOG_HOME/$NGINX_ERROR_LOG_FILE
	\$InputFileTag nginx-error:
	\$InputFileStateFile stat-nginx-error
	\$InputFileSeverity error
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor

	#Add a tag for nginx events
	\$template LogglyFormatNginx,\"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$LOGGLY_AUTH_TOKEN@41058 $TAG] %msg%\n\"

	if \$programname == 'nginx-access' then @@logs-01.loggly.com:514;LogglyFormatNginx
	if \$programname == 'nginx-access' then ~
	if \$programname == 'nginx-error' then @@logs-01.loggly.com:514;LogglyFormatNginx
	if \$programname == 'nginx-error' then ~
	"

	#change the nginx-21 file to variable from above and also take the directory of the nginx log file.
sudo cat << EOIPFW >> $NGINX_SYSLOG_CONFFILE
$imfileStr
EOIPFW

	restartRsyslog
}

#checks if the nginx logs made to loggly
checkIfNginxLogsMadeToLoggly()
{
	counter=1
	maxCounter=10

	nginxInitialLogCount=0
	nginxLatestLogCount=0
	queryParam="tag%3Anginx&from=-15m&until=now&size=1"

	queryUrl="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$queryParam"
	logMsgToConfigSysLog "INFO" "INFO: Search URL: $queryUrl"

	logMsgToConfigSysLog "INFO" "INFO: Getting initial nginx log count."
	#get the initial count of nginx logs for past 15 minutes
	searchAndFetch nginxInitialLogCount "$queryUrl"

	logMsgToConfigSysLog "INFO" "INFO: Verifying if the nginx logs made it to Loggly."
	logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
	#get the final count of nginx logs for past 15 minutes
	searchAndFetch nginxLatestLogCount "$queryUrl"
	let counter=$counter+1

	while [ "$nginxLatestLogCount" -le "$nginxInitialLogCount" ]; do
		echo "INFO: Did not find the test log message in Loggly's search yet. Waiting for 30 secs."
		sleep 30
		echo "INFO: Done waiting. Verifying again."
		logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
		searchAndFetch nginxLatestLogCount "$queryUrl"
		let counter=$counter+1
		if [ "$counter" -gt "$maxCounter" ]; then
			logMsgToConfigSysLog "ERROR" "ERROR: Nginx logs did not make to Loggly in time. Please check network and firewall settings and retry."
			exit 1
		fi
	done

	if [ "$nginxLatestLogCount" -gt "$nginxInitialLogCount" ]; then
		logMsgToConfigSysLog "INFO" "INFO: Nginx logs successfully transferred to Loggly! You are now sending Nginx logs to Loggly."
		checkIfLogsAreParsedInLoggly
	fi
}

#verifying if the logs are being parsed or not
checkIfLogsAreParsedInLoggly()
{
	nginxInitialLogCount=0
	TAG_PARSER=
	IFS=, read -a array <<< "$LOGGLY_FILE_TAG"
	for i in "${array[@]}"
	do
		TAG_PARSER="$TAG_PARSER%20tag%3A$i "
	done
	queryParam="logtype%3Anginx$TAG_PARSER&from=-15m&until=now&size=1"
	queryUrl="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$queryParam"
	searchAndFetch nginxInitialLogCount "$queryUrl"
	logMsgToConfigSysLog "INFO" "INFO: Verifying if the Nginx logs are parsed in Loggly."
	if [ "$nginxInitialLogCount" -gt 0 ]; then  
		logMsgToConfigSysLog "INFO" "INFO: Nginx logs successfully parsed in Loggly!"
	else
		logMsgToConfigSysLog "WARN" "WARN: We received your logs but they do not appear to use one of our automatically parsed formats. You can still do full text search and counts on these logs, but you won't be able to use our field explorer. Please consider switching to one of our automated formats https://www.loggly.com/docs/automated-parsing/"
	fi
}

#remove 21nginx.conf file
remove21NginxConfFile()
{
	echo "INFO: Deleting the loggly nginx syslog conf file."
	if [ -f "$NGINX_SYSLOG_CONFFILE" ]; then
		sudo rm -rf "$NGINX_SYSLOG_CONFFILE"
	fi
	echo "INFO: Removed all the modified files."
	restartRsyslog
}

#display usage syntax
usage()
{
cat << EOF
usage: configure-nginx [-a loggly auth account or subdomain] [-t loggly token (optional)] [-u username] [-p password (optional)] [-tag filetag1,filetag2 (optional)] [-s suppress prompts {optional)]
usage: configure-nginx [-a loggly auth account or subdomain] [-r to rollback]
usage: configure-nginx [-h for help]
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
    installLogglyConfForNginx
elif [ "$LOGGLY_ROLLBACK" != "" -a "$LOGGLY_ACCOUNT" != "" ]; then
    removeLogglyConfForNginx
else
	usage
fi

##########  Get Inputs from User - End  ##########
