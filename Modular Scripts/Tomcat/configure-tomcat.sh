#!/bin/bash

#downloads configure-linux.sh
echo "INFO: Downloading dependencies - configure-linux.sh"
curl -s -o configure-linux.sh https://www.loggly.com/install/configure-linux.sh
source configure-linux.sh "being-invoked"

##########  Variable Declarations - Start  ##########
#name of the current script
SCRIPT_NAME=configure-tomcat.sh
#version of the current script
SCRIPT_VERSION=1.6

#minimum version of tomcat to enable log rotation
MIN_TOMCAT_VERSION=6.0.33.0

#we have not found the tomcat version yet at this point in the script
APP_TAG="\"tomcat-version\":\"\""

#name of the service, in this case tomcat6
SERVICE=tomcat6
#name and location of tomcat syslog file
TOMCAT_SYSLOG_CONFFILE=$RSYSLOG_ETCDIR_CONF/21-tomcat.conf
#name and location of tomcat syslog backup file
TOMCAT_SYSLOG_CONFFILE_BACKUP=$RSYSLOG_ETCDIR_CONF/21-tomcat.conf.loggly.bk

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

#tomcat as tag sent with the logs
LOGGLY_FILE_TAG="tomcat"

#add tags to the logs
TAG=

TLS_SENDING="true"

#this variable will hold the catalina home provide by user.
#this is not a mandatory input
LOGGLY_CATALINA_HOME=

MANUAL_CONFIG_INSTRUCTION="Manual instructions to configure Tomcat is available at https://www.loggly.com/docs/tomcat-application-server/. Rsyslog troubleshooting instructions are available at https://www.loggly.com/docs/troubleshooting-rsyslog/"

#this variable will hold if the check env function for linux is invoked
TOMCAT_ENV_VALIDATED=
##########  Variable Declarations - End  ##########

#check if Tomcat environment is compatible for Loggly
checkTomcatLogglyCompatibility() {
  #check if the linux environment is compatible for Loggly
  checkLinuxLogglyCompatibility

  #deduce CATALINA_HOME, this sets the value for LOGGLY_CATALINA_HOME variable
  deduceAndCheckTomcatHomeAndVersion

  #check if tomcat is configured with log4j. If yes, then exit
  checkIfTomcatConfiguredWithLog4J

  TOMCAT_ENV_VALIDATED="true"
}

# executing the script for loggly to install and configure syslog.
installLogglyConfForTomcat() {
  #log message indicating starting of Loggly configuration
  logMsgToConfigSysLog "INFO" "INFO: Initiating Configure Loggly for Tomcat."

  #check if tomcat environment is compatible with Loggly
  if [ "$TOMCAT_ENV_VALIDATED" = "" ]; then
    checkTomcatLogglyCompatibility
  fi

  #ask user if tomcat can be restarted
  canTomcatBeRestarted

  #configure loggly for Linux
  installLogglyConf

  #backing up the logging.properties file
  backupLoggingPropertiesFile

  #update logging.properties file for log rotation
  updateLoggingPropertiesFile

  #update server.xml to add renameOnRotate
  updateServerXML

  #multiple tags
  addTagsInConfiguration

  #create 21tomcat.conf file
  write21TomcatConfFile

  #verify if the tomcat logs made it to loggly
  checkIfTomcatLogsMadeToLoggly

  #log success message
  logMsgToConfigSysLog "SUCCESS" "SUCCESS: Tomcat successfully configured to send logs via Loggly."
}

#executing script to remove loggly configuration for tomcat
removeLogglyConfForTomcat() {
  logMsgToConfigSysLog "INFO" "INFO: Initiating rollback."

  #check if the user has root permission to run this script
  checkIfUserHasRootPrivileges

  #check if the OS is supported by the script. If no, then exit
  checkIfSupportedOS

  #deduce CATALINA_HOME, this sets the value for LOGGLY_CATALINA_HOME variable
  deduceAndCheckTomcatHomeAndVersion

  #ask user if tomcat can be restarted
  canTomcatBeRestarted

  #remove 21tomcat.conf file
  remove21TomcatConfFile

  #restore original server.xml from backup
  restoreServerXML

  #restore original loggly properties file from backup
  restoreLogglyPropertiesFile

  logMsgToConfigSysLog "INFO" "INFO: Rollback completed."
}

