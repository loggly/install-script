#!/bin/bash

#This script needs to be run as a sudo user
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root"
   exit 1
fi

SCRIPT_NAME="ltomcatsetup.sh"
SCRIPT_VERSION="1.0"
CONFIG_SYSLOG_TOKEN="b886e45a-b2f9-4019-8ffb-accc0a68e114"
MIN_TOMCAT_VERSION="6.0.33.0"
MIN_SYSLOG_VERSION="5.8.0"

# executing the script for loggly to get the install and configure syslog.
setVariables()
{
#These are common variables and will be used across various functions
SERVICE=tomcat6
SYSLOG_ETCDIR_CONF=/etc/rsyslog.d
LOGGLY_SYSLOG_CONFFILE=$SYSLOG_ETCDIR_CONF/22-loggly.conf
TOMCAT_SYSLOGCONF_FILE=$SYSLOG_ETCDIR_CONF/21-tomcat.conf

SYSLOG_DIR=/var/spool/rsyslog

LINUX_DIST=$(lsb_release -ds)
if [ $? -ne 0 ]; then
	logMsgToConfigSysLog "ERROR" "ERROR: This operating system is not supported by the script"
	exit 1
else
	#remove double quotes (if any) from the linux distribution name
	LINUX_DIST="${LINUX_DIST%\"}"
	LINUX_DIST="${LINUX_DIST#\"}"
	case "$LINUX_DIST" in
		*"Ubuntu"* )
		echo "INFO: Operating system is Ubuntu"
		;;
		*"Red Hat"* )
		echo "INFO: Operating system is Red Hat"
		;;
		*"CentOS"* )
		echo "INFO: Operating system is CentOS"
		;;
		* )
		logMsgToConfigSysLog "ERROR" "ERROR: This operating system is not supported by the script"
		exit 1
		;;
	esac
fi

#get CATALINA_HOME
getCatalinaHome $SERVICE

LOGGLY_CATALINA_CONF_HOME=$LOGGLY_CATALINA_HOME/conf
LOGGLY_CATALINA_PROPFILE=$LOGGLY_CATALINA_CONF_HOME/logging.properties
LOGGLY_CATALINA_BACKUP_PROPFILE=$LOGGLY_CATALINA_PROPFILE.loggly.bk

LOGGLY_CATALINA_LOG_HOME=/var/log/$SERVICE

#identify tomcat version
CATALINA_JAR_PATH=$LOGGLY_CATALINA_HOME/lib/catalina.jar
#check if the identified CATALINA_HOME has the catalina.jar
if [ ! -f "$CATALINA_JAR_PATH" ]; then
	#if not, search it throughout the system. If we find no entries or more than
	#1 entry, then we cannot determine the version of the tomcat
	echo "INFO: Could not find catalina.jar in $LOGGLY_CATALINA_HOME/lib. Searching at other locations, this may take some time..."
	if [ $(sudo find / -name catalina.jar | grep tomcat6 | wc -l) = 1 ]; then
			CATALINA_JAR_PATH=$(sudo find / -name catalina.jar | grep tomcat6)
			echo "INFO: Found catalina.jar at $CATALINA_JAR_PATH"
	else
		logMsgToConfigSysLog "WARNING" "WARNING: Unable to determine the correct version of tomcat. Assuming its >= to 6.0.33"
	fi
fi

if [ -f "$CATALINA_JAR_PATH" ]; then
	TOMCAT_VERSION=$(sudo java -cp $CATALINA_JAR_PATH org.apache.catalina.util.ServerInfo | grep "Server number")
	TOMCAT_VERSION=${TOMCAT_VERSION#*: }
	TOMCAT_VERSION=$TOMCAT_VERSION | tr -d ' '
fi

HOST_NAME=$(hostname)
CONFIG_SYSLOG_TOKEN="1ec4e8e1-fbb2-47e7-929b-75a1bff5ffe0"
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
	echo "INFO: CATALINA HOME: $LOGGLY_CATALINA_HOME"
}

