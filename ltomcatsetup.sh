#!/bin/bash 
# executing the script for loggly to get the install and configure syslog.
configureLoggly() {
SERVICE=tomcat
LOGGLY_CATALINA_CONF_HOME=$LOGGLY_CATALINA_HOME/conf
LOGGLY_CATALINA_PROPFILE=$LOGGLY_CATALINA_CONF_HOME/logging.properties
LOGGLY_CATALINA_BACKUP_PROPFILE=$LOGGLY_CATALINA_PROPFILE.bk
SYSLOG_DIR=/var/spool/rsyslog
SYSLOG_ETCDIR_CONF=/etc/rsyslog.d
LOGGLY_SYSLOG_CONFFILE=$SYSLOG_ETCDIR_CONF/22-loggly.conf
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

sed -i -e 's/rotatable\ =\ true/rotatable\ =\ false/g' $LOGGLY_CATALINA_BACKUP_PROPFILE 

restartTomcat

# Create rsyslog dir if doesn't exist, Modify the rsyslog directory if exsit
if [ -d "$SYSLOG_DIR" ]; then
    echo "$SYSLOG_DIR exist, Not creating dir"
    echo "Changing the permission on the rsyslog in /var/spool"
    sudo chown -R syslog:adm /var/spool/rsyslog
else 
    echo "creating dir $SYSLOGDIR..."
    sudo mkdir -v /var/spool/rsyslog
    sudo chown -R syslog:adm /var/spool/rsyslog
fi

TOMCAT_SYSLOGCONF_FILE=/etc/rsyslog.d/21-tomcat.conf

if [ -f "$TOMCAT_SYSLOGCONF_FILE" ]; then
    echo "$TOMCAT_SYSLOGCONF_FILE exist, Not creating file"
else
   echo " Creating file $TOMCAT_SYSLOGCONF_FILE" 
   sudo touch $TOMCAT_SYSLOGCONF_FILE
   sudo chmod o+w $TOMCAT_SYSLOGCONF_FILE
fi

#change the tomcat-21 file to variable from above and also take the directory of the tomcat log file.
sudo cat << EOIPFW >> /etc/rsyslog.d/21-tomcat.conf 
\$ModLoad imfile
\$WorkDirectory /var/spool/rsyslog
\$PrivDropToGroup adm
\$WorkDirectory /var/spool/rsyslog

#parameterized token here.......
#Add a tag for tomcat events
\$template LogglyFormatTomcat,"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$LOGGLY_AUTH_TOKEN@41058 tag=\"tomcat\"] %msg%\n"
# catalina.log
\$InputFileName /var/log/tomcat6/catalina.log
\$InputFileTag catalina-log
\$InputFileStateFile stat-catalina-log
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'catalina-log' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'catalina-log' then ~

# catalina.out
\$InputFileName /var/log/tomcat6/catalina.out
\$InputFileTag catalina-out
\$InputFileStateFile stat-catalina-out
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'catalina-out' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'catalina-out' then ~

# host-manager.log
\$InputFileName /var/log/tomcat6/host-manager.log
\$InputFileTag host-manager
\$InputFileStateFile stat-host-manager
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'host-manager' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'host-manager' then ~

# initd.log
\$InputFileName /var/log/tomcat6/initd.log
\$InputFileTag initd
\$InputFileStateFile stat-initd
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'initd' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'initd' then ~

# localhost.log
\$InputFileName /var/log/tomcat6/localhost.log
\$InputFileTag localhost-log
\$InputFileStateFile stat-localhost-log
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'localhost-log' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'localhost-log' then ~

# manager.log
\$InputFileName /var/log/tomcat6/manager.log
\$InputFileTag manager
\$InputFileStateFile stat-manager
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'manager' then @@logs-01.loggly.com:514;LogglyFormatTomcat
    if \$programname == 'manager' then ~
EOIPFW
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
   echo "######## Done waiting. verfiying again..."
   echo "Try # $counter of total 10"
   searchAndFetch tomcatLatestLogCount "$queryParam" 
   echo "Again Fetch: initial count $tomcatinitialLogCount : latest count : $tomcatLatestLogCount  counter: $counter  max counter: $maxCounter"
   let counter=$counter+1
done

if [ "$tomcatLatestLogCount" -gt "$tomcatinitialCount" ]; then
echo "####### Tomcat Log succesfully transferred to Loggly ###########"
fi


}
# End of configure rsyslog for tomcat

rollback() {
 echo "Reverting the catalina file ...."
 if [ -f "$LOGGLY_CATALINA_BACKUP_PROPFILE" ]; then
    cp -f $LOGGLY_CATALINA_BACKUP_PROPFILE $LOGGLY_CATALINA_PROPFILE 
 fi
 echo "Deleting the loggly tomcat syslog conf file ...."
 if [ -f "$TOMCAT_SYSLOGCONF_FILE" ]; then
    sudo rm -rf "$TOMCAT_SYSLOGCONF_FILE"
 fi
 echo "Removed all the needed files"
 restartTomcat
}
debug() {

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
      echo "######## Done waiting. verfiying again..."
      echo "Try # $counter of total 10"
      searchAndFetch finalCount "$queryParam"
      echo "Again Fetch: initial count $initialCount : final count : $finalCount  counter: $counter  max counter: $maxCounter"
      let counter=$counter+1
    done
    if [ "$finalCount" -gt "$initialCount" ]; then
	echo "####### Log succesfully transferred to Loggly ###########"
    fi

}


#$1 return the count of records in loggly, $2 is the query param to search in loggly
searchAndFetch() {
    searchquery="$2"
    echo "Search query is $searchquery"
#    url="http://$LOGGLY_ACCOUNT.loggly.com/apiv2/search?q=syslog.appName:LOGGLYVERIFY&from=-5m&until=now&size=1"
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
#    echo "actual result based on rsid: $result"
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
 usage: ltomcat [-ch catalina home] [-d to debug] [-a loggly auth account or subdomain] [-t loggly token] [-u username] [-p password] [-h help]
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
  if [ -f /etc/init.d/tomcat ]; then
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
          shift
          ;;
       -r | --rollback )
          echo "Reverting configuration for sending tomcat logs to Logggly"
          rollback
          exit
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

if [ "$LOGGLY_CATALINA_HOME" != ""  -a  "$LOGGLY_AUTH_TOKEN" != "" ]; then
    configureLoggly
elif [ "$LOGGLY_DEBUG" != ""  -a  "$LOGGLY_AUTH_TOKEN" != "" -a "$LOGGLY_ACCOUNT" != "" ]; then
    debug
else 
    usage
fi