#identify if tomcat6/ tomcat7/ tomcat8 is installed on your system
deduceAndCheckTomcatHomeAndVersion() {

  if [ "$LOGGLY_CATALINA_HOME" = "" ]; then
    LOGGLY_CATALINA_HOME=

    #lets check if tomcat7 is installed on the system
    SERVICE=tomcat7

    #try to deduce tomcat home considering tomcat7
    assumeTomcatHome $SERVICE

    #initialize validTomcatHome variable with value true. This value will be toggled
    #in the function checkIfValidTomcatHome fails
    validTomcatHome="true"

    #checks if the deduced tomcat7 home is correct or not
    checkIfValidTomcatHome validTomcatHome

    #if tomcat7 home is not valid one, move on to check for tomcat6
    if [ "$validTomcatHome" = "false" ]; then

      LOGGLY_CATALINA_HOME=

      #lets check if tomcat6 is installed on the system
      SERVICE=tomcat6

      #try to deduce tomcat home considering tomcat6
      assumeTomcatHome $SERVICE

      #initialize validTomcatHome variable with value true. This value will be toggled
      #in the function checkIfValidTomcatHome fails
      validTomcatHome="true"

      #checks if the deduced tomcat7 home is correct or not
      checkIfValidTomcatHome validTomcatHome
    fi

    #if tomcat6 home is not valid one, move on to check for tomcat8
    if [ "$validTomcatHome" = "false" ]; then

      LOGGLY_CATALINA_HOME=

      #lets check if tomcat6 is installed on the system
      SERVICE=tomcat8

      #try to deduce tomcat home considering tomcat6
      assumeTomcatHome $SERVICE

      #initialize validTomcatHome variable with value true. This value will be toggled
      #in the function checkIfValidTomcatHome fails
      validTomcatHome="true"

      #checks if the deduced tomcat7 home is correct or not
      checkIfValidTomcatHome validTomcatHome
    fi

    if [ "$validTomcatHome" = "true" ]; then
      logMsgToConfigSysLog "INFO" "INFO: CATALINA HOME: $LOGGLY_CATALINA_HOME"

      #set all the required tomcat variables by this script
      setTomcatVariables

      #find tomcat version
      getTomcatVersion

      #check if tomcat version is supported by the script. The script only support tomcat 6 and 7
      checkIfSupportedTomcatVersion
    else
      logMsgToConfigSysLog "ERROR" "ERROR: Unable to determine correct CATALINA_HOME. Please provide correct Catalina Home using -ch option."
    fi
  else
    #if the user has provided catalina_home, then we need to check if it is a valid catalina home and what is the correct version of the tomcat.
    #Let us assume service name is tomcat for now, which will be updated later.
    SERVICE=tomcat

    #set the flag to true
    validTomcatHome="true"

    #check if the tomcat home provided by user is valid
    checkIfValidTomcatHome validTomcatHome

    if [ "$validTomcatHome" = "true" ]; then
      logMsgToConfigSysLog "INFO" "INFO: CATALINA HOME: $LOGGLY_CATALINA_HOME"

      #set tomcat variables
      setTomcatVariables

      #find tomcat version
      getTomcatVersion

      #check if tomcat version is supported by the script. The script only support tomcat 6 and 7
      checkIfSupportedTomcatVersion

      #update the service name
      if [ "$tomcatMajorVersion" = "7" ]; then
        SERVICE=tomcat7
      elif [ "$tomcatMajorVersion" = "6" ]; then
        SERVICE=tomcat6
      elif [ "$tomcatMajorVersion" = "8" ]; then
        SERVICE=tomcat8
      fi
    else
      logMsgToConfigSysLog "ERROR" "ERROR: Provided Catalina Home is not correct. Please recheck."
    fi
  fi
}

