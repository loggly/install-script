#!/bin/bash

##########  Variable Declarations - Start  ##########

#name of the current script. This will get overwritten by the child script which calls this
SCRIPT_NAME=configure-linux.sh
#version of the current script. This will get overwritten by the child script which calls this
SCRIPT_VERSION=1.0

#application tag. This will get overwritten by the child script which calls this
APP_TAG=

#directory location for syslog
RSYSLOG_ETCDIR_CONF=/etc/rsyslog.d
#name and location of loggly syslog file
LOGGLY_RSYSLOG_CONFFILE=$RSYSLOG_ETCDIR_CONF/22-loggly.conf
#name and location of loggly syslog backup file
LOGGLY_RSYSLOG_CONFFILE_BACKUP=$LOGGLY_RSYSLOG_CONFFILE.loggly.bk

#syslog directory
RSYSLOG_DIR=/var/spool/rsyslog
#rsyslog service name
RSYSLOG_SERVICE=rsyslog
#rsyslogd
RSYSLOGD=rsyslogd
#minimum version of rsyslog to enable logging to loggly
MIN_RSYSLOG_VERSION=5.8.0
#this variable will hold the users syslog version
RSYSLOG_VERSION=

#this variable will hold the host name
HOST_NAME=
#this variable will hold the name of the linux distribution
LINUX_DIST=

#host name for logs-01.loggly.com
LOGS_01_HOST=logs-01.loggly.com
LOGS_01_URL=https://$LOGS_01_HOST
#this variable will contain loggly account url in the format https://$LOGGLY_ACCOUNT.loggly.com
LOGGLY_ACCOUNT_URL=
#loggly.com URL
LOGGLY_COM_URL=https://www.loggly.com

######Inputs provided by user######
#this variable will hold the loggly account name provided by user.
#this is a mandatory input
LOGGLY_ACCOUNT=
#this variable will hold the loggly authentication token provided by user.
#this is a mandatory input
LOGGLY_AUTH_TOKEN=
#this variable will identify if the user has selected to rollback settings
LOGGLY_ROLLBACK=
#this variable will hold the user name provided by user
#this is a mandatory input
LOGGLY_USERNAME=
#this variable will hold the password provided by user
#this is a mandatory input
LOGGLY_PASSWORD=

#variables used in 22-loggly.conf file
LOGGLY_SYSLOG_PORT=514
LOGGLY_DISTRIBUTION_ID="41058"

#Instruction link on how to configure loggly on linux manually. This will get overwritten by the child script which calls this
#on how to configure the child application
MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure rsyslog on Linux are available at https://www.loggly.com/docs/rsyslog-manual-configuration/."

#this variable is set if the script is invoked via some other calling script
IS_INVOKED=


##########  Variable Declarations - End  ##########

# executing the script for loggly to install and configure rsyslog.
installLogglyConf()
{

	#log message indicating starting of Loggly configuration
	logMsgToConfigSysLog "INFO" "INFO: Initiating Configure Loggly for Linux."

	#check if the user has root permission to run this script
	checkIfUserHasRootPrivileges

	#check if the OS is supported by the script. If no, then exit
	checkIfSupportedOS

	#set the basic variables needed by this script
	setLinuxVariables

	#check if the Loggly servers are accessible. If no, ask user to check network connectivity & exit
	checkIfLogglyServersAccessible

	#check if user credentials are valid. If no, then exit
	checkIfValidUserNamePassword

	#check if authentication token is valid. If no, then exit
	checkIfValidAuthToken

	#check if rsyslog is configured as service. If no, then exit
	checkIfRsyslogConfiguredAsService

	#check if multiple rsyslog are present in the system. If yes, then exit
	checkIfMultipleRsyslogConfigured

	#check for the minimum version of rsyslog i.e 5.8.0. If no, then exit
	checkIfMinVersionOfRsyslog

	#check if selinux service is enforced. if yes, ask the user to manually disable and exit the script
	checkIfSelinuxServiceEnforced

	#if all the above check passes, write the 22-loggly.conf file
	write22LogglyConfFile

	# Create rsyslog dir if it doesn't exist, Modify the permission on rsyslog directory if exist on Ubuntu
	createRsyslogDir

	#check if the logs are going to loggly fro linux system now
	checkIfLogsMadeToLoggly

	#log success message
	logMsgToConfigSysLog "SUCCESS" "SUCCESS: Linux system successfully configured to send logs via Loggly."

}
# End of configure rsyslog for linux

