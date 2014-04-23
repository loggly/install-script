#!/bin/bash 
# executing the script for loggly to get the install and configure syslog.

setVariables(){
#These are common variables and will be used across various functions
SERVICE=tomcat6
SYSLOG_ETCDIR_CONF=/etc/rsyslog.d
LOGGLY_SYSLOG_CONFFILE=$SYSLOG_ETCDIR_CONF/22-loggly.conf
TOMCAT_SYSLOGCONF_FILE=$SYSLOG_ETCDIR_CONF/21-tomcat.conf

SYSLOG_DIR=/var/spool/rsyslog

LOGGLY_CATALINA_CONF_HOME=$LOGGLY_CATALINA_HOME/conf
LOGGLY_CATALINA_PROPFILE=$LOGGLY_CATALINA_CONF_HOME/logging.properties
LOGGLY_CATALINA_BACKUP_PROPFILE=$LOGGLY_CATALINA_PROPFILE.loggly.bk

LOGGLY_CATALINA_LOG_HOME=/var/log/$SERVICE
}

configureLoggly() {
setVariables
INITIAL_MSGSEARCH_COUNT=0
FINAL_MSGSEARCH_COUNT=0

echo "Tomcat HOME: $LOGGLY_CATALINA_HOME"
echo "Tomcat logging properties file:  $LOGGLY_CATALINA_PROPFILE"

# if the loggly configuration file exist, then don't create it.
echo "checking if loggly sysconf file $LOGGLY_SYSLOG_CONFFILE exist"
if [ -f "$LOGGLY_SYSLOG_CONFFILE" ]; then
    echo "Loggly syslog file $LOGGLY_SYSLOG_CONFILE exist, not creating file" 
else 
    if [ "$LOGGLY_ACCOUNT" != "" ]; then
        wget -q -O - https://www.loggly.com/install/configure-syslog.py | sudo python - setup --auth $LOGGLY_AUTH_TOKEN --account $LOGGLY_ACCOUNT   
    else 
        echo "ERROR: Loggly auth token is required to configure rsyslog. Please pass -a <auth token> while running script"
    fi 
fi 
	
# backup the logging properties file just in case it need to reverted.
echo "Backing up the properties file: $LOGGLY_CATALINA_PROPFILE to $LOGGLY_CATALINA_BACKUP_PROPFILE"
cp -f $LOGGLY_CATALINA_PROPFILE $LOGGLY_CATALINA_BACKUP_PROPFILE

# This might not be needed.
#wget -q -O - https://www.loggly.com/install/configure-syslog.py | sudo  python - setup

#On RHEL 6.4, 'yum install tomcat' installs tomcat v6.0.24. This version does not support disabling of log rotation
if [ "$(lsb_release -ds | grep  'Red Hat Enterprise Linux Server release 6.4')" = "" ]; then
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
#If rotatable property present or not, add the following lines to disable rotation in any case
sudo cat << EOIPFW >> $LOGGLY_CATALINA_PROPFILE 
1catalina.org.apache.juli.FileHandler.rotatable = false
2localhost.org.apache.juli.FileHandler.rotatable = false
3manager.org.apache.juli.FileHandler.rotatable = false
4host-manager.org.apache.juli.FileHandler.rotatable = false
EOIPFW

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

restartTomcat

# Create rsyslog dir if doesn't exist, Modify the rsyslog directory if exsit
if [ -d "$SYSLOG_DIR" ]; then
    echo "$SYSLOG_DIR exist, Not creating dir"
    echo "Changing the permission on the rsyslog in /var/spool"
	if [ "$(lsb_release -ds | grep Ubuntu)" != "" ]; then
		sudo chown -R syslog:adm $SYSLOG_DIR
	fi
else 
    echo "creating dir $SYSLOGDIR..."
    sudo mkdir -v $SYSLOG_DIR
	if [ "$(lsb_release -ds | grep Ubuntu)" != "" ]; then
		sudo chown -R syslog:adm $SYSLOG_DIR
	fi
fi

if [ -f "$TOMCAT_SYSLOGCONF_FILE" ]; then
    echo "$TOMCAT_SYSLOGCONF_FILE exist, Not creating file"
else
   echo " Creating file $TOMCAT_SYSLOGCONF_FILE" 
   sudo touch $TOMCAT_SYSLOGCONF_FILE
   sudo chmod o+w $TOMCAT_SYSLOGCONF_FILE
   generateTomcat21File
fi

tomcatinitialLogCount=0
tomcatLatestLogCount=0
queryParam="&from=-15m&until=now&size=1"
searchAndFetch tomcatinitialLogCount "$queryParam"
# restart the syslog service.
restartsyslog
echo "restarting tomcat one more time..."
restartTomcat
searchAndFetch tomcatLatestLogCount "$queryParam"

counter=1
maxCounter=10
echo "latest tomcat log count: $tomcatLatestLogCount and before query count: $tomcatinitialLogCount"
while [ "$tomcatLatestLogCount" -le "$tomcatinitialLogCount" ]; do 
   echo "######### waiting for 30 secs......"
   sleep 30
   echo "######## Done waiting. verifying again..."
   echo "Try # $counter of total 10"
   searchAndFetch tomcatLatestLogCount "$queryParam" 
   echo "Again Fetch: initial count $tomcatinitialLogCount : latest count : $tomcatLatestLogCount  counter: $counter  max counter: $maxCounter"
   let counter=$counter+1
   if [ "$counter" -gt "$maxCounter" ]; then
	echo "####### Tomcat logs did not make to Loggly in stipulated time. Please retry ###########"
	break;
   fi
done

if [ "$tomcatLatestLogCount" -gt "$tomcatinitialLogCount" ]; then
echo "####### Tomcat Log successfully transferred to Loggly ###########"
fi

}
# End of configure rsyslog for tomcat