#Get default location of tomcat home on various supported OS if user has not provided one
assumeTomcatHome() {
  #if user has not provided the catalina home
  if [ "$LOGGLY_CATALINA_HOME" = "" ]; then
    LINUX_DIST_IN_LOWER_CASE=$(echo $LINUX_DIST | tr "[:upper:]" "[:lower:]")
    case "$LINUX_DIST_IN_LOWER_CASE" in
    *"ubuntu"*)
      LOGGLY_CATALINA_HOME="/var/lib/$1"
      ;;
    *"redhat"*)
      LOGGLY_CATALINA_HOME="/usr/share/$1"
      ;;
    *"centos"*)
      LOGGLY_CATALINA_HOME="/usr/share/$1"
      ;;
    *"amazon"*)
      LOGGLY_CATALINA_HOME="/usr/share/$1"
      ;;
    esac
  fi
}

#checks if the catalina home is a valid one by searching for logging.properties and
#checks for startup.sh if tomcat is not configured as service
checkIfValidTomcatHome()
{
  #check if logging.properties files  is present
  if [ ! -f "$LOGGLY_CATALINA_HOME/conf/logging.properties" ]; then
    logMsgToConfigSysLog "WARN" "WARN: Unable to find conf/logging.properties file within $LOGGLY_CATALINA_HOME."
    eval $1="false"
  #check if tomcat is configured as a service. If no, then check if we have access to startup.sh file
  elif [ ! -f /etc/init.d/$SERVICE ]; then
    if [[ ! $(which systemctl) && $(systemctl list-unit-files $SERVICE.service | grep "$SERVICE.service") ]] &>/dev/null; then
      logMsgToConfigSysLog "INFO" "INFO: Tomcat is not configured as a service."
      if [ ! -f "$LOGGLY_CATALINA_HOME/bin/startup.sh" ]; then
        logMsgToConfigSysLog "WARN" "WARN: Unable to find bin/startup.sh file within $LOGGLY_CATALINA_HOME."
        eval $1="false"
      fi
    fi
  fi
}

#sets tomcat variables which will be used across various functions
setTomcatVariables() {
  #set value for catalina conf home path, logging.properties path and
  #logging.properties.loggly.bk path
  LOGGLY_CATALINA_CONF_HOME=$LOGGLY_CATALINA_HOME/conf
  LOGGLY_CATALINA_PROPFILE=$LOGGLY_CATALINA_CONF_HOME/logging.properties
  LOGGLY_CATALINA_BACKUP_PROPFILE=$LOGGLY_CATALINA_PROPFILE.loggly.bk

  LOGGLY_CATALINA_LOG_HOME=/var/log/$SERVICE

  #if tomcat is not installed as service, then tomcat logs will be created at would be $CATALINA_HOME/log
  if [ ! -f "$LOGGLY_CATALINA_LOG_HOME" ]; then
    LOGGLY_CATALINA_LOG_HOME=$LOGGLY_CATALINA_HOME/logs
  fi

  #default path for catalina.jar
  CATALINA_JAR_PATH=$LOGGLY_CATALINA_HOME/lib/catalina.jar
}

