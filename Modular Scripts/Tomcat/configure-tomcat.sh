#!/bin/bash

source configure-linux.sh "being-invoked"

##########  Variable Declarations - Start  ##########
#name of the current script
SCRIPT_NAME=configure-tomcat.sh
#version of the current script
SCRIPT_VERSION=1.0

#minimum version of tomcat to enable log rotation
MIN_TOMCAT_VERSION=6.0.33.0

#we have not found the tomcat version yet at this point in the script
APP_TAG="\"tomcat-version\":\"\""

#name of the service, in this case tomcat6
SERVICE=tomcat6
#directory location for syslog
SYSLOG_ETCDIR_CONF=/etc/rsyslog.d
#name and location of tomcat syslog file
TOMCAT_SYSLOG_CONFFILE=$SYSLOG_ETCDIR_CONF/21-tomcat.conf
#syslog directory
SYSLOG_DIR=/var/spool/rsyslog

#this variable will hold the host name
HOST_NAME=
#this variable will hold the name of the linux distribution
LINUX_DIST=

#this variable will hold the path to the catalina home
LOGGLY_CATALINA_HOME=
#this variable will hold the path to the conf folder within catalina home
LOGGLY_CATALINA_CONF_HOME=
#this variable will hold the path to the logging.properties file within
#catalina_home/conf directory
LOGGLY_CATALINA_PROPFILE=
#this variable will hold the path to the logging.properties.loggly.bk file we
#create to take a backup of logging.properties within catalina_home/conf directory
LOGGLY_CATALINA_BACKUP_PROPFILE=
#this variable will hold the value of the tomcat log folder
LOGGLY_CATALINA_LOG_HOME=
#this variable will hold the path of the catalina.jar file
CATALINA_JAR_PATH=
#this variable will hold the users tomcat version
TOMCAT_VERSION=
#this variable will hold the location of log4j files path
LOG4J_FILE_PATH=

#this variable will hold the catalina home provide by user.
#this is not a mandatory input
LOGGLY_CATALINA_HOME=

MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure Tomcat is available at https://www.loggly.com/docs/tomcat-application-server"
##########  Variable Declarations - End  ##########

#sets tomcat variables which will be used across various functions
setTomcatVariables()
{
#get CATALINA_HOME, this sets the value for LOGGLY_CATALINA_HOME variable
getCatalinaHome $SERVICE

#set value for catalina conf home path, logging.properties path and
#logging.properties.loggly.bk path
LOGGLY_CATALINA_CONF_HOME=$LOGGLY_CATALINA_HOME/conf
LOGGLY_CATALINA_PROPFILE=$LOGGLY_CATALINA_CONF_HOME/logging.properties
LOGGLY_CATALINA_BACKUP_PROPFILE=$LOGGLY_CATALINA_PROPFILE.loggly.bk

LOGGLY_CATALINA_LOG_HOME=/var/log/$SERVICE

#default path for catalina.jar
CATALINA_JAR_PATH=$LOGGLY_CATALINA_HOME/lib/catalina.jar

#check if the identified CATALINA_HOME has the catalina.jar
if [ ! -f "$CATALINA_JAR_PATH" ]; then
	#if not, search it throughout the system. If we find no entries or more than
	#1 entry, then we cannot determine the version of the tomcat
	logMsgToConfigSysLog "INFO" "INFO: Could not find catalina.jar in $LOGGLY_CATALINA_HOME/lib. Searching at other locations, this may take some time."
	if [ $(sudo find / -name catalina.jar | grep tomcat6 | wc -l) = 1 ]; then
			CATALINA_JAR_PATH=$(sudo find / -name catalina.jar | grep tomcat6)
			logMsgToConfigSysLog "INFO" "INFO: Found catalina.jar at $CATALINA_JAR_PATH."
	else
		logMsgToConfigSysLog "WARNING" "WARNING: Unable to determine the correct version of tomcat 6. Assuming its >= to 6.0.33."
	fi
fi

#get the tomcat version number
if [ -f "$CATALINA_JAR_PATH" ]; then
	TOMCAT_VERSION=$(sudo java -cp $CATALINA_JAR_PATH org.apache.catalina.util.ServerInfo | grep "Server number")
	TOMCAT_VERSION=${TOMCAT_VERSION#*: }
	TOMCAT_VERSION=$TOMCAT_VERSION | tr -d ' '
	APP_TAG="\"tomcat-version\":\"$TOMCAT_VERSION\""

	tomcatMajorVersion=${TOMCAT_VERSION%%.*}
	if [ $tomcatMajorVersion -ne 6 ]; then
			echo "ERROR" "ERROR: This script only supports Tomcat version 6."
			exit 1
	fi
fi
}

#try to deduce tomcat home if user has not provided one
getCatalinaHome()
{
	#if user has not provided the catalina home
	if [ "$LOGGLY_CATALINA_HOME" = "" ]; then
		case "$LINUX_DIST" in
			*"Ubuntu"* )
			checkIfValidCatalinaHome "/var/lib/$1"
			;;
			*"Red Hat"* )
			checkIfValidCatalinaHome "/usr/share/$1"
			;;
			*"CentOS"* )
			checkIfValidCatalinaHome "/usr/share/$1"
			;;
		esac
	else
		checkIfValidCatalinaHome "$LOGGLY_CATALINA_HOME"
	fi
	logMsgToConfigSysLog "INFO" "INFO: CATALINA HOME: $LOGGLY_CATALINA_HOME"
}