generateTomcat21File() {

imfileStr="\$ModLoad imfile
\$WorkDirectory $SYSLOG_DIR
"
if [ "$(lsb_release -ds | grep Ubuntu)" != "" ]; then
imfileStr+="\$PrivDropToGroup adm
\$WorkDirectory $SYSLOG_DIR"
fi



#change the tomcat-21 file to variable from above and also take the directory of the tomcat log file.
sudo cat << EOIPFW >> $TOMCAT_SYSLOGCONF_FILE 
$imfileStr

#parameterized token here.......
#Add a tag for tomcat events
\$template LogglyFormatTomcat,"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$LOGGLY_AUTH_TOKEN@41058 tag=\"tomcat\"] %msg%\n"
# catalina.log
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/catalina.log
\$InputFileTag catalina-log
\$InputFileStateFile stat-catalina-log
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'catalina-log' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'catalina-log' then ~

# catalina.out
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/catalina.out
\$InputFileTag catalina-out
\$InputFileStateFile stat-catalina-out
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'catalina-out' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'catalina-out' then ~

# host-manager.log
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/host-manager.log
\$InputFileTag host-manager
\$InputFileStateFile stat-host-manager
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'host-manager' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'host-manager' then ~

# initd.log
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/initd.log
\$InputFileTag initd
\$InputFileStateFile stat-initd
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'initd' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'initd' then ~

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
EOIPFW
}

rollback() {
	setVariables
	echo "Reverting the catalina file ...."
	if [ -f "$LOGGLY_CATALINA_BACKUP_PROPFILE" ]; then
		sudo rm -fr $LOGGLY_CATALINA_PROPFILE
		cp -f $LOGGLY_CATALINA_BACKUP_PROPFILE $LOGGLY_CATALINA_PROPFILE
		sudo rm -fr $LOGGLY_CATALINA_BACKUP_PROPFILE
	fi
	echo "Deleting the loggly tomcat syslog conf file ...."
	if [ -f "$TOMCAT_SYSLOGCONF_FILE" ]; then
		sudo rm -rf "$TOMCAT_SYSLOGCONF_FILE"
	fi
	echo "Removed all the needed files"
	restartTomcat
}
debug() {
	setVariables
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
		echo "####### Tomcat logs did not make to Loggly in stipulated time. Please retry ###########"
		break;
	  fi
    done
    if [ "$finalCount" -gt "$initialCount" ]; then
	echo "####### Log successfully transferred to Loggly ###########"
    fi
}


#$1 return the count of records in loggly, $2 is the query param to search in loggly
searchAndFetch() {
    searchquery="$2"
    echo "Search query is $searchquery"
	#url="http://$LOGGLY_ACCOUNT.loggly.com/apiv2/search?q=syslog.appName:LOGGLYVERIFY&from=-5m&until=now&size=1"
    url="http://$LOGGLY_ACCOUNT.loggly.com/apiv2/search?q=$searchquery"
    echo "search url: $url"
    result=$(wget -qO- /dev/stdout --user "$LOGGLY_USERNAME" --password "$LOGGLY_PASSWORD" "$url")
    #echo "Result of wget invoke $result"
    if [ -z "$result" ]; then
       echo "loggly subdomain, username and password need to be specified" 
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
#        echo "timestamp: "$timestamp""
        echo "Data made successfully to loggly!!!"
    fi
}

usage() {
cat << EOF
 usage: ltomcatsetup [-ch catalina home] [-a loggly auth account or subdomain] [-t loggly token] [-u username] [-p password] [-d to debug] [-h help]
 usage: ltomcatsetup [-ch catalina home] [-r to rollback] [-h help]
EOF
}


restartsyslog() {
echo "Restarting the rsyslog service..."
sudo service rsyslog restart
}

restartTomcat() {
#sudo service tomcat restart or home/bin/start.sh
if [ $(ps -ef | grep -v grep | grep "$SERVICE" | wc -l) > 0 ]; then
   echo "$SERVICE is running..."
  if [ -f /etc/init.d/$SERVICE ]; then
    echo "$SERVICE is running as service"
    sudo service $SERVICE restart
  else 
    echo "$SERVICE is not running as service..."
    # To be commented only for test
   echo "shutting down tomcat..."
   $LOGGLY_CATALINA_HOME/bin/shutdown.sh 
   echo "Done shutting down tomcat!"
   echo "starting up tomcat..."
   $LOGGLY_CATALINA_HOME/bin/startup.sh 
   echo "Tomcat is up and running"
  fi
fi
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
      -d | --debug )
          LOGGLY_DEBUG="true"
          echo "Running debug..."          
          ;;
       -r | --rollback )
		  LOGGLY_ROLLBACK="true"
          echo "Reverting configuration for sending tomcat logs to Loggly"          
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

if [ "$LOGGLY_DEBUG" != ""  -a  "$LOGGLY_CATALINA_HOME" != ""  -a  "$LOGGLY_AUTH_TOKEN" != "" -a "$LOGGLY_ACCOUNT" != "" ]; then
    debug
elif [ "$LOGGLY_CATALINA_HOME" != ""  -a  "$LOGGLY_AUTH_TOKEN" != "" -a "$LOGGLY_ACCOUNT" != "" ]; then
    configureLoggly
elif [ "$LOGGLY_ROLLBACK" != ""  -a  "$LOGGLY_CATALINA_HOME" != "" ]; then
    rollback
else 
    usage
fi