#get the version of tomcat
getTomcatVersion() {
  #check if the identified CATALINA_HOME has the catalina.jar
  if [ ! -f "$CATALINA_JAR_PATH" ]; then
    #if not, search it throughout the system. If we find no entries or more than
    #1 entry, then we cannot determine the version of the tomcat
    logMsgToConfigSysLog "INFO" "INFO: Could not find catalina.jar in $LOGGLY_CATALINA_HOME/lib. Searching at other locations, this may take some time."
    if [ $(sudo find / -name catalina.jar | grep $SERVICE | wc -l) = 1 ]; then
      CATALINA_JAR_PATH=$(sudo find / -name catalina.jar | grep $SERVICE)
      logMsgToConfigSysLog "INFO" "INFO: Found catalina.jar at $CATALINA_JAR_PATH"
    else
      logMsgToConfigSysLog "WARNING" "WARNING: Unable to determine the correct version of tomcat 6. Assuming its >= to 6.0.33."
      TOMCAT_VERSION=6.0.33.0
    fi
  fi

  #get the tomcat version number
  if [ -f "$CATALINA_JAR_PATH" ]; then
    TOMCAT_VERSION=$(sudo java -cp $CATALINA_JAR_PATH org.apache.catalina.util.ServerInfo | grep "Server number")
    TOMCAT_VERSION=${TOMCAT_VERSION#*: }
    TOMCAT_VERSION=$TOMCAT_VERSION | tr -d ' '
    APP_TAG="\"tomcat-version\":\"$TOMCAT_VERSION\""
  fi
}

#checks if the tomcat version is supported by this script, currently the script
#only supports tomcat 6 and tomcat 7
checkIfSupportedTomcatVersion() {
  tomcatMajorVersion=${TOMCAT_VERSION%%.*}
  if [[ ($tomcatMajorVersion -ne 6) && ($tomcatMajorVersion -ne 7) && ($tomcatMajorVersion -ne 8) ]]; then
    logMsgToConfigSysLog "ERROR" "ERROR: This script only supports Tomcat version 6, 7 or 8."
    exit 1
  fi
}

#checks if the tomcat is already configured with log4j. If yes, then exit
checkIfTomcatConfiguredWithLog4J() {
  echo "INFO: Checking if tomcat is configured with log4j logger."
  #default path for log4j files
  LOG4J_FILE_PATH=$LOGGLY_CATALINA_HOME/lib/log4j*
  #check if the log4j files are present, if yes, then exit
  if ls $LOG4J_FILE_PATH >/dev/null 2>&1; then
    logMsgToConfigSysLog "ERROR" "ERROR: Script does not support log4j logger. Please see $LOGGLY_COM_URL/docs/java-log4j"
    exit 1
  else
    #if not found in the default path, check in the path where catalina.jar is found
    libDirName=$(dirname ${CATALINA_JAR_PATH})
    LOG4J_FILE_PATH=$libDirName/log4j*
    if ls $LOG4J_FILE_PATH >/dev/null 2>&1; then
      logMsgToConfigSysLog "ERROR" "ERROR: Script does not support log4j logger. Please see $LOGGLY_COM_URL/docs/java-log4j"
      exit 1
    fi
  fi
  logMsgToConfigSysLog "INFO" "INFO: Tomcat seems not to be configured with log4j logger."
}

canTomcatBeRestarted() {
  if [ "$SUPPRESS_PROMPT" == "false" ]; then
    while true; do
      read -p "Tomcat needs to be restarted during configuration. Do you wish to continue? (yes/no)" yn
      case $yn in
      [Yy]*)
        break
        ;;
      [Nn]*)
        logMsgToConfigSysLog "WARN" "WARN: This script must restart Tomcat. Please run the script again when you are ready to restart it. No changes have been made to your system. Exiting."
        exit 1
        break
        ;;
      *) echo "Please answer yes or no." ;;
      esac
    done
  else
    logMsgToConfigSysLog "WARN" "WARN:Tomcat needs to be restarted during configuration."
  fi
}
#backup the logging.properties file in the CATALINA_HOME folder
backupLoggingPropertiesFile() {
  logMsgToConfigSysLog "INFO" "INFO: Tomcat logging properties file: $LOGGLY_CATALINA_PROPFILE"
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

}

#update logging.properties file to enable log rotation. If the version of tomcat
#is less than 6.0.33, then log rotation cannot be enabled
updateLoggingPropertiesFile() {
  #check if tomcat version is less than 6.0.33.0, if yes, throw a warning
  if [ $(compareVersions $TOMCAT_VERSION $MIN_TOMCAT_VERSION 4) -lt 0 ]; then
    logMsgToConfigSysLog "WARNING" "WARNING: Tomcat version is less than 6.0.33. Log rotation cannot be disabled for version <6.0.33; only catalina.out log will be monitored."
  fi

  #Log rotation is not supported on version below 6.0.33.0, logging.properties should not be modified
  #in such case. If version is above 6.0.33.0, then do the following
  if [ $(compareVersions $TOMCAT_VERSION $MIN_TOMCAT_VERSION 4) -ge 0 ]; then
    #removing the end . from logging.properties variable 1catalina.org.apache.juli.FileHandler.prefix = catalina.
    if grep -Fq "prefix = catalina." $LOGGLY_CATALINA_PROPFILE; then
      sudo sed -i "s/prefix = catalina./prefix = catalina/g" $LOGGLY_CATALINA_PROPFILE
    fi
    if grep -Fq "prefix = localhost." $LOGGLY_CATALINA_PROPFILE; then
      sudo sed -i "s/prefix = localhost./prefix = localhost/g" $LOGGLY_CATALINA_PROPFILE
    fi
    if grep -Fq "prefix = manager." $LOGGLY_CATALINA_PROPFILE; then
      sudo sed -i "s/prefix = manager./prefix = manager/g" $LOGGLY_CATALINA_PROPFILE
    fi
    if grep -Fq "prefix = host-manager." $LOGGLY_CATALINA_PROPFILE; then
      sudo sed -i "s/prefix = host-manager./prefix = host-manager/g" $LOGGLY_CATALINA_PROPFILE
    fi

    #Check if the rotatable property is present in logging.properties
    if grep -Fq "rotatable" $LOGGLY_CATALINA_PROPFILE; then
      #If present, set all the values to false
      sed -i -e 's/rotatable = true/rotatable = false/g' $LOGGLY_CATALINA_PROPFILE
    fi

    if [ $(fgrep "rotatable = false" "$LOGGLY_CATALINA_PROPFILE" | wc -l) -lt 4 ]; then
      #If rotatable property present or not, add the following lines to disable rotation in any case
      sudo cat <<EOIPFW >>$LOGGLY_CATALINA_PROPFILE
1catalina.org.apache.juli.FileHandler.rotatable = false
2localhost.org.apache.juli.FileHandler.rotatable = false
3manager.org.apache.juli.FileHandler.rotatable = false
4host-manager.org.apache.juli.FileHandler.rotatable = false
EOIPFW
    fi
  fi
}

#add renameOnRotate to true in the Valve element to stop access logs
#log rotation
updateServerXML() {

  if ! grep -q 'renameOnRotate="true"' "$LOGGLY_CATALINA_HOME/conf/server.xml"; then

    #Creating backup of server.xml to server.xml.bk
    logMsgToConfigSysLog "INFO" "INFO: Creating backup of server.xml to server.xml.bk"
    sudo cp $LOGGLY_CATALINA_HOME/conf/server.xml $LOGGLY_CATALINA_HOME/conf/server.xml.bk
    if grep -q '"localhost_access_log."' "$LOGGLY_CATALINA_HOME/conf/server.xml"; then
      sed -i 's/"localhost_access_log."/"localhost_access_log"/g' $LOGGLY_CATALINA_HOME/conf/server.xml
    fi
    sed -i 's/"localhost_access_log"/"localhost_access_log"\ renameOnRotate="true"/g' $LOGGLY_CATALINA_HOME/conf/server.xml
    logMsgToConfigSysLog "INFO" "INFO: Disabled log rotation for localhost_access_log file in server.xml"
  fi
}
addTagsInConfiguration() {
  #split tags by comman(,)
  IFS=, read -a array <<<"$LOGGLY_FILE_TAG"
  for i in "${array[@]}"; do
    TAG="$TAG tag=\\\"$i\\\" "
  done
}

write21TomcatConfFile() {
  #Create tomcat syslog config file if it doesn't exist
  echo "INFO: Checking if tomcat sysconf file $TOMCAT_SYSLOG_CONFFILE exist."
  if [ -f "$TOMCAT_SYSLOG_CONFFILE" ]; then
    logMsgToConfigSysLog "WARN" "WARN: Tomcat syslog file $TOMCAT_SYSLOG_CONFFILE already exist."
    if [ "$SUPPRESS_PROMPT" == "false" ]; then
      while true; do
        read -p "Do you wish to override $TOMCAT_SYSLOG_CONFFILE? (yes/no)" yn
        case $yn in
        [Yy]*)
          logMsgToConfigSysLog "INFO" "INFO: Going to back up the conf file: $TOMCAT_SYSLOG_CONFFILE to $TOMCAT_SYSLOG_CONFFILE_BACKUP"
          sudo mv -f $TOMCAT_SYSLOG_CONFFILE $TOMCAT_SYSLOG_CONFFILE_BACKUP
          write21TomcatFileContents
          break
          ;;
        [Nn]*) break ;;
        *) echo "Please answer yes or no." ;;
        esac
      done
    else
      logMsgToConfigSysLog "INFO" "INFO: Going to back up the conf file: $TOMCAT_SYSLOG_CONFFILE to $TOMCAT_SYSLOG_CONFFILE_BACKUP"
      sudo mv -f $TOMCAT_SYSLOG_CONFFILE $TOMCAT_SYSLOG_CONFFILE_BACKUP
      write21TomcatFileContents
    fi
  else
    write21TomcatFileContents
  fi
}

#function to write the contents of tomcat syslog config file
write21TomcatFileContents() {
  logMsgToConfigSysLog "INFO" "INFO: Creating file $TOMCAT_SYSLOG_CONFFILE"
  sudo touch $TOMCAT_SYSLOG_CONFFILE
  sudo chmod o+w $TOMCAT_SYSLOG_CONFFILE

  commonContent="
  \$ModLoad imfile
  \$WorkDirectory $RSYSLOG_DIR
  "
  if [[ "$LINUX_DIST" == *"Ubuntu"* ]]; then
    commonContent+="\$PrivDropToGroup adm		
    "
  fi

    imfileStr=$commonContent"

\$ActionSendStreamDriver gtls
\$ActionSendStreamDriverMode 1
\$ActionSendStreamDriverAuthMode x509/name
\$ActionSendStreamDriverPermittedPeer *.loggly.com

#RsyslogGnuTLS
\$DefaultNetstreamDriverCAFile $CA_FILE_PATH

#parameterized token here.......
#Add a tag for tomcat events
\$template LogglyFormatTomcat,\"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$LOGGLY_AUTH_TOKEN@41058 $TAG] %msg%\n\"

# catalina.out
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/catalina.out
\$InputFileTag catalina-out
\$InputFileStateFile stat-catalina-out
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'catalina-out' then @@logs-01.loggly.com:6514;LogglyFormatTomcat
if \$programname == 'catalina-out' then ~

# initd.log
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/initd.log
\$InputFileTag initd
\$InputFileStateFile stat-initd
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'initd' then @@logs-01.loggly.com:6514;LogglyFormatTomcat
if \$programname == 'initd' then ~
"

  #if log rotation is enabled i.e. tomcat version is greater than or equal to
  #6.0.33.0, then add the following lines to tomcat syslog conf file
  if [ $(compareVersions $TOMCAT_VERSION $MIN_TOMCAT_VERSION 4) -ge 0 ]; then
  imfileStr+=$commonContent"
# catalina.log
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/catalina.log
\$InputFileTag catalina-log
\$InputFileStateFile stat-catalina-log
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'catalina-log' then @@logs-01.loggly.com:6514;LogglyFormatTomcat
if \$programname == 'catalina-log' then ~

# host-manager.log
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/host-manager.log
\$InputFileTag host-manager
\$InputFileStateFile stat-host-manager
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'host-manager' then @@logs-01.loggly.com:6514;LogglyFormatTomcat
if \$programname == 'host-manager' then ~

# localhost.log
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/localhost.log
\$InputFileTag localhost-log
\$InputFileStateFile stat-localhost-log
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'localhost-log' then @@logs-01.loggly.com:6514;LogglyFormatTomcat
if \$programname == 'localhost-log' then ~

# manager.log
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/manager.log
\$InputFileTag manager
\$InputFileStateFile stat-manager
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'manager' then @@logs-01.loggly.com:6514;LogglyFormatTomcat
if \$programname == 'manager' then ~

# localhost_access_log.txt 
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/localhost_access_log.txt
\$InputFileTag tomcat-access
\$InputFileStateFile stat-tomcat-access
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'tomcat-access' then @@logs-01.loggly.com:6514;LogglyFormatTomcat
if \$programname == 'tomcat-access' then ~
"
  fi

  imfileStrNonTls=$commonContent"

#parameterized token here.......
#Add a tag for tomcat events
\$template LogglyFormatTomcat,\"<%pri%>%protocol-version% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %msgid% [$LOGGLY_AUTH_TOKEN@41058 $TAG] %msg%\n\"

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
  imfileStrNonTls+=$commonContent"
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

# localhost_access_log.txt 
\$InputFileName $LOGGLY_CATALINA_LOG_HOME/localhost_access_log.txt
\$InputFileTag tomcat-access
\$InputFileStateFile stat-tomcat-access
\$InputFileSeverity info
\$InputFilePersistStateInterval 20000
\$InputRunFileMonitor
if \$programname == 'tomcat-access' then @@logs-01.loggly.com:514;LogglyFormatTomcat
if \$programname == 'tomcat-access' then ~
"
  fi

  if [ $TLS_SENDING == "false" ];
  then
    imfileStr=$imfileStrNonTls
  fi

  #change the tomcat-21 file to variable from above and also take the directory of the tomcat log file.
  sudo cat <<EOIPFW >>$TOMCAT_SYSLOG_CONFFILE
$imfileStr
EOIPFW

  #restart the syslog service.
  restartRsyslog
}

#checks if the tomcat logs made to loggly
checkIfTomcatLogsMadeToLoggly() {
  counter=1
  maxCounter=10

  tomcatInitialLogCount=0
  tomcatLatestLogCount=0
  queryParam="tag%3Atomcat&from=-15m&until=now&size=1"

  queryUrl="$LOGGLY_ACCOUNT_URL/apiv2/search?q=$queryParam"
  logMsgToConfigSysLog "INFO" "INFO: Search URL: $queryUrl"

  logMsgToConfigSysLog "INFO" "INFO: Getting initial tomcat log count."
  #get the initial count of tomcat logs for past 15 minutes
  searchAndFetch tomcatInitialLogCount "$queryUrl"

  logMsgToConfigSysLog "INFO" "INFO: Tomcat needs to be restarted to complete the configuration and verification."
  # restart the tomcat service.
  restartTomcat

  logMsgToConfigSysLog "INFO" "INFO: Verifying if the tomcat logs made it to Loggly."
  logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
  #get the final count of tomcat logs for past 15 minutes
  searchAndFetch tomcatLatestLogCount "$queryUrl"
  let counter=$counter+1

  while [ "$tomcatLatestLogCount" -le "$tomcatInitialLogCount" ]; do
    echo "INFO: Did not find the test log message in Loggly's search yet. Waiting for 30 secs."
    sleep 30
    echo "INFO: Done waiting. Verifying again."
    logMsgToConfigSysLog "INFO" "INFO: Verification # $counter of total $maxCounter."
    searchAndFetch tomcatLatestLogCount "$queryUrl"
    let counter=$counter+1
    if [ "$counter" -gt "$maxCounter" ]; then
      logMsgToConfigSysLog "ERROR" "ERROR: Tomcat logs did not make to Loggly in time. Please check network and firewall settings and retry."
      exit 1
    fi
  done

  if [ "$tomcatLatestLogCount" -gt "$tomcatInitialLogCount" ]; then
    logMsgToConfigSysLog "SUCCESS" "SUCCESS: Tomcat logs successfully transferred to Loggly! You are now sending Tomcat logs to Loggly."
    exit 0
  fi
}

#restore original loggly properties file from backup
restoreLogglyPropertiesFile() {
  echo "INFO: Reverting the logging.properties file."
  if [ -f "$LOGGLY_CATALINA_BACKUP_PROPFILE" ]; then
    sudo rm -fr $LOGGLY_CATALINA_PROPFILE
    sudo cp -f $LOGGLY_CATALINA_BACKUP_PROPFILE $LOGGLY_CATALINA_PROPFILE
    sudo rm -fr $LOGGLY_CATALINA_BACKUP_PROPFILE
  fi

  logMsgToConfigSysLog "INFO" "INFO: Tomcat needs to be restarted to rollback the configuration."
  restartTomcat
}

restoreServerXML() {
  if [ -f "$LOGGLY_CATALINA_HOME/conf/server.xml.bk" ]; then
    logMsgToConfigSysLog "INFO" "INFO: Restoring server.xml file from backup"
    sudo rm -rf $LOGGLY_CATALINA_HOME/conf/server.xml
    sudo cp $LOGGLY_CATALINA_HOME/conf/server.xml.bk $LOGGLY_CATALINA_HOME/conf/server.xml
    sudo rm -rf $LOGGLY_CATALINA_HOME/conf/server.xml.bk
  fi
}

#remove 21tomcat.conf file
remove21TomcatConfFile() {
  echo "INFO: Deleting the loggly tomcat syslog conf file."
  if [ -f "$TOMCAT_SYSLOG_CONFFILE" ]; then
    sudo rm -rf "$TOMCAT_SYSLOG_CONFFILE"
  fi

  #restart rsyslog
  restartRsyslog
}

#restart tomcat
restartTomcat() {
  #sudo service tomcat restart or home/bin/start.sh
  if [ $(ps -ef | grep -v grep | grep "$SERVICE" | wc -l) -gt 0 ]; then
    logMsgToConfigSysLog "INFO" "INFO: $SERVICE is running."
    if [ -f /etc/init.d/$SERVICE ]; then
      logMsgToConfigSysLog "INFO" "INFO: $SERVICE is running as service."
      logMsgToConfigSysLog "INFO" "INFO: Restarting the tomcat service."
      sudo service $SERVICE restart
      if [ $? -ne 0 ]; then
        logMsgToConfigSysLog "WARNING" "WARNING: Tomcat did not restart gracefully. Log rotation may not be disabled. Please restart tomcat manually."
      fi
    else
      logMsgToConfigSysLog "INFO" "INFO: $SERVICE is not running as service."
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
usage() {
  cat <<EOF
usage: configure-tomcat [-a loggly auth account or subdomain] [-t loggly token (optional)] [-u username] [-p password (optional)] [-ch catalina home (optional)] [-tag filetag1,filetag2 (optional)]  [-s suppress prompts {optional)]
usage: configure-tomcat [-r to rollback] [-a loggly auth account or subdomain] [-ch catalina home (optional)]
usage: configure-tomcat [-h for help]
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
    -tag | --filetag ) shift
    LOGGLY_FILE_TAG=$1
    echo "File tag: $LOGGLY_FILE_TAG"
    ;;
      -r | --rollback )
    LOGGLY_ROLLBACK="true"
          ;;
      -s | --suppress )
    SUPPRESS_PROMPT="true"
    ;;
           --insecure )
    LOGGLY_TLS_SENDING="false"
    TLS_SENDING="false"
    LOGGLY_SYSLOG_PORT=514
      ;;
      -h | --help)
          usage
          exit
          ;;
    esac
    shift
  done
fi

if [ "$LOGGLY_DEBUG" != "" -a "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" ]; then
  if [ "$LOGGLY_PASSWORD" = "" ]; then
    getPassword
  fi
  debug
elif [ "$LOGGLY_ACCOUNT" != "" -a "$LOGGLY_USERNAME" != "" ]; then
  if [ "$LOGGLY_PASSWORD" = "" ]; then
    getPassword
  fi
  installLogglyConfForTomcat
elif [ "$LOGGLY_ROLLBACK" != "" -a "$LOGGLY_ACCOUNT" != "" ]; then
  removeLogglyConfForTomcat
else
  usage
fi

##########  Get Inputs from User - End  ##########
