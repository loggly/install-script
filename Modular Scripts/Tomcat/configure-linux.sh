#!/bin/bash

##########  Variable Declarations - Start  ##########

#name of the current script. This will get overwritten by the child script which calls this
SCRIPT_NAME=configure-linux.sh
#version of the current script. This will get overwritten by the child script which calls this
SCRIPT_VERSION=1.0
#minimum version of syslog to enable logging to loggly
MIN_SYSLOG_VERSION=5.8.0

#application tag. This will get overwritten by the child script which calls this
APP_TAG=

#directory location for syslog
SYSLOG_ETCDIR_CONF=/etc/rsyslog.d
#name and location of loggly syslog file
LOGGLY_SYSLOG_CONFFILE=$SYSLOG_ETCDIR_CONF/22-loggly.conf
#syslog directory
SYSLOG_DIR=/var/spool/rsyslog

#this variable will hold the host name
HOST_NAME=
#this variable will hold the name of the linux distribution
LINUX_DIST=

#this variable will hold the users syslog version
SYSLOG_VERSION=

#host name for logs-01.loggly.com
LOGS_01_HOST=logs-01.loggly.com
LOGS_01_URL=https://$LOGS_01_HOST
#this variable will contain loggly account url in the format
#https://$LOGGLY_ACCOUNT.loggly.com
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
#this variable will hold if debug is enabled by the user.
#this option is not used at present
LOGGLY_DEBUG=
#this variable will identify if the user has selected to rollback settings
LOGGLY_ROLLBACK=
#this variable will hold the user name provided by user
#this is a mandatory input
LOGGLY_USERNAME=
#this variable will hold the password provided by user
#this is a mandatory input
LOGGLY_PASSWORD=

#Instruction link on how to configure loggly on linux manually. This will get overwritten by the child script which calls this
#on how to configure the child application
MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure rsyslog on Linux is available at https://www.loggly.com/docs/rsyslog-manual-configuration/"
##########  Variable Declarations - End  ##########