checkIfValidCatalinaHome()
{
	LOGGLY_CATALINA_HOME=$1
	#check if logging.properties files  is present
	if [ ! -f "$LOGGLY_CATALINA_HOME/conf/logging.properties" ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Unable to find conf/logging.properties file within $LOGGLY_CATALINA_HOME. Please provide correct Catalina Home using -ch option"
		exit 1
	#check if tomcat is configured as a service. If no, then check if we have access to catalina.sh file
	elif [ ! -f /etc/init.d/$SERVICE ]; then
		logMsgToConfigSysLog "INFO" "INFO: Tomcat is not configured as a service"
		if [ ! -f "$LOGGLY_CATALINA_HOME/bin/startup.sh" ]; then
			logMsgToConfigSysLog "ERROR" "ERROR: Unable to find bin/startup.sh file within $LOGGLY_CATALINA_HOME. Please provide correct Catalina Home using -ch option"
			exit 1
		fi
	fi
}

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

checkLogglyServersAccessiblilty()
{
echo "Checking if https://www.loggly.com is reachable"
if [ $(curl -s --head  --request GET https://www.loggly.com | grep "200 OK" | wc -l) == 1 ]; then
	echo "INFO: https://www.loggly.com is reachable"
else
	logMsgToConfigSysLog "WARNING" "WARNING: https://www.loggly.com is not reachable. Please check your network and firewall settings. Continuing to configure Loggly on your system..."
fi

echo "Checking if https://$LOGGLY_ACCOUNT.loggly.com is reachable"
if [ $(curl -s --head  --request GET https://$LOGGLY_ACCOUNT.loggly.com/login | grep "200 OK" | wc -l) == 1 ]; then
	echo "INFO: https://$LOGGLY_ACCOUNT.loggly.com reachable"
else
	logMsgToConfigSysLog "WARNING" "WARNING: https://$LOGGLY_ACCOUNT.loggly.com is not reachable. Please check your network and firewall settings. Continuing to configure Loggly on your system..."
fi

echo "Checking if logs-01.loggly.com is reachable"
if [ $(ping -c 1 logs-01.loggly.com | grep "1 packets transmitted, 1 received, 0% packet loss" | wc -l) == 1 ]; then
	echo "INFO: logs-01.loggly.com is reachable"
else
	logMsgToConfigSysLog "WARNING" "WARNING: logs-01.loggly.com is not reachable. Please check your network and firewall settings. Continuing to configure Loggly on your system..."
fi
if [ $(curl -s -u $LOGGLY_USERNAME:$LOGGLY_PASSWORD https://$LOGGLY_ACCOUNT.loggly.com/apiv2/customer | grep "Unauthorized" | wc -l) == 1 ]; then
	logMsgToConfigSysLog "ERROR" "ERROR: Invalid Loggly username or password"
	exit 1
fi

}

configureLoggly()
{
setVariables
logMsgToConfigSysLog "INFO" "INFO: Initiating Configure Loggly"
checkLogglyServersAccessiblilty

INITIAL_MSGSEARCH_COUNT=0
FINAL_MSGSEARCH_COUNT=0

echo "INFO: Tomcat logging properties file: $LOGGLY_CATALINA_PROPFILE"

sudo service rsyslog start
SYSLOG_VERSION=$(sudo rsyslogd -version | grep "rsyslogd")
SYSLOG_VERSION=${SYSLOG_VERSION#* }
SYSLOG_VERSION=${SYSLOG_VERSION%,*}
SYSLOG_VERSION=$SYSLOG_VERSION | tr -d " "
if [ $(compareVersions $SYSLOG_VERSION $MIN_SYSLOG_VERSION 3) -lt 0 ]; then
	logMsgToConfigSysLog "ERROR" "ERROR: Min syslog version required is 5.8.0"
	exit 1
fi

# if the loggly configuration file exist, then don't create it.
echo "INFO: Checking if loggly sysconf file $LOGGLY_SYSLOG_CONFFILE exist"
if [ -f "$LOGGLY_SYSLOG_CONFFILE" ]; then
    echo "INFO: Loggly syslog file $LOGGLY_SYSLOG_CONFILE exist, not creating file"
else
    if [ "$LOGGLY_ACCOUNT" != "" ]; then
        wget -q -O - https://www.loggly.com/install/configure-syslog.py | sudo python - setup --auth $LOGGLY_AUTH_TOKEN --account $LOGGLY_ACCOUNT
    else
		logMsgToConfigSysLog "ERROR" "ERROR: Loggly auth token is required to configure rsyslog. Please pass -a <auth token> while running script"
		exit 1
    fi
fi

# backup the logging properties file just in case it need to reverted.
echo "INFO: Going to back up the properties file: $LOGGLY_CATALINA_PROPFILE to $LOGGLY_CATALINA_BACKUP_PROPFILE"
if [ ! -f $LOGGLY_CATALINA_PROPFILE ]; then
	logMsgToConfigSysLog "ERROR" "ERROR: logging.properties file not found!. Looked at location $LOGGLY_CATALINA_PROPFILE"
	exit 1
else
	# dont take a backup of logging properties file if it is already there
	if [ ! -f $LOGGLY_CATALINA_BACKUP_PROPFILE ]; then
		sudo cp -f $LOGGLY_CATALINA_PROPFILE $LOGGLY_CATALINA_BACKUP_PROPFILE
	fi
fi


# This might not be needed.
#wget -q -O - https://www.loggly.com/install/configure-syslog.py | sudo  python - setup

#Log rotation is not supported on version below 6.0.33.0
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
#if [ $(fgrep rotatable "$LOGGLY_CATALINA_PROPFILE" | wc -l) < 4 ]; then
#echo "Rotable configuration doesn't exist on the properites file. Adding it..."
#cat << ROTATABLE >> "$LOGGLY_CATALINA_PROPFILEA"
#1catalina.org.apache.juli.FileHandler.rotatable = false
#2localhost.org.apache.juli.FileHandler.rotatable = false
#3manager.org.apache.juli.FileHandler.rotatable = false
#4host-manager.org.apache.juli.FileHandler.rotatable = false
#ROTATABLE
#fi

#restartTomcat

# Create rsyslog dir if doesn't exist, Modify the rsyslog directory if exist
if [ -d "$SYSLOG_DIR" ]; then
    echo "$SYSLOG_DIR exist, not creating dir"
    if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
		echo "INFO: Changing the permission on the rsyslog in /var/spool"
		sudo chown -R syslog:adm $SYSLOG_DIR
	fi
else
    echo "INFO: Creating dir $SYSLOGDIR..."
    sudo mkdir -v $SYSLOG_DIR
	 if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
		sudo chown -R syslog:adm $SYSLOG_DIR
	fi
fi

if [ -f "$TOMCAT_SYSLOGCONF_FILE" ]; then
    echo "INFO: $TOMCAT_SYSLOGCONF_FILE exist, not creating file"
else
   echo "INFO: Creating file $TOMCAT_SYSLOGCONF_FILE"
   sudo touch $TOMCAT_SYSLOGCONF_FILE
   sudo chmod o+w $TOMCAT_SYSLOGCONF_FILE
   generateTomcat21File
fi

tomcatinitialLogCount=0
tomcatLatestLogCount=0
queryParam="tag%3Atomcat&from=-15m&until=now&size=1"
searchAndFetch tomcatinitialLogCount "$queryParam"
# restart the syslog service.
restartsyslog
echo "INFO: Restarting tomcat to generate logs for verification..."
restartTomcat
searchAndFetch tomcatLatestLogCount "$queryParam"

counter=1
maxCounter=10
echo "latest tomcat log count: $tomcatLatestLogCount and before query count: $tomcatinitialLogCount"
while [ "$tomcatLatestLogCount" -le "$tomcatinitialLogCount" ]; do
	echo "######### waiting for 30 secs......"
	sleep 30
	echo "######## Done waiting. verifying again..."
	echo "Try # $counter of total $maxCounter"
	searchAndFetch tomcatLatestLogCount "$queryParam"
	echo "Again Fetch: initial count $tomcatinitialLogCount : latest count : $tomcatLatestLogCount  counter: $counter  max counter: $maxCounter"
	let counter=$counter+1
	if [ "$counter" -gt "$maxCounter" ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Tomcat logs did not make to Loggly in stipulated time. Please check your token & network/firewall settings and retry"
		exit 1
	fi
done

if [ "$tomcatLatestLogCount" -gt "$tomcatinitialLogCount" ]; then
	logMsgToConfigSysLog "SUCCESS" "SUCCESS: Tomcat Log successfully transferred to Loggly"
	exit 0
fi
}
# End of configure rsyslog for tomcat

generateTomcat21File()
{

imfileStr="\$ModLoad imfile
\$WorkDirectory $SYSLOG_DIR
"
 if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
imfileStr+="\$PrivDropToGroup adm
\$WorkDirectory $SYSLOG_DIR
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
else
logMsgToConfigSysLog "INFO" "INFO: Tomcat version is less than 6.0.33. Log rotation cannot be disabled for version <6.0.33; only catalina.out log will be monitored"
fi

#change the tomcat-21 file to variable from above and also take the directory of the tomcat log file.
sudo cat << EOIPFW >> $TOMCAT_SYSLOGCONF_FILE
$imfileStr
EOIPFW
}

rollback()
{
	setVariables
	logMsgToConfigSysLog "INFO" "INFO: Initiating rollback"
	echo "INFO: Reverting the catalina file ...."
	if [ -f "$LOGGLY_CATALINA_BACKUP_PROPFILE" ]; then
		sudo rm -fr $LOGGLY_CATALINA_PROPFILE
		sudo cp -f $LOGGLY_CATALINA_BACKUP_PROPFILE $LOGGLY_CATALINA_PROPFILE
		sudo rm -fr $LOGGLY_CATALINA_BACKUP_PROPFILE
	fi
	echo "INFO: Deleting the loggly tomcat syslog conf file ...."
	if [ -f "$TOMCAT_SYSLOGCONF_FILE" ]; then
		sudo rm -rf "$TOMCAT_SYSLOGCONF_FILE"
	fi
	echo "INFO: Removed all the modified files"
	restartTomcat
	logMsgToConfigSysLog "INFO" "INFO: Rollback completed"
}

debug()
{
	setVariables
	logMsgToConfigSysLog "INFO" "INFO: Initiating debug"
	checkLogglyServersAccessiblilty
	
    #if [ -f loggly_tcpdump.log ]; then
    #    sudo rm -rf loggly_tcpdump.log
    #fi

    # Get the inital count for the msg.
    queryParam="syslog.appName:LOGGLYVERIFY&from=-15m&until=now&size=1"
	#set -x
    searchAndFetch initialCount "$queryParam"
	#set +x
    echo "Count of the msg before logging: $initialCount"

    #sudo sh -c "tcpdump  -i eth0 -A \"tcp and port 514\" -s 0 -w loggly_tcpdump.log" &


    logger -t "LOGGLYVERIFY" "LOGGLYDEBUG- Test msg for verification from script"
    #msg="<14>0 test test [$LOGGLY_AUTH_TOKEN@41058 tag=\"Test\"] test from Loggly verify script"
    #echo "test msg: $msg"
    #echo "$msg" | nc -vv -q2 logs-01.loggly.com 514

    #sleep 1
    #sudo killall tcpdump
    #echo "Reading the capture packets!!"
	#TODO not sure why -r doesn't work.
	# sudo tcpdump -r loggly_tcpdump.log
	#Hack using grep and strings
	# result="$(strings loggly_tcpdump.log | grep "LOGGLYDEBUG" | wc -l)"
    #echo "result is $result"
    #if [ "$result" -eq 0 ]; then
    #   echo "Failed to send data to logs-01.loggly.com on 514. Please check your rsyslog config or tomcat config file"
    # else
    #    echo "Succefully send data to loggly!!!"
    #fi

    # schedule the search
    searchAndFetch finalCount $queryParam
    counter=1
    maxCounter=10
    echo "initial count $initialCount : final count : $finalCount  counter: $counter  max counter: $maxCounter"
    while [ "$finalCount" -le "$initialCount" ]; do
		echo "initial count $initialCount : final count : $finalCount  counter: $counter  max counter: $maxCounter"
		echo "######### waiting for 30 secs......"
		sleep 30
		echo "######## Done waiting. verifying again..."
		echo "Try # $counter of total 10"
		searchAndFetch finalCount "$queryParam"
		echo "Again Fetch: initial count $initialCount : final count : $finalCount  counter: $counter  max counter: $maxCounter"
		let counter=$counter+1
		if [ "$counter" -gt "$maxCounter" ]; then
			logMsgToConfigSysLog "ERROR" "ERROR: Tomcat logs did not make to Loggly in stipulated time. Please check your token & network/firewall settings and retry"
			exit 1
		fi
    done
    if [ "$finalCount" -gt "$initialCount" ]; then
	logMsgToConfigSysLog "SUCCESS" "SUCCESS: Tomcat Log successfully transferred to Loggly"
	exit 0
    fi
}


#$1 return the count of records in loggly, $2 is the query param to search in loggly
searchAndFetch()
{
    searchquery="$2"
    echo "Search query is $searchquery"
	#url="http://$LOGGLY_ACCOUNT.loggly.com/apiv2/search?q=syslog.appName:LOGGLYVERIFY&from=-5m&until=now&size=1"
    url="http://$LOGGLY_ACCOUNT.loggly.com/apiv2/search?q=$searchquery"
    echo "search url: $url"
    result=$(wget -qO- /dev/stdout --user "$LOGGLY_USERNAME" --password "$LOGGLY_PASSWORD" "$url")
    #echo "Result of wget invoke $result"
    if [ -z "$result" ]; then
		logMsgToConfigSysLog "ERROR" "ERROR: Please check your network/firewall settings & ensure Loggly subdomain, username and password is specified correctly"
		exit 1
    fi
    id=$(echo "$result" | grep -v "{" | grep id | awk '{print $2}')
    # strip last double quote from id
    id="${id%\"}"
    # strip first double quote from id
    id="${id#\"}"
    echo "rsid for the search is: $id"
    url="http://$LOGGLY_ACCOUNT.loggly.com/apiv2/events?rsid=$id"

    # retrieve the data
    result=$(wget -qO- /dev/stdout --user "$LOGGLY_USERNAME" --password "$LOGGLY_PASSWORD" "$url")
	#echo "actual result based on rsid: $result"
    count=$(echo "$result" | grep total_events | awk '{print $2}')
    count="${count%\,}"
    eval $1="'$count'"
    echo "count of event from loggly: "$count""
    #$1=$count;
    if [ "$count" > 0 ]; then
        timestamp=$(echo "$result" | grep timestamp)
		#echo "timestamp: "$timestamp""
        echo "Data made successfully to loggly!!!"
    fi
}

usage()
{
cat << EOF
 usage: ltomcatsetup [-a loggly auth account or subdomain] [-t loggly token] [-u username] [-p password (optional)] [-ch catalina home (optional)]
 usage: ltomcatsetup [-r to rollback] [-ch catalina home (optional)]
 usage: ltomcatsetup [-h for help]
EOF
}


restartsyslog()
{
	echo "Restarting the rsyslog service..."
	sudo service rsyslog restart
	if [ $? -ne 0 ]; then
		logMsgToConfigSysLog "WARNING" "WARNING: rsyslog did not restart gracefully. Please restart rsyslog manually"
	fi
}

restartTomcat()
{
	#sudo service tomcat restart or home/bin/start.sh
	if [ $(ps -ef | grep -v grep | grep "$SERVICE" | wc -l) > 0 ]; then
		echo "INFO: $SERVICE is running..."
		if [ -f /etc/init.d/$SERVICE ]; then
			echo "INFO: $SERVICE is running as service"
			sudo service $SERVICE restart
			if [ $? -ne 0 ]; then
				logMsgToConfigSysLog "WARNING" "WARNING: Tomcat did not restart gracefully. Log rotation may not be disabled. Please restart tomcat manually"
			fi
		else
			echo "INFO: $SERVICE is not running as service..."
			# To be commented only for test
			echo "INFO: Shutting down tomcat..."
			sudo $LOGGLY_CATALINA_HOME/bin/shutdown.sh
			if [ $? -ne 0 ]; then
				logMsgToConfigSysLog "WARNING" "WARNING: Tomcat did not shut down gracefully"
			else
				echo "INFO: Done shutting down tomcat!"
			fi
			
			echo "INFO: Starting up tomcat..."
			sudo $LOGGLY_CATALINA_HOME/bin/startup.sh
			if [ $? -ne 0 ]; then
				logMsgToConfigSysLog "WARNING" "WARNING: Tomcat did not start up down gracefully"
			else
				echo "INFO: Tomcat is up and running"
			fi
		fi
	fi
}

logMsgToConfigSysLog()
{
	#$1 variable will be SUCCESS or ERROR or INFO
	#$2 variable will be the message
	echo "$2"
	CURRENT_TIME=$(date)

	var="{\"sub-domain\":\"$LOGGLY_ACCOUNT\", \"host-name\":\"$HOST_NAME\", \"script-name\":\"$SCRIPT_NAME\", \"script-version\":\"$SCRIPT_VERSION\", \"status\":\"$1\", \"time-stamp\":\"$CURRENT_TIME\", \"linux-distribution\":\"$LINUX_DIST\", \"tomcat-version\":\"$TOMCAT_VERSION\", \"messages\":\"$2\"}"

	curl -s -H "content-type:application/json" -d "$var" https://logs-01.loggly.com/inputs/$CONFIG_SYSLOG_TOKEN
	echo
}

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

LOGGLY_ACCOUNT=""
LOGGLY_CATALINA_HOME=""
LOGGLY_AUTH_TOKEN=""
LOGGLY_DEBUG=""
LOGGLY_ROLLBACK=""
LOGGLY_USERNAME=
LOGGLY_PASSWORD=
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
      #-d | --debug )
      #    LOGGLY_DEBUG="true"
      #    ;;
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
    configureLoggly
elif [ "$LOGGLY_ROLLBACK" != "" ]; then
    rollback
else
	usage
fi