#checks if the catalina home is a valid one by searching for logging.properties and
#checks for startup.sh if tomcat is not configured as service
checkIfValidCatalinaHome()
{
	LOGGLY_CATALINA_HOME=$1
	#check if logging.properties files  is present
	if [ ! -f "$LOGGLY_CATALINA_HOME/conf/logging.properties" ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Unable to find conf/logging.properties file within $LOGGLY_CATALINA_HOME. Please provide correct Catalina Home using -ch option."
		exit 1
	#check if tomcat is configured as a service. If no, then check if we have access to startup.sh file
	elif [ ! -f /etc/init.d/$SERVICE ]; then
		logMsgToConfigSysLog "INFO" "INFO: Tomcat is not configured as a service"
		if [ ! -f "$LOGGLY_CATALINA_HOME/bin/startup.sh" ]; then
			logMsgToConfigSysLog "ERROR" "ERROR: Unable to find bin/startup.sh file within $LOGGLY_CATALINA_HOME. Please provide correct Catalina Home using -ch option."
			exit 1
		fi
	fi
}


#checks if the tomcat is already configured with log4j. If yes, then exit
checkIfTomcatConfiguredWithLog4J()
{
	echo "INFO: Checking if tomcat is configured with log4j logger"
	#default path for log4j files
	LOG4J_FILE_PATH=$LOGGLY_CATALINA_HOME/lib/log4j*
	#check if the log4j files are present, if yes, then exit
	if ls $LOG4J_FILE_PATH > /dev/null 2>&1; then
		logMsgToConfigSysLog "ERROR" "ERROR: Script does not support log4j logger. Please see $LOGGLY_COM_URL/docs/java-log4j"
		exit 1
	else
		#if not found in the default path, check in the path where catalina.jar is found
		libDirName=$(dirname ${CATALINA_JAR_PATH})
		LOG4J_FILE_PATH=$libDirName/log4j*
		if ls $LOG4J_FILE_PATH > /dev/null 2>&1; then
			logMsgToConfigSysLog "ERROR" "ERROR: Script does not support log4j logger. Please see $LOGGLY_COM_URL/docs/java-log4j"
			exit 1
		fi
	fi
	logMsgToConfigSysLog "INFO" "INFO: Tomcat seems not to be configured with log4j logger"
}

# executing the script for loggly to install and configure syslog.
configureLogglyForTomcat()
{
	configureLogglyForLinux
	setTomcatVariables

	logMsgToConfigSysLog "INFO" "INFO: Tomcat logging properties file: $LOGGLY_CATALINA_PROPFILE"

	# backup the logging properties file just in case it need to reverted.
	echo "INFO: Going to back up the properties file: $LOGGLY_CATALINA_PROPFILE to $LOGGLY_CATALINA_BACKUP_PROPFILE."
	if [ ! -f $LOGGLY_CATALINA_PROPFILE ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: logging.properties file not found!. Looked at location $LOGGLY_CATALINA_PROPFILE."
		exit 1
	else
		# dont take a backup of logging properties file if it is already there
		if [ ! -f $LOGGLY_CATALINA_BACKUP_PROPFILE ]; then
			sudo cp -f $LOGGLY_CATALINA_PROPFILE $LOGGLY_CATALINA_BACKUP_PROPFILE
		fi
	fi

	#check if tomcat version is less than 6.0.33.0, if yes, throw a warning
	if [ $(compareVersions $TOMCAT_VERSION $MIN_TOMCAT_VERSION 4) -lt 0 ]; then
		logMsgToConfigSysLog "WARNING" "WARNING: Tomcat version is less than 6.0.33. Log rotation cannot be disabled for version <6.0.33; only catalina.out log will be monitored."
	fi

	#Log rotation is not supported on version below 6.0.33.0, logging.properties should not be modified
	#in such case. If version is above 6.0.33.0, then do the following
	if [ $(compareVersions $TOMCAT_VERSION $MIN_TOMCAT_VERSION 4) -ge 0 ]; then
		#removing the end . from logging.properties variable 1catalina.org.apache.juli.FileHandler.prefix = catalina.
		if grep -Fq "prefix = catalina." $LOGGLY_CATALINA_PROPFILE
		then
			sudo sed -i "s/prefix = catalina./prefix = catalina/g" $LOGGLY_CATALINA_PROPFILE
		fi
		if grep -Fq "prefix = localhost." $LOGGLY_CATALINA_PROPFILE
		then
			sudo sed -i "s/prefix = localhost./prefix = localhost/g" $LOGGLY_CATALINA_PROPFILE
		fi
		if grep -Fq "prefix = manager." $LOGGLY_CATALINA_PROPFILE
		then
			sudo sed -i "s/prefix = manager./prefix = manager/g" $LOGGLY_CATALINA_PROPFILE
		fi
		if grep -Fq "prefix = host-manager." $LOGGLY_CATALINA_PROPFILE
		then
			sudo sed -i "s/prefix = host-manager./prefix = host-manager/g" $LOGGLY_CATALINA_PROPFILE
		fi

		#Check if the rotatable property is present in logging.properties
		if grep -Fq "rotatable" $LOGGLY_CATALINA_PROPFILE
		then
			#If present, set all the values to false
			sed -i -e 's/rotatable = true/rotatable = false/g' $LOGGLY_CATALINA_PROPFILE
		fi

		if [ $(fgrep "rotatable = false" "$LOGGLY_CATALINA_PROPFILE" | wc -l) -lt 4 ]; then
			#If rotatable property present or not, add the following lines to disable rotation in any case
sudo cat << EOIPFW >> $LOGGLY_CATALINA_PROPFILE
1catalina.org.apache.juli.FileHandler.rotatable = false
2localhost.org.apache.juli.FileHandler.rotatable = false
3manager.org.apache.juli.FileHandler.rotatable = false
4host-manager.org.apache.juli.FileHandler.rotatable = false
EOIPFW
		fi
	fi

	#Create tomcat syslog config file if it doesn't exist
	echo "INFO: Checking if tomcat sysconf file $TOMCAT_SYSLOG_CONFFILE exist."
	if [ -f "$TOMCAT_SYSLOG_CONFFILE" ]; then
	   logMsgToConfigSysLog "INFO" "INFO: Tomcat syslog file $TOMCAT_SYSLOG_CONFFILE exist, not creating file."
	else
	   logMsgToConfigSysLog "INFO" "INFO: Creating file $TOMCAT_SYSLOG_CONFFILE."
	   sudo touch $TOMCAT_SYSLOG_CONFFILE
	   sudo chmod o+w $TOMCAT_SYSLOG_CONFFILE
	   generateTomcat21File
	fi

	tomcatInitialLogCount=0
	tomcatLatestLogCount=0
	queryParam="tag%3Atomcat&from=-15m&until=now&size=1"
	searchAndFetch tomcatInitialLogCount "$queryParam"

	logMsgToConfigSysLog "INFO" "INFO: Restarting rsyslog and tomcat to generate logs for verification."
	# restart the syslog service.
	restartsyslog
	# restart the tomcat service.
	restartTomcat
	searchAndFetch tomcatLatestLogCount "$queryParam"

	counter=1
	maxCounter=10
	#echo "latest tomcat log count: $tomcatLatestLogCount and before query count: $tomcatInitialLogCount"
	while [ "$tomcatLatestLogCount" -le "$tomcatInitialLogCount" ]; do
		echo "######### waiting for 30 secs while loggly processes the test events."
		sleep 30
		echo "######## Done waiting. verifying again..."
		logMsgToConfigSysLog "INFO" "INFO: Try # $counter of total $maxCounter"
		searchAndFetch tomcatLatestLogCount "$queryParam"
		#echo "Again Fetch: initial count $tomcatInitialLogCount : latest count : $tomcatLatestLogCount  counter: $counter  max counter: $maxCounter"
		let counter=$counter+1
		if [ "$counter" -gt "$maxCounter" ]; then
			logMsgToConfigSysLog "ERROR" "ERROR: Tomcat logs did not make to Loggly in stipulated time. Please check your token & network/firewall settings and retry."
			exit 1
		fi
	done

	if [ "$tomcatLatestLogCount" -gt "$tomcatInitialLogCount" ]; then
		logMsgToConfigSysLog "SUCCESS" "SUCCESS: Tomcat logs successfully transferred to Loggly."
		exit 0
	fi
}
# End of configure rsyslog for tomcat

#function to generate tomcat syslog config file
generateTomcat21File()
{

	imfileStr="\$ModLoad imfile
	\$WorkDirectory $SYSLOG_DIR
	"
	if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
		imfileStr+="\$PrivDropToGroup adm
		"
	fi

	imfileStr+="
	#parameterized token here.......
	#Add a tag for tomcat events
	\$template LogglyFormatTomcat,\"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$LOGGLY_AUTH_TOKEN@41058 tag=\\\"tomcat\\\"] %msg%\n\"

	# catalina.out
	\$InputFileName $LOGGLY_CATALINA_LOG_HOME/catalina.out
	\$InputFileTag catalina-out
	\$InputFileStateFile stat-catalina-out
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor
	if \$programname == 'catalina-out' then @@logs-01.loggly.com:514;LogglyFormatTomcat
	if \$programname == 'catalina-out' then ~

	# initd.log
	\$InputFileName $LOGGLY_CATALINA_LOG_HOME/initd.log
	\$InputFileTag initd
	\$InputFileStateFile stat-initd
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor
	if \$programname == 'initd' then @@logs-01.loggly.com:514;LogglyFormatTomcat
	if \$programname == 'initd' then ~
	"

	#if log rotation is enabled i.e. tomcat version is greater than or equal to
	#6.0.33.0, then add the following lines to tomcat syslog conf file
	if [ $(compareVersions $TOMCAT_VERSION $MIN_TOMCAT_VERSION 4) -ge 0 ]; then
	imfileStr+="
	# catalina.log
	\$InputFileName $LOGGLY_CATALINA_LOG_HOME/catalina.log
	\$InputFileTag catalina-log
	\$InputFileStateFile stat-catalina-log
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor
	if \$programname == 'catalina-log' then @@logs-01.loggly.com:514;LogglyFormatTomcat
	if \$programname == 'catalina-log' then ~

	# host-manager.log
	\$InputFileName $LOGGLY_CATALINA_LOG_HOME/host-manager.log
	\$InputFileTag host-manager
	\$InputFileStateFile stat-host-manager
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor
	if \$programname == 'host-manager' then @@logs-01.loggly.com:514;LogglyFormatTomcat
	if \$programname == 'host-manager' then ~

	# localhost.log
	\$InputFileName $LOGGLY_CATALINA_LOG_HOME/localhost.log
	\$InputFileTag localhost-log
	\$InputFileStateFile stat-localhost-log
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor
	if \$programname == 'localhost-log' then @@logs-01.loggly.com:514;LogglyFormatTomcat
	if \$programname == 'localhost-log' then ~

	# manager.log
	\$InputFileName $LOGGLY_CATALINA_LOG_HOME/manager.log
	\$InputFileTag manager
	\$InputFileStateFile stat-manager
	\$InputFileSeverity info
	\$InputFilePersistStateInterval 20000
	\$InputRunFileMonitor
	if \$programname == 'manager' then @@logs-01.loggly.com:514;LogglyFormatTomcat
	if \$programname == 'manager' then ~
	"
	fi

	#change the tomcat-21 file to variable from above and also take the directory of the tomcat log file.
sudo cat << EOIPFW >> $TOMCAT_SYSLOG_CONFFILE
$imfileStr
EOIPFW
}

#rollback tomcat loggly configuration
rollback()
{
	checkIfUserHasRootPrivileges
	setLinuxVariables
	setTomcatVariables
	logMsgToConfigSysLog "INFO" "INFO: Initiating rollback"
	echo "INFO: Reverting the catalina file."
	if [ -f "$LOGGLY_CATALINA_BACKUP_PROPFILE" ]; then
		sudo rm -fr $LOGGLY_CATALINA_PROPFILE
		sudo cp -f $LOGGLY_CATALINA_BACKUP_PROPFILE $LOGGLY_CATALINA_PROPFILE
		sudo rm -fr $LOGGLY_CATALINA_BACKUP_PROPFILE
	fi
	echo "INFO: Deleting the loggly tomcat syslog conf file."
	if [ -f "$TOMCAT_SYSLOG_CONFFILE" ]; then
		sudo rm -rf "$TOMCAT_SYSLOG_CONFFILE"
	fi
	echo "INFO: Removed all the modified files."
	restartTomcat
	logMsgToConfigSysLog "INFO" "INFO: Rollback completed."
}

#$1 return the count of records in loggly, $2 is the query param to search in loggly
searchAndFetch()
{
    searchquery="$2"
    url="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$searchquery"
    logMsgToConfigSysLog "INFO" "INFO: Search URL: $url"
    result=$(wget -qO- /dev/stdout --user "$LOGGLY_USERNAME" --password "$LOGGLY_PASSWORD" "$url")
    if [ -z "$result" ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Please check your network/firewall settings & ensure Loggly subdomain, username and password is specified correctly."
		exit 1
    fi
    id=$(echo "$result" | grep -v "{" | grep id | awk '{print $2}')
    # strip last double quote from id
    id="${id%\"}"
    # strip first double quote from id
    id="${id#\"}"
    #echo "rsid for the search is: $id"
    url="$LOGGLY_ACCOUNT_URL/apiv2/events?rsid=$id"

    # retrieve the data
    result=$(wget -qO- /dev/stdout --user "$LOGGLY_USERNAME" --password "$LOGGLY_PASSWORD" "$url")
	#echo "actual result based on rsid: $result"
    count=$(echo "$result" | grep total_events | awk '{print $2}')
    count="${count%\,}"
    eval $1="'$count'"
    echo "Count of events from loggly: "$count""
    if [ "$count" > 0 ]; then
        timestamp=$(echo "$result" | grep timestamp)
		#echo "timestamp: "$timestamp""
        #echo "Data made successfully to loggly!!!"
    fi
}

#restart tomcat
restartTomcat()
{
	#sudo service tomcat restart or home/bin/start.sh
	if [ $(ps -ef | grep -v grep | grep "$SERVICE" | wc -l) > 0 ]; then
		logMsgToConfigSysLog "INFO" "INFO: $SERVICE is running"
		if [ -f /etc/init.d/$SERVICE ]; then
			logMsgToConfigSysLog "INFO" "INFO: $SERVICE is running as service."
			logMsgToConfigSysLog "INFO" "INFO: Restarting the tomcat service."
			sudo service $SERVICE restart
			if [ $? -ne 0 ]; then
				logMsgToConfigSysLog "WARNING" "WARNING: Tomcat did not restart gracefully. Log rotation may not be disabled. Please restart tomcat manually."
			fi
		else
			logMsgToConfigSysLog "INFO" "INFO: $SERVICE is not running as service."
			# To be commented only for test
			logMsgToConfigSysLog "INFO" "INFO: Shutting down tomcat."
			sudo $LOGGLY_CATALINA_HOME/bin/shutdown.sh
			if [ $? -ne 0 ]; then
				logMsgToConfigSysLog "WARNING" "WARNING: Tomcat did not shut down gracefully."
			else
				logMsgToConfigSysLog "INFO" "INFO: Done shutting down tomcat."
			fi

			logMsgToConfigSysLog "INFO" "INFO: Starting up tomcat."
			sudo $LOGGLY_CATALINA_HOME/bin/startup.sh
			if [ $? -ne 0 ]; then
				logMsgToConfigSysLog "WARNING" "WARNING: Tomcat did not start up down gracefully."
			else
				logMsgToConfigSysLog "INFO" "INFO: Tomcat is up and running."
			fi
		fi
	fi
}

#display usage syntax
usage()
{
cat << EOF
usage: ltomcatsetup [-a loggly auth account or subdomain] [-t loggly token] [-u username] [-p password (optional)] [-ch catalina home (optional)]
usage: ltomcatsetup [-r to rollback] [-ch catalina home (optional)]
usage: ltomcatsetup [-h for help]
EOF
}

##########  Get Inputs from User - Start  ##########

if [ $# -eq 0 ]; then
    usage
	exit
else
while [ "$1" != "" ]; do
    case $1 in
     -ch | --catalinahome ) shift
         LOGGLY_CATALINA_HOME=$1
         echo "CATALINA HOME from input: $LOGGLY_CATALINA_HOME"
         ;;
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
    configureLogglyForTomcat
elif [ "$LOGGLY_ROLLBACK" != "" ]; then
    rollback
else
	usage
fi

##########  Get Inputs from User - End  ##########