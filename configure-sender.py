import os
from optparse import OptionParser
import platform
import re
import sys
import getpass
from distutils.version import StrictVersion
import time
from datetime import datetime
import tempfile
import urllib2
import json
import uuid

#Constants
OS_UBUNTU = 1
OS_FEDORA = 2
OS_RHEL = 3
OS_CENTOS = 4
OS_UNSUPPORTED = -1

PROD_SYSLOG_NG = 1
PROD_RSYSLOG = 2
PROD_PLAIN_SYSLOG = 3
PROD_UNSUPPORTED = -1

LOGGLY_SYSLOG_SERVER = "collector01.chipper01.loggly.net"
LOGGLY_SYSLOG_PORT = 514
LOGGLY_CONFIG_FILE = "22-loggly.conf"
LOGGLY_ENV_DETAILS_FILE = "env_details.txt"

STR_EXIT_MESSAGE = "\nThis environment (OS) is not supported by the Loggly Syslog Configuration Script.  Please contact support@loggly.com for more information.\n"
STR_NO_SYSLOG_MESSAGE = "\nSupported syslog type/version not found.  Please contact support@loggly.com for more information.\n"
STR_SYSLOG_DAEMON_MESSAGE = "\nSyslog daemon (%s) is not running. Please start %s daemon and try again.\n"

REST_URL_SUBMIT_ENVIRONMENT = "http://testing.fe-app.dev.loggly.net:8000/chopper/account/overview" #"http://httpbin.org/post"
##REST_URL_GET_AUTH_TOKEN = "https://agistar.loggly.com/api/inputs"
REST_URL_GET_AUTH_TOKEN = "http://%s.frontend.chipper01.loggly.net/chopper/api/customer"
REST_URL_GET_SEARCH_ID = "http://%s.frontend.chipper01.loggly.net/chopper/api/search?q=%s&from=-2h&until=now&size=10"
REST_URL_GET_SEARCH_RESULT = "http://%s.frontend.chipper01.loggly.net/chopper/api/events?rsid=%s"
REST_URL_PUSH_INFO = "https://logs.frontend.chipper01.loggly.net/inputs/4f476788-f526-4744-a7c0-ff9b4b215689"

supported_os_environments = {
                                OS_UBUNTU: ["9.04", "9.10", "10.04", "10.10", "11.04", "11.10", "12.04", "12.10", "13.04"],
                                OS_FEDORA: ["11", "12", "13", "14", "15", "16", "17", "18", "19"],
                                OS_RHEL: ["5.2", "5.3", "5.4", "5.5", "5.6", "5.7", "5.8", "5.9", "6.1", "6.2", "6.3", "6.4" ],
                                OS_CENTOS: ["5.2", "5.3", "5.4", "5.5", "5.6", "5.7", "5.8", "5.9", "6.0", "6.1", "6.2", "6.3", "6.4"]
                            }

supported_syslog_versions = {
                                PROD_SYSLOG_NG: ["1.6", "2.0", "2.1", "3.1", "3.2", "3.3", "3.4", "3.5"],
                                PROD_RSYSLOG: ["1.19", "2.0", "3.14", "3.21", "3.22", "4.2", "4.4", "4.6", "5.7", "5.8", "7.2", "7.3"],
                                PROD_PLAIN_SYSLOG: ["1.3", "1.4", "1.5"]
                            }

default_config_file_name = {
                                PROD_SYSLOG_NG: "/etc/syslog-ng/syslog-ng.conf",
                                PROD_RSYSLOG: "/etc/rsyslog.conf",
                                PROD_PLAIN_SYSLOG: "/etc/syslogd.conf"
                            }