#sets linux variables which will be used across various functions
setLinuxVariables()
{
	#set host name
	HOST_NAME=$(hostname)

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

	#set loggly account url
	LOGGLY_ACCOUNT_URL=https://$LOGGLY_ACCOUNT.loggly.com
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


#checks if all the various endpoints used for configuring loggly are accessible
checkLogglyServersAccessiblilty()
{
	echo "INFO: Checking if $LOGGLY_ACCOUNT_URL is reachable"
	if [ $(curl -s --head  --request GET $LOGGLY_ACCOUNT_URL/login | grep "200 OK" | wc -l) == 1 ]; then
		echo "INFO: $LOGGLY_ACCOUNT_URL is reachable"
	else
		logMsgToConfigSysLog "WARNING" "WARNING: $LOGGLY_ACCOUNT_URL is not reachable. Please check your network and firewall settings. Continuing to configure Loggly on your system."
	fi

	echo "INFO: Checking if $LOGS_01_HOST is reachable"
	if [ $(ping -c 1 $LOGS_01_HOST | grep "1 packets transmitted, 1 received, 0% packet loss" | wc -l) == 1 ]; then
		echo "INFO: $LOGS_01_HOST is reachable"
	else
		logMsgToConfigSysLog "WARNING" "WARNING: $LOGS_01_HOST is not reachable. Please check your network and firewall settings. Continuing to configure Loggly on your system."
	fi

	echo "INFO: Checking if provided username and password is correct"
	if [ $(curl -s -u $LOGGLY_USERNAME:$LOGGLY_PASSWORD $LOGGLY_ACCOUNT_URL/apiv2/customer | grep "Unauthorized" | wc -l) == 1 ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Invalid Loggly username or password."
		exit 1
	else
		logMsgToConfigSysLog "INFO" "INFO: Username and password authorized successfully."
	fi
}

# executing the script for loggly to install and configure syslog.
configureLogglyForLinux()
{
	checkIfUserHasRootPrivileges
	setLinuxVariables
	logMsgToConfigSysLog "INFO" "INFO: Initiating Configure Loggly for Linux."
	checkLogglyServersAccessiblilty

	sudo service rsyslog start
	SYSLOG_VERSION=$(sudo rsyslogd -version | grep "rsyslogd")
	SYSLOG_VERSION=${SYSLOG_VERSION#* }
	SYSLOG_VERSION=${SYSLOG_VERSION%,*}
	SYSLOG_VERSION=$SYSLOG_VERSION | tr -d " "
	if [ $(compareVersions $SYSLOG_VERSION $MIN_SYSLOG_VERSION 3) -lt 0 ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Min syslog version required is 5.8.0."
		exit 1
	fi

	echo "INFO: Checking if loggly sysconf file $LOGGLY_SYSLOG_CONFFILE exist"
	# if the loggly configuration file exist, then don't create it.
	if [ -f "$LOGGLY_SYSLOG_CONFFILE" ]; then
		logMsgToConfigSysLog "INFO" "INFO: Loggly syslog file $LOGGLY_SYSLOG_CONFFILE exist, not creating file."
	else
		logMsgToConfigSysLog "INFO" "INFO: Creating file $LOGGLY_SYSLOG_CONFFILE"
		if [ "$LOGGLY_ACCOUNT" != "" ]; then
			wget -q -O - $LOGGLY_COM_URL/install/configure-syslog.py | sudo python - setup --auth $LOGGLY_AUTH_TOKEN --account $LOGGLY_ACCOUNT
		else
			logMsgToConfigSysLog "ERROR" "ERROR: Loggly auth token is required to configure rsyslog. Please pass -a <auth token> while running script."
			exit 1
		fi
	fi

	# Create rsyslog dir if it doesn't exist, Modify the rsyslog directory if exist
	if [ -d "$SYSLOG_DIR" ]; then
		logMsgToConfigSysLog "INFO" "INFO: $SYSLOG_DIR exist, not creating dir."
		if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
			logMsgToConfigSysLog "INFO" "INFO: Changing the permission on the rsyslog in /var/spool."
			sudo chown -R syslog:adm $SYSLOG_DIR
		fi
	else
		logMsgToConfigSysLog "INFO" "INFO: Creating directory $SYSLOGDIR."
		sudo mkdir -v $SYSLOG_DIR
		 if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
			sudo chown -R syslog:adm $SYSLOG_DIR
		fi
	fi
	
	logMsgToConfigSysLog "SUCCESS" "SUCCESS: Linux system successfully configured to send logs via Loggly."

}
# End of configure rsyslog for linux


#restart syslog
restartsyslog()
{
	logMsgToConfigSysLog "INFO" "INFO: Restarting the rsyslog service."
	sudo service rsyslog restart
	if [ $? -ne 0 ]; then
		logMsgToConfigSysLog "WARNING" "WARNING: rsyslog did not restart gracefully. Please restart rsyslog manually."
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

sendPayloadToConfigSysLog()
{
	if [ "$APP_TAG" = "" ]; then
		var="{\"sub-domain\":\"$LOGGLY_ACCOUNT\", \"host-name\":\"$HOST_NAME\", \"script-name\":\"$SCRIPT_NAME\", \"script-version\":\"$SCRIPT_VERSION\", \"status\":\"$1\", \"time-stamp\":\"$currentTime\", \"linux-distribution\":\"$LINUX_DIST\", \"messages\":\"$2\"}"
	else
		var="{\"sub-domain\":\"$LOGGLY_ACCOUNT\", \"host-name\":\"$HOST_NAME\", \"script-name\":\"$SCRIPT_NAME\", \"script-version\":\"$SCRIPT_VERSION\", \"status\":\"$1\", \"time-stamp\":\"$currentTime\", \"linux-distribution\":\"$LINUX_DIST\", $APP_TAG, \"messages\":\"$2\"}"
	fi
	curl -s -H "content-type:application/json" -d "$var" $LOGS_01_URL/inputs/$3 > /dev/null 2>&1
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

#checks if user has root privileges
checkIfUserHasRootPrivileges()
{
	#This script needs to be run as a sudo user
	if [[ $EUID -ne 0 ]]; then
	   logMsgToConfigSysLog "ERROR" "ERROR: This script must be run as root."
	   exit 1
	fi
}

#display usage syntax
usage()
{
cat << EOF
usage: configure-linux [-a loggly auth account or subdomain] [-t loggly token] [-u username] [-p password (optional)]
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
		  -h | --help)
			  usage
			  exit
			  ;;
		esac
		shift
	done
	fi

	if [ "$LOGGLY_DEBUG" != ""  -a  "$LOGGLY_AUTH_TOKEN" != "" -a "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" ]; then
		if [ "$LOGGLY_PASSWORD" = "" ]; then
			getPassword
		fi
		debug
	elif [ "$LOGGLY_AUTH_TOKEN" != "" -a "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" ]; then
		if [ "$LOGGLY_PASSWORD" = "" ]; then
			getPassword
		fi
		configureLogglyForLinux
	elif [ "$LOGGLY_ROLLBACK" != "" ]; then
		rollback
	else
		usage
	fi
fi

##########  Get Inputs from User - End  ##########