#remove loggly configuration from Linux system
removeLogglyConf()
{
	#log message indicating starting of Loggly configuration
	logMsgToConfigSysLog "INFO" "INFO: Initiating uninstall Loggly for Linux."

	#check if the user has root permission to run this script
	checkIfUserHasRootPrivileges

	#check if the OS is supported by the script. If no, then exit
	checkIfSupportedOS

	#set the basic variables needed by this script
	setLinuxVariables

	#remove 22-loggly.conf file
	remove22LogglyConfFile

	#log success message
	logMsgToConfigSysLog "SUCCESS" "SUCCESS: Uninstalled Loggly configuration from Linux system."
}

#checks if user has root privileges
checkIfUserHasRootPrivileges()
{
	#This script needs to be run as a sudo user
	if [[ $EUID -ne 0 ]]; then
	   logMsgToConfigSysLog "ERROR" "ERROR: This script must be run as root."
	   exit 1
	fi
}

#check if supported operating system
checkIfSupportedOS()
{
	#set value for linux distribution name
	LINUX_DIST=$(lsb_release -ds)

	if [ $? -ne 0 ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: This operating system is not supported by the script."
		exit 1
	else
		#remove double quotes (if any) from the linux distribution name
		LINUX_DIST="${LINUX_DIST%\"}"
		LINUX_DIST="${LINUX_DIST#\"}"
		case "$LINUX_DIST" in
			*"Ubuntu"* )
			echo "INFO: Operating system is Ubuntu."
			;;
			*"Red Hat"* )
			echo "INFO: Operating system is Red Hat."
			;;
			*"CentOS"* )
			echo "INFO: Operating system is CentOS."
			;;
			* )
			logMsgToConfigSysLog "ERROR" "ERROR: This operating system is not supported by the script."
			exit 1
			;;
		esac
	fi
}


#sets linux variables which will be used across various functions
setLinuxVariables()
{
	#set host name
	HOST_NAME=$(hostname)

	#set loggly account url
	LOGGLY_ACCOUNT_URL=https://$LOGGLY_ACCOUNT.loggly.com
}

#checks if all the various endpoints used for configuring loggly are accessible
checkIfLogglyServersAccessible()
{
	echo "INFO: Checking if $LOGGLY_ACCOUNT_URL is reachable."
	if [ $(curl -s --head  --request GET $LOGGLY_ACCOUNT_URL/login | grep "200 OK" | wc -l) == 1 ]; then
		echo "INFO: $LOGGLY_ACCOUNT_URL is reachable."
	else
		logMsgToConfigSysLog "WARNING" "WARNING: $LOGGLY_ACCOUNT_URL is not reachable. Please check your network and firewall settings. Continuing to configure Loggly on your system."
	fi

	echo "INFO: Checking if $LOGS_01_HOST is reachable."
	if [ $(ping -c 1 $LOGS_01_HOST | grep "1 packets transmitted, 1 received, 0% packet loss" | wc -l) == 1 ]; then
		echo "INFO: $LOGS_01_HOST is reachable."
	else
		logMsgToConfigSysLog "WARNING" "WARNING: $LOGS_01_HOST is not reachable. Please check your network and firewall settings. Continuing to configure Loggly on your system."
	fi
}

#check if user name and password is valid
checkIfValidUserNamePassword()
{
	echo "INFO: Checking if provided username and password is correct."
	if [ $(curl -s -u $LOGGLY_USERNAME:$LOGGLY_PASSWORD $LOGGLY_ACCOUNT_URL/apiv2/customer | grep "Unauthorized" | wc -l) == 1 ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Invalid Loggly username or password."
		exit 1
	else
		logMsgToConfigSysLog "INFO" "INFO: Username and password authorized successfully."
	fi
}

#check if authentication token is valid
checkIfValidAuthToken()
{
	echo "INFO: Checking if provided auth token is correct."
	if [ $(curl -s -u $LOGGLY_USERNAME:$LOGGLY_PASSWORD $LOGGLY_ACCOUNT_URL/apiv2/customer | grep \"$LOGGLY_AUTH_TOKEN\" | wc -l) == 1 ]; then
		logMsgToConfigSysLog "INFO" "INFO: Authentication token validated successfully."
	else
		logMsgToConfigSysLog "ERROR" "ERROR: Invalid authentication token. You can get valid authentication token by following instructions at https://www.loggly.com/docs/customer-token-authentication-token/."
		exit 1
	fi
}

#check if rsyslog is configured as service. If it is configured as service and not started, start the service
checkIfRsyslogConfiguredAsService()
{
	if [ -f /etc/init.d/$RSYSLOG_SERVICE ]; then
		logMsgToConfigSysLog "INFO" "INFO: $RSYSLOG_SERVICE is present as service."
	else
		logMsgToConfigSysLog "ERROR" "ERROR: $RSYSLOG_SERVICE is not present as service."
		exit 1
	fi

	if [ $(ps -ef | grep -v grep | grep "$RSYSLOG_SERVICE" | wc -l) -eq 0 ]; then
		logMsgToConfigSysLog "INFO" "INFO: $RSYSLOG_SERVICE is not running. Attempting to start service."
		sudo service $RSYSLOG_SERVICE start
	fi
}


#check if multiple versions of rsyslog is configured
checkIfMultipleRsyslogConfigured()
{
	if [ $(ps -ef | grep -v grep | grep "$RSYSLOG_SERVICE" | wc -l) -gt 1 ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Multiple (more than 1) $RSYSLOG_SERVICE is running."
	fi
}

#check if mimimum version of rsyslog required to configure loggly is met
checkIfMinVersionOfRsyslog()
{
	RSYSLOG_VERSION=$(sudo $RSYSLOGD -version | grep "$RSYSLOGD")
	RSYSLOG_VERSION=${RSYSLOG_VERSION#* }
	RSYSLOG_VERSION=${RSYSLOG_VERSION%,*}
	RSYSLOG_VERSION=$RSYSLOG_VERSION | tr -d " "
	if [ $(compareVersions $RSYSLOG_VERSION $MIN_RSYSLOG_VERSION 3) -lt 0 ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Min rsyslog version required is 5.8.0."
		exit 1
	fi
}

#check if SeLinux service is enforced
checkIfSelinuxServiceEnforced()
{
	isSelinuxInstalled=$(getenforce -ds 2>/dev/null)
	if [ $? -ne 0 ]; then
		logMsgToConfigSysLog "INFO" "INFO: selinux status is not enforced."
	elif [ $(sudo getenforce | grep "Enforcing" | wc -l) -gt 0 ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: selinux status is 'Enforcing'. Please disable it and start the rsyslog daemon manually."
	fi
}

#write 22-loggly,conf file to /etc/rsyslog.d directory after checking with user if override is needed
write22LogglyConfFile()
{
	echo "INFO: Checking if loggly sysconf file $LOGGLY_RSYSLOG_CONFFILE exist."
	if [ -f "$LOGGLY_RSYSLOG_CONFFILE" ]; then
		logMsgToConfigSysLog "WARN" "WARN: Loggly rsyslog file $LOGGLY_RSYSLOG_CONFFILE already exist."
		while true; do
			read -p "Do you wish to override $LOGGLY_RSYSLOG_CONFFILE? (yes/no)" yn
			case $yn in
				[Yy]* )
				logMsgToConfigSysLog "INFO" "INFO: Going to back up the conf file: $LOGGLY_RSYSLOG_CONFFILE to $LOGGLY_RSYSLOG_CONFFILE_BACKUP";
				sudo mv -f $LOGGLY_RSYSLOG_CONFFILE $LOGGLY_RSYSLOG_CONFFILE_BACKUP;
				checkAuthTokenAndWriteContents;
				break;;
				[Nn]* ) break;;
				* ) echo "Please answer yes or no.";;
			esac
		done
	else
		logMsgToConfigSysLog "INFO" "INFO: Loggly rsyslog file $LOGGLY_RSYSLOG_CONFFILE does not exist, creating file $LOGGLY_RSYSLOG_CONFFILE"
		checkAuthTokenAndWriteContents
	fi
}

#check if authentication token is valid and then write contents to 22-loggly.conf file to /etc/rsyslog.d directory
checkAuthTokenAndWriteContents()
{
	if [ "$LOGGLY_ACCOUNT" != "" ]; then
		writeContents $LOGGLY_ACCOUNT $LOGGLY_AUTH_TOKEN $LOGGLY_DISTRIBUTION_ID $LOGS_01_HOST $LOGGLY_SYSLOG_PORT
		restartRsyslog
	else
		logMsgToConfigSysLog "ERROR" "ERROR: Loggly auth token is required to configure rsyslog. Please pass -a <auth token> while running script."
		exit 1
	fi
}

#write the contents to 22-loggly.conf file
writeContents()
{
inputStr="
#          -------------------------------------------------------
#          Syslog Logging Directives for Loggly ($1.loggly.com)
#          -------------------------------------------------------

# Define the template used for sending logs to Loggly. Do not change this format.
\$template LogglyFormat,\"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$2@$3] %msg%\"

# Send messages to Loggly over TCP using the template.
*.*             @@$4:$5;LogglyFormat

#          -------------------------------------------------------
#          End of Syslog Logging Directives for Loggly
#          -------------------------------------------------------
"
sudo cat << EOIPFW >> $LOGGLY_RSYSLOG_CONFFILE
$inputStr
EOIPFW
}

#create /var/spool/rsyslog directory if not already present. Modify the permission of this directory for Ubuntu
createRsyslogDir()
{
	if [ -d "$RSYSLOG_DIR" ]; then
		logMsgToConfigSysLog "INFO" "INFO: $RSYSLOG_DIR already exist, so not creating directory."
		if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
			logMsgToConfigSysLog "INFO" "INFO: Changing the permission on the rsyslog in /var/spool"
			sudo chown -R syslog:adm $RSYSLOG_DIR
		fi
	else
		logMsgToConfigSysLog "INFO" "INFO: Creating directory $SYSLOGDIR"
		sudo mkdir -v $RSYSLOG_DIR
		if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
			sudo chown -R syslog:adm $RSYSLOG_DIR
		fi
	fi
}

#check if the logs made it to Loggly
checkIfLogsMadeToLoggly()
{
	logMsgToConfigSysLog "INFO" "INFO: Sending test message to Loggly."
	uuid=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

	queryParam="syslog.appName%3ALOGGLYVERIFY%20$uuid"
	logger -t "LOGGLYVERIFY" "LOGGLYVERIFY-Test message for verification with UUID $uuid"

	counter=1
	maxCounter=10
	finalCount=0

	queryUrl="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$queryParam"
	logMsgToConfigSysLog "INFO" "INFO: Search URL: $queryUrl"

	logMsgToConfigSysLog "INFO" "INFO: Verifying if the log made it to Loggly."
	logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
	searchAndFetch finalCount "$queryUrl"
	let counter=$counter+1

	while [ "$finalCount" -eq 0 ]; do
		echo "INFO: Did not find the test log message in Loggly's search yet. Waiting for 30 secs."
		sleep 30
		echo "INFO: Done waiting. Verifying again."
		logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
		searchAndFetch finalCount "$queryUrl"
		let counter=$counter+1
		if [ "$counter" -gt "$maxCounter" ]; then
			MANUAL_CONFIG_INSTRUCTION=$MANUAL_CONFIG_INSTRUCTION" Rsyslog troubleshooting instructions are available at https://www.loggly.com/docs/troubleshooting-rsyslog/"
			logMsgToConfigSysLog "ERROR" "ERROR: Verification logs did not make it to Loggly in time. Please check your token & network/firewall settings and retry."
			exit 1
		fi
	done

	if [ "$finalCount" -eq 1 ]; then
		logMsgToConfigSysLog "SUCCESS" "SUCCESS: Verification logs successfully transferred to Loggly! You are now sending Linux system logs to Loggly."
		if [ "$IS_INVOKED" = "" ]; then
			exit 0
		fi
	fi

}

#delete 22-loggly.conf file
remove22LogglyConfFile()
{
	if [ -f "$LOGGLY_RSYSLOG_CONFFILE" ]; then
		sudo rm -rf "$LOGGLY_RSYSLOG_CONFFILE"
	fi
}

#compares two version numbers, used for comparing versions of various softwares
compareVersions ()
{
	typeset    IFS='.'
	typeset -a v1=( $1 )
	typeset -a v2=( $2 )
	typeset    n diff

	for (( n=0; n<$3; n+=1 )); do
	diff=$((v1[n]-v2[n]))
	if [ $diff -ne 0 ] ; then
		[ $diff -le 0 ] && echo '-1' || echo '1'
		return
	fi
	done
	echo  '0'
}

#restart rsyslog
restartRsyslog()
{
	logMsgToConfigSysLog "INFO" "INFO: Restarting the $RSYSLOG_SERVICE service."
	sudo service $RSYSLOG_SERVICE restart
	if [ $? -ne 0 ]; then
		logMsgToConfigSysLog "WARNING" "WARNING: $RSYSLOG_SERVICE did not restart gracefully. Please restart $RSYSLOG_SERVICE manually."
	fi
}

#logs message to config syslog
logMsgToConfigSysLog()
{
	#$1 variable will be SUCCESS or ERROR or INFO or WARNING
	#$2 variable will be the message
	cslStatus=$1
	cslMessage=$2
	echo "$cslMessage"
	currentTime=$(date)

	#for Linux system, we need to use -d switch to decode base64 whereas
	#for Mac system, we need to use -D switch to decode
	varUname=$(uname)
	if [[ $varUname == 'Linux' ]]; then
		enabler=$(echo MWVjNGU4ZTEtZmJiMi00N2U3LTkyOWItNzVhMWJmZjVmZmUw | base64 -d)
	elif [[ $varUname == 'Darwin' ]]; then
		enabler=$(echo MWVjNGU4ZTEtZmJiMi00N2U3LTkyOWItNzVhMWJmZjVmZmUw | base64 -D)
	fi

	if [ $? -ne 0 ]; then
        echo  "ERROR: Base64 decode is not supported on your Operating System. Please update your system to support Base64."
        exit 1
	fi

	sendPayloadToConfigSysLog "$cslStatus" "$cslMessage" "$enabler"

	#if it is an error, then log message "Script Failed" to config syslog and exit the script
	if [[ $cslStatus == "ERROR" ]]; then
		sendPayloadToConfigSysLog "ERROR" "Script Failed" "$enabler"
		echo $MANUAL_CONFIG_INSTRUCTION
		exit 1
	fi

	#if it is a success, then log message "Script Succeeded" to config syslog and exit the script
	if [[ $cslStatus == "SUCCESS" ]]; then
		sendPayloadToConfigSysLog "SUCCESS" "Script Succeeded" "$enabler"
	fi
}

#payload construction to send log to config syslog
sendPayloadToConfigSysLog()
{
	if [ "$APP_TAG" = "" ]; then
		var="{\"sub-domain\":\"$LOGGLY_ACCOUNT\", \"host-name\":\"$HOST_NAME\", \"script-name\":\"$SCRIPT_NAME\", \"script-version\":\"$SCRIPT_VERSION\", \"status\":\"$1\", \"time-stamp\":\"$currentTime\", \"linux-distribution\":\"$LINUX_DIST\", \"messages\":\"$2\"}"
	else
		var="{\"sub-domain\":\"$LOGGLY_ACCOUNT\", \"host-name\":\"$HOST_NAME\", \"script-name\":\"$SCRIPT_NAME\", \"script-version\":\"$SCRIPT_VERSION\", \"status\":\"$1\", \"time-stamp\":\"$currentTime\", \"linux-distribution\":\"$LINUX_DIST\", $APP_TAG, \"messages\":\"$2\"}"
	fi
	curl -s -H "content-type:application/json" -d "$var" $LOGS_01_URL/inputs/$3 > /dev/null 2>&1
}

#$1 return the count of records in loggly, $2 is the query param to search in loggly
searchAndFetch()
{
	url=$2
	result=$(wget -qO- /dev/null --user "$LOGGLY_USERNAME" --password "$LOGGLY_PASSWORD" "$url")
	if [ -z "$result" ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Please check your network/firewall settings & ensure Loggly subdomain, username and password is specified correctly."
		exit 1
	fi
	id=$(echo "$result" | grep -v "{" | grep id | awk '{print $2}')
	# strip last double quote from id
	id="${id%\"}"
	# strip first double quote from id
	id="${id#\"}"
	url="$LOGGLY_ACCOUNT_URL/apiv2/events?rsid=$id"

	# retrieve the data
	result=$(wget -qO- /dev/null --user "$LOGGLY_USERNAME" --password "$LOGGLY_PASSWORD" "$url")
	count=$(echo "$result" | grep total_events | awk '{print $2}')
	count="${count%\,}"
	eval $1="'$count'"
	if [ "$count" -gt 0 ]; then
		timestamp=$(echo "$result" | grep timestamp)
	fi
}

#get password in the form of asterisk
getPassword()
{
	unset LOGGLY_PASSWORD
	prompt="Please enter Loggly Password:"
	while IFS= read -p "$prompt" -r -s -n 1 char
	do
		if [[ $char == $'\0' ]]
		then
			break
		fi
		prompt='*'
		LOGGLY_PASSWORD+="$char"
	done
	echo
}

#display usage syntax
usage()
{
cat << EOF
usage: configure-linux [-a loggly auth account or subdomain] [-t loggly token] [-u username] [-p password (optional)]
usage: configure-linux [-r to remove]
usage: configure-linux [-h for help]
EOF
}

##########  Get Inputs from User - Start  ##########
if [ "$1" != "being-invoked" ]; then
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
			-r | --remove )
				LOGGLY_REMOVE="true"
				;;
			-h | --help)
				usage
				exit
				;;
			*) usage
			exit
			;;
			esac
			shift
		done
	fi

	if [ "$LOGGLY_REMOVE" != "" ]; then
		removeLogglyConf
	elif [ "$LOGGLY_AUTH_TOKEN" != "" -a "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" ]; then
		if [ "$LOGGLY_PASSWORD" = "" ]; then
			getPassword
		fi
		installLogglyConf
	else
		usage
	fi
else
	IS_INVOKED="true"
fi

##########  Get Inputs from User - End  ##########