syslog_processid_path = {
                                OS_UBUNTU: {
                                    PROD_SYSLOG_NG: "/var/run/syslog-ng.pid",
                                    PROD_RSYSLOG: "/var/run/rsyslogd.pid",
                                    PROD_PLAIN_SYSLOG: "sysklogd"
                                },
                                OS_FEDORA: {
                                    PROD_SYSLOG_NG: "/var/run/syslogd.pid",
                                    PROD_RSYSLOG: "/var/run/syslogd.pid",
                                    PROD_PLAIN_SYSLOG: "sysklogd"
                                },
                                OS_RHEL: {
                                    PROD_SYSLOG_NG: "/var/run/syslog-ng.pid",
                                    PROD_RSYSLOG: "/var/run/syslogd.pid",
                                    PROD_PLAIN_SYSLOG: "/var/run/syslogd.pid"
                                },
                                OS_CENTOS: {
                                    PROD_SYSLOG_NG: "/var/run/syslog-ng.pid",
                                    PROD_RSYSLOG: "/var/run/syslogd.pid",
                                    PROD_PLAIN_SYSLOG: "sysklogd"
                                }
                            }

configuration_text = {
                                PROD_SYSLOG_NG: """#                -------------------------------------------------------
#                 Syslog Logging Directives for Loggly (www.loggly.com)
#                -------------------------------------------------------
%s
destination loghost { tcp("%s" port (%s) template("$ISODATE $HOST [%s@%s] $MSG\\n") template_escape(no)); };
log { source(%s); destination(loghost); };""",
                                
                                PROD_RSYSLOG: """#                -------------------------------------------------------
#                 Syslog Logging Directives for Loggly (www.loggly.com)
#                -------------------------------------------------------
# $template - Define logging format // $template <template_name> <logging_format>
# 
$template LogglyFormat,"%%timegenerated%% %%HOSTNAME%% [%s@%s] %%msg:::drop-last-lf%%\\n"

# Send messages to syslog server listening on TCP port using template

*.*             @@%s:%s;LogglyFormat

#                -------------------------------------------------------
""",
                                PROD_PLAIN_SYSLOG: "/etc/syslogd.conf"
                            }

yes = set(['yes', 'ye', 'y'])
no = set(['no', 'n'])
                
def printLog(message):
    print(message)

def printMessage(message):
    printLog("\n*************************************************************")
    printLog("****** " + message + " Loggly Syslog Configuration Script ******")
    printLog("*************************************************************\n")

def printEnvironment(current_environment):
    printLog("Operating System: %s-%s(%s)" % (current_environment['distro_name'], current_environment['version'], current_environment['id']))
    printLog("Syslog versions:")
    if len(current_environment['syslog_versions']) > 0:
        for index in range(0, len(current_environment['syslog_versions'])):
            printLog("\t%d.   %s(%s)" % (index + 1, current_environment['syslog_versions'][index][0], current_environment['syslog_versions'][index][1]))
    else:
        printLog("\tNo Syslog Version Found......")

def sendEnvironment(current_environment):
    printLog (current_environment)
    printLog ("Sending Environment Details to Loggly Server.")

def usr_input(st):
    get_input = ''
    try:
        get_input = raw_input
    except NameError:
        get_input = input
    
    st = get_input(st)
    return st
    
# Function will return following values.
# -1 : version1 is less than version2
# 0 : version1 equals to version2
# 1 : version1 is greater than version2

def version_compare(version1, version2):
    cmp_ex = lambda x, y: StrictVersion(x).__cmp__(y)
    return cmp_ex(version1, version2)

# Get OS ID for corresponding OS present on machine
def get_os_id(os_name):
    return {
        'ubuntu': OS_UBUNTU, 'fedora': OS_FEDORA, 'red hat enterprise linux server': OS_RHEL, 'centos': OS_CENTOS,
        }.get(os_name.lower(), OS_UNSUPPORTED)

# Get syslog id from installed syslog product
def get_syslog_id(product_name):
    return {
        'syslog-ng': PROD_SYSLOG_NG, 'rsyslog': PROD_RSYSLOG, 'syslogd': PROD_PLAIN_SYSLOG, 'sysklogd': PROD_PLAIN_SYSLOG,
        }.get(product_name.lower(), PROD_UNSUPPORTED)

# Derive which syslog version is installed
def get_syslog_version(distro_id):
    printLog("Reading Installed Syslog Versions....")
    if distro_id == OS_UBUNTU:
        command = "dpkg -l \*sys\*log\* | grep ^ii"
        pattern = 'ii\s+(rsyslog|syslog-ng|sysklogd)\s+(\d+\.\d+)'
    elif distro_id == OS_FEDORA:
        command = "rpm -qa | grep -i 'sys' | grep -i 'log'"
        pattern = '(rsyslog|syslog-ng|sysklogd)-(\d+\.\d+)'
    elif distro_id == OS_RHEL:
        command = "rpm -qa | grep -i 'sys' | grep -i 'log'"
        pattern = '(rsyslog|syslog-ng|sysklogd)-(\d+\.\d+)'
    elif distro_id == OS_CENTOS:
        command = "rpm -qa | grep -i 'sys' | grep -i 'log'"
        pattern = '(rsyslog|syslog-ng|sysklogd)-(\d+\.\d+)'
    else:
        return []

    output = os.popen(command).read()
    compiled_regex = re.compile(pattern, re.MULTILINE | re.IGNORECASE)

    return compiled_regex.findall(output)

# Checks for sudo privileges, if yes returns true
def is_sudo_privilege():
    if os.getuid() == 0:
        return True
    return False

# Get Distro Name, Distro ID, Version and ID.
def get_environment_details():
    printLog("Reading Environment Details....")
    environment = {}
    distribution = platform.linux_distribution()
    environment['distro_name'] = distribution[0]
    environment['distro_id'] = get_os_id(distribution[0])
    environment['version'] = distribution[1]
    environment['id'] = distribution[2]
    environment['syslog_versions'] = get_syslog_version(environment['distro_id'])
    environment['supported_syslog_versions'] = {}
    return environment

# Performing quick check for OS and Syslog
def perform_sanity_check(current_environment):
    printLog("Performing Sanity Check....")
    if (current_environment['distro_id'] == OS_UNSUPPORTED) or (current_environment['version'] not in supported_os_environments.get(current_environment['distro_id'])):
        printLog(STR_EXIT_MESSAGE)
        printMessage("Aborting")
        sys.exit(-1)

    syslog_versions = {}
    for (syslog_type, syslog_version) in current_environment['syslog_versions']:
        syslog_id = get_syslog_id(syslog_type)
        if syslog_version in supported_syslog_versions.get(syslog_id):
            syslog_versions[syslog_type] = syslog_version

    current_environment['supported_syslog_versions'] = syslog_versions

    if(current_environment['supported_syslog_versions'] == None or len(current_environment['supported_syslog_versions']) <= 0):
        printLog(STR_NO_SYSLOG_MESSAGE)
        printMessage("Aborting")
        sys.exit(-1)

    printLog("Sanity Check Passed. Your environment is supported.")

# Checks for syslog daemon status.
def check_syslog_service_status(distro_name, syslog_type):
    if not os.path.exists(syslog_processid_path.get(get_os_id(distro_name)).get(get_syslog_id(syslog_type))):
        printLog(STR_SYSLOG_DAEMON_MESSAGE % (syslog_type, syslog_type))
        printMessage("Aborting")
        sys.exit(-1)

# Checks for multiple syslog daemon installed.          
def product_for_configuration(current_environment):
    user_choice = 0
    
    if len(current_environment['supported_syslog_versions']) > 1:
        printLog("Multiple versions of syslog detected on your system.")
        index = 0
        for (syslog_name, syslog_version) in current_environment['supported_syslog_versions'].iteritems():
            index += 1
            printLog("\t%d. %s(%s)" % (index, syslog_name, syslog_version))
            
        for _ in range(0, 5):
            try:
                sys.stdin = open("/dev/tty") 
                str_msg = "Please select (1-" + str(index) + ") to specify which version of syslog you'd like configured. (Default is 1): "
                user_choice = int(usr_input(str_msg)) - 1
                break
            except ValueError:
                printLog ("Not a valid response. Please retry.")
        if user_choice < 0 or user_choice > (index):
            printLog("Invalid choice entered. Continue with default value.")
            user_choice = 0

    check_syslog_service_status(current_environment['distro_name'], current_environment['supported_syslog_versions'].keys()[user_choice])
    printLog("Configuring %s-%s" % (current_environment['supported_syslog_versions'].keys()[user_choice], current_environment['supported_syslog_versions'].values()[user_choice]))

    return current_environment['supported_syslog_versions'].keys()[user_choice]

# Fetching installed/configured syslog details
def get_installed_syslog_configuration(syslog_id):
    default_directory = ''
    auth_token = ''
    source = ''
    printLog("Reading default configuration directory path from (%s)." % default_config_file_name.get(syslog_id))
    text_file = open(default_config_file_name.get(syslog_id), "r")
    
    if syslog_id == PROD_RSYSLOG:
        include_pattern = "^\s*[^#]\s*IncludeConfig\s+([\S]+/)"
        auth_token_pattern = "^\s*[^#]*\s*template\sLogglyFormat.*([a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}).*"
    elif syslog_id == PROD_SYSLOG_NG:
        include_pattern = "^\s*[^#]\s*Include\s+([\S]+/)"
        source_pattern = "^\s*source\s+([\S]+)\s*"
        auth_token_pattern = "^\s*[^#]*\s*destination\sloghost\s\{\stcp.*([a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}).*\};"
        source_compiled_regex = re.compile(source_pattern, re.MULTILINE | re.IGNORECASE)
    elif syslog_id == PROD_PLAIN_SYSLOG:
        include_pattern = "rpm -qa | grep -i 'sys' | grep -i 'log'"
    else:
        return default_directory

    include_compiled_regex = re.compile(include_pattern, re.MULTILINE | re.IGNORECASE)
    auth_token_compiled_regex = re.compile(auth_token_pattern, re.MULTILINE | re.IGNORECASE)
        
    for line in text_file:
        if len(default_directory) <= 0:
            include_match_grp = include_compiled_regex.match(line.rstrip('\n'))
            if include_match_grp:
                default_directory = include_match_grp.group(1)
                default_directory = default_directory.lstrip('"').rstrip('"')

        if len(auth_token) <= 0:
            auth_token_match_grp = auth_token_compiled_regex.match(line.rstrip('\n'))
            if auth_token_match_grp:
                auth_token = auth_token_match_grp.group(1)

        if len(source) <= 0 and syslog_id == PROD_SYSLOG_NG:
            source_match_grp = source_compiled_regex.match(line)
            if source_match_grp:
                source = source_match_grp.group(1)

    return { "path": default_directory, "token": auth_token, "source": source }

# Function to create/modify configuration file
def write_configuration(syslog_id, authorization_details, user_type):
    printLog("Reading configuration directory path....")
    syslog_configuration_details = get_installed_syslog_configuration(syslog_id)
    
    sys.stdin = open("/dev/tty")
    if len(syslog_configuration_details.get("path")) > 0:
        printLog("The default syslog configuration file location is (%s)." % syslog_configuration_details.get("path"))
        question = "\nThe Loggly Syslog Configuration Script will either create a new configuration file or will add configuration parameters to the existing file (%s). The new configuration file will be located at (%s). The new file won't affect the existing configuration.\n\nDo you want the Loggly Syslog Configuration Script to create a new file? [Yes|No] " % (default_config_file_name.get(syslog_id), os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE))
        for _ in range(0, 5):
            user_input = usr_input(question).lower()
            if len(user_input) > 0:
                if  user_input in yes:
                    create_loggly_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type)
                    return
                elif user_input in no:
                    modify_syslog_config_file(syslog_id, syslog_configuration_details, authorization_details)
                    return
    else:
        modify_syslog_config_file(syslog_id, syslog_configuration_details, authorization_details)
        return

    printLog("\nFailed to read configuration directory path after maximum attempts.\nPlease contact support@loggly.com for more information.\n")
    printMessage("Aborting")
    sys.exit(-1)

# Ask for Loggly credentials
def login():
    
    sys.stdin = open("/dev/tty")
    printLog("Reading Loggly credentials from user....")
    user = usr_input("Loggly Username [%s]: " % getpass.getuser())
    if not user:
        user = getpass.getuser()

    if user:
        pprompt = lambda: (getpass.getpass("Password for %s: " % user))
        password = pprompt()
        for _ in range(0, 2):
            if not password:
                password = pprompt()
            else:
                msg = "Loggly Account Name [%s]:" % user
                subdomain = usr_input(msg).lower()
                if len(subdomain) <= 0 :
                    subdomain = user
                return user, password, subdomain

    printLog("\nLoggly credentials not provided after maximum attempts.")
    printMessage("Aborting")
    sys.exit(-1)
   
# Retrieve Auth Token and Distribution ID from Loggly account
def get_json_data(url, user, password):
    req = urllib2.Request(url)
    req.add_header("Accept", "application/json")
    req.add_header("Content-type", "application/json")
    req.add_header("Authorization", "Basic " + (user + ":" + password).encode("base64").rstrip())
    return json.loads(urllib2.urlopen(req).read())
    
def get_auth_token_and_distribution_id(loggly_user, loggly_password, loggly_subdomain):

    # Create the request object and set some headers
    try:
        if loggly_user and loggly_password:
            url = (REST_URL_GET_AUTH_TOKEN % (loggly_subdomain))
            data = get_json_data(url, loggly_user, loggly_password)
            auth_tokens = data["tokens"]
            user_choice = 0
            if not auth_tokens:
                printLog ("No Customer Tokens were found.")
                sys.exit()

            if len(auth_tokens) > 1:
                printLog("Multiple Customer Tokens received from server.")
                for index in range(0, len(auth_tokens)):
                    printLog("\t%d. %s"%(index + 1, auth_tokens[index]))
                for _ in range(0, 5):
                    try:
                        sys.stdin = open("/dev/tty") 
                        str_msg = "Please select (1-" + str(index + 1) + ") to specify which Customer Token you want to use. (Default is 1): "
                        user_choice = int(usr_input(str_msg)) - 1
                        if user_choice < 0 or user_choice > (index):
                            printLog("Invalid choice entered.")
                            continue
                        break
                    except ValueError:
                        printLog ("Not a valid selection. Please retry.")
                if user_choice < 0 or user_choice > (index):
                    printLog("Invalid choice entered. Continue with default value.")
                    user_choice = 0
            token = auth_tokens[user_choice]
            distribution_id = "41058"
            printLog("\nLoggly will be configured with \"%s\" Customer Token.\n" % token)
            return { "token" : token, "id": distribution_id }
        else:
            printLog("Loggly credentials could not be verified.")
            sys.exit()

    except urllib2.HTTPError:
        e = sys.exc_info()[1]
        printLog ("%s" % e)
        sys.exit(-1)
        
    except urllib2.URLError:
        e = sys.exc_info()[1]
        printLog ("%s" % e)
        sys.exit(-1)
        
    except Exception:
        e = sys.exc_info()[1]
        printLog ("%s" % e)
        sys.exit(-1)

# Creating syslog content for configuring Loggly
def syslog_config_file_content(syslog_id, source, authorization_details):
    content = ""
    
    if syslog_id == PROD_RSYSLOG:
        content = configuration_text.get(syslog_id) % (authorization_details.get("token"), authorization_details.get("id"), LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT)
    elif syslog_id == PROD_SYSLOG_NG:
        printLog("Reading configured source from (%s) file." % default_config_file_name.get(syslog_id))
        configured_source = source
        source_created = ''
       
        if len(configured_source) <= 0:
            # create new source of loggly
            source_created = "source loggly_src {\n\tsystem();\n\tinternal();};"
            configured_source = "loggly_src"

        content = configuration_text.get(syslog_id) % (source_created, LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT, authorization_details.get("token"), authorization_details.get("id"), configured_source)
    elif syslog_id == PROD_PLAIN_SYSLOG:
        content = "rpm -qa | grep -i 'sys' | grep -i 'log'"
    else:
        printLog("Failed to create content for syslog id %s\n" % syslog_id)
        printMessage("Aborting")
        sys.exit(-1)
        
    return content + "\n"

# Create Loggly configuration file
def create_loggly_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type):
    file_path = os.path.join(os.getenv("HOME"), LOGGLY_CONFIG_FILE)
    printLog("Creating configuration file at %s" % file_path)
    content = syslog_config_file_content(syslog_id, syslog_configuration_details.get("source"), authorization_details)
    try:
        config_file =  open(file_path, "w")
        config_file.write(content)
        config_file.close()
        if user_type == 3:
            # print Instructions...
            printLog("Current user does not have sudo privileges. Please copy the loggly configuration file (%s) to the (%s) directory and restart the syslog service." % (file_path, syslog_configuration_details.get("path")))
            printMessage("Finished")
            sys.exit()
        else:
            if os.path.isfile(os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)):
                msg = "Loggly configuration file (%s) is already present. Do you want to overwrite it? [Yes|No]: " % os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE) 
                sys.stdin = open("/dev/tty")
                for _ in range(0, 5):
                    user_input = usr_input(msg).lower()
                    if len(user_input) > 0:
                        if  user_input in yes:
                            os.popen("sudo mv -f %s %s" % (file_path, os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)))
                            return
                        elif user_input in no:
                            return
                        else:
                            printLog("Not a valid input. Please retry.")
            else:
                os.popen("sudo mv -f %s %s" % (file_path, os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)))
                return
            
            printLog("Invalid input received after maximum attempts.")
            printMessage("Aborting")
            sys.exit(-1)
            
    except IOError:
        e = sys.exc_info()[1]
        printLog ("IOError %s" % e)

# Modifying configuration file by adding Loggly configuration text
def modify_syslog_config_file(syslog_id, syslog_configuration_details, authorization_details):

    comment = "\n#Configuration modified by Loggly Syslog Configuration Script (%s)\n#\n" % datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
    content = syslog_config_file_content(syslog_id, syslog_configuration_details.get("source"), authorization_details)
    
    if len(syslog_configuration_details.get("token")) <= 0:
        question = "\nThe Loggly configuration will be appended to (%s) file.\n\nDo you want this installer to modify the configuration file? [Yes|No]: " % default_config_file_name.get(syslog_id)
        for _ in range(0, 5):
            user_input = usr_input(question).lower()
            if len(user_input) > 0:
                if  user_input in yes:
                    backup_file_name = "%s_%s.bak" % (default_config_file_name.get(syslog_id), datetime.now().strftime('%Y-%m-%dT%H:%M:%S'))
                    
                    os.popen("sudo cp -p %s %s" % (default_config_file_name.get(syslog_id), backup_file_name))

                    temp_file = tempfile.NamedTemporaryFile(delete=False)
                    temp_file.write(content)
                    temp_file.close()

                    os.popen("sudo bash -c 'cat %s >> %s' " % (temp_file.name, default_config_file_name.get(syslog_id))).read()
                    os.unlink(temp_file.name)
                    
                    return backup_file_name
                
                elif user_input in no:
                    printLog("\n\nPlease add the following lines to the syslog configuration file (%s).\n\n%s%s" % (default_config_file_name.get(syslog_id), comment, content))
                    printMessage("Finished")
                    sys.exit(0)
    else:
        question = "\nLoggly is already configured with %s Customer Token. Do you want to overwrite it? [Yes|No]: " % syslog_configuration_details.get("token")
        sys.stdin = open("/dev/tty")
        for _ in range(0, 5):
            user_input = usr_input(question).lower()
            if len(user_input) > 0:
                if  user_input in yes:
                    pattern = "s/[a-z0-9]\{8\}\-[a-z0-9]\{4\}\-[a-z0-9]\{4\}\-[a-z0-9]\{4\}\-[a-z0-9]\{12\}/%s/g" % authorization_details.get("token")
                    os.popen("sudo sed -i '%s' %s" % (pattern, default_config_file_name.get(syslog_id)))
                    return
                elif user_input in no:
                    return
                else:
                    printLog("Not a valid input. Please retry.")
        printMessage("Aborting")
        sys.exit(-1)
    
    printLog("Invalid input received after maximum attempts.")
    printMessage("Aborting")
    sys.exit(-1)

# Sending sighup to syslog daemon
def send_sighup_to_syslog(syslog_type, user_type, distro_id):
    if user_type != 3:
        sys.stdin = open("/dev/tty")
        syslog_processid_file = syslog_processid_path.get(distro_id).get(get_syslog_id(syslog_type))
        if os.path.exists(syslog_processid_file):
            question = "Do you want the Loggly Syslog Configuration Script to restart (SIGHUP) the syslog daemon. [Yes|No]: "
            for _ in range(0, 5):
                user_input = usr_input(question).lower()
                if len(user_input) > 0:
                    if  user_input in yes:
                        #output = os.popen("sudo kill -SIGHUP `cat %s`" % syslog_processid_file).read()
                        output = os.popen("sudo /etc/init.d/rsyslog restart").read()
                        printLog("SIGHUP Sent. %s" % (output))
                        return True
                    elif user_input in no:
                        return False
                    else:
                        printLog("Not a valid input. Please retry.")
        else:
            printLog("Syslog daemon (%s) is not running. Configuration file has been modified, please start %s daemon manually." % (syslog_type, syslog_type))

    return False

def doverify(loggly_user, loggly_password, loggly_subdomain, unique_string):
    #get  (search id)
    search_url = REST_URL_GET_SEARCH_ID % (loggly_subdomain, unique_string)
    printLog("Sending search request. %s" % search_url)

    data = get_json_data(search_url, loggly_user, loggly_password)
    rsid = data["rsid"]["id"]

    search_result_url = REST_URL_GET_SEARCH_RESULT % (loggly_user, rsid)
    printLog("Sending search result request. %s" % search_result_url)
    data = get_json_data(search_result_url, loggly_user, loggly_password)
    total_events = data["total_events"]
    return total_events >= 1

    
# Parse command line argument
def parseOptions():
    usage = "usage: %prog -i|--info "
    parser = OptionParser(usage=usage, version="Install Sender")
    parser.add_option("-i", "--info", action="store_true", dest="info", default=False, help="Help!!!")
    (options, args) = parser.parse_args()
    return options

# Write environment information to a file
def write_env_details():
    try:
        file_path = os.path.join(os.getenv("HOME"), LOGGLY_ENV_DETAILS_FILE)
        current_environment = get_environment_details()
        env_file = open(file_path, "w")
        env_file.write(os.popen("uname -a").read())
        env_file.write("Operating System: %s-%s(%s)" % (current_environment['distro_name'], current_environment['version'], current_environment['id']))
        env_file.write("\nSyslog versions:\n")
        if len(current_environment['syslog_versions']) > 0:
            for index in range(0, len(current_environment['syslog_versions'])):
                env_file.write("\t%d.   %s(%s)" % (index + 1, current_environment['syslog_versions'][index][0], current_environment['syslog_versions'][index][1]))
        else:
            env_file.write("\tNo Syslog version Found......")

        env_file.close()
        printLog("Created environment details file at %s, please forward it to support@loggly.com" % file_path)
            
    except:
        e = sys.exc_info()[1]
        printLog ("Error %s" % e)

# Checks for compatible Python version.
def version_compatibility_check(minimum_version):
    sys_version = ".".join(map(str, sys.version_info[:2]))
    if sys_version < minimum_version:
        printLog('Python version check fails: Installed version is ' + sys_version + '. Minimum required version is ' + str(minimum_version))
        return False
    
    printLog('Python version check successful: Installed version is ' + sys_version + '. Minimum required version is ' + str(minimum_version))
    return True

# Script starts here
def main():
    printMessage("Starting")
    
    if not version_compatibility_check('2.6'):
        sys.exit(-1)
        
    if parseOptions().info:
        write_env_details()
        printMessage("Finished")
        sys.exit()
        
    # 1. Determine if it has sudo privileges.
    # user_type, 1: root user, 2: non-root user with sudo privileges, 3: non-root user and no sudo privileges

    user_type = 1
    root_user = is_sudo_privilege()
    if not bool(root_user):
        printLog("Script not started as root. Running sudo.")
        user_type = 2
        # Check if user has sudo privileges.
        dummy_file_name = "/etc/%d-loggly.conf" % int(time.time())
        command = "sudo touch %s" % dummy_file_name
        os.popen(command)

        try:
            config_file = open(dummy_file_name, "r")
            config_file.close()
            command = "sudo rm -f %s" % dummy_file_name
            os.popen(command)
        except IOError:
            e = sys.exc_info()[1]
            printLog ("IOError %s" % e)
            user_type = 3
    
    # 2. Determine the environment in which it was invoked (i.e. which distro, release, and syslog daemon has been deployed)
    current_environment = get_environment_details()
    printEnvironment(current_environment)
    perform_sanity_check(current_environment)
    syslog_name_for_configuration = product_for_configuration(current_environment)  

    # 3. Ask for the customer's Loggly credentials and gather the list of available Customer Tokens on their account.
    # Allow the customer to select which Cust Token they would like to connect to if there is more than one available.

    loggly_user, loggly_password, loggly_subdomain = login()
    
    authorization_details = get_auth_token_and_distribution_id(loggly_user, loggly_password, loggly_subdomain)

    # 4. If possible, determine the location of the syslog.conf file or the syslog.conf.d/ directory.
    # Provide the location as the default and prompt the user for confirmation.
    
    # 5. Create custom configuration file and place it in configuration directory path ($IncludeConfig), default path for rsyslog will be /etc/rsyslog.d/
    #authorization_details = get_auth_token_and_distribution_id()

    write_configuration(get_syslog_id(syslog_name_for_configuration), authorization_details, user_type)    

    # 6. SIGHUP the syslog daemon.
    sighup_status = send_sighup_to_syslog(syslog_name_for_configuration, user_type, current_environment['distro_id'])

    if sighup_status:
        printLog("Sending a test message using logger.")
        unique_string = str(uuid.uuid4()).replace("-","")
        dummy_message = "Testing that your log messages can make it to Loggly! %s" % unique_string
        printLog ("Sending message (%s) to Loggly server (%s)" % (dummy_message, LOGGLY_SYSLOG_SERVER))
        os.popen("sudo logger -p INFO '%s'" % dummy_message).read()
        time.sleep(15)
        # Implement REST APIs to search if dummy message has been sent.
        if doverify(loggly_user, loggly_password, loggly_subdomain, unique_string):
            printLog("******* Congratulations! Loggly is configured successfully.")
        else:
            printLog("!!!!!! Loggly verification failed. Please contact support@loggly.com for more information.")
        
    printMessage("Finished")

if __name__ == "__main__":
    main()
