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
try:
    import urllib.request as urllib_request
except ImportError:
    import urllib2 as urllib_request
import json
import uuid
import base64
import traceback
import socket
import subprocess

#Constants
TEMP_PREFIX = 'temp'
ROOT_USER = 1
NON_ROOT_USER = 2

VERIFICATION_SLEEP_INTERAVAL = 15
VERIFICATION_SLEEP_INTERAVAL_PER_ITERATION = 5

OS_UBUNTU = 1
OS_FEDORA = 2
OS_RHEL = 3
OS_CENTOS = 4
OS_UNSUPPORTED = -1

PROD_SYSLOG_NG = 1
PROD_RSYSLOG = 2
PROD_PLAIN_SYSLOG = 3
PROD_UNSUPPORTED = -1

#LOGGLY_SYSLOG_SERVER = "10.10.15.101"
LOGGLY_SYSLOG_SERVER = "collector01.chipper01.loggly.net"
LOGGLY_SYSLOG_PORT = 514
DISTRIBUTION_ID = "41058"
LOGGLY_CONFIG_FILE = "22-loggly.conf"
LOGGLY_ENV_DETAILS_FILE = "env_details.txt"

STR_EXIT_MESSAGE = "\nThis environment (OS) is not supported by the Loggly Syslog Configuration Script.  Please contact support@loggly.com for more information.\n"
STR_NO_SYSLOG_MESSAGE = "\nSupported syslog type/version not found.  Please contact support@loggly.com for more information.\n"
STR_MULTIPLE_SYSLOG_MESSAGE = ""
STR_SYSLOG_DAEMON_MESSAGE = "\nSyslog daemon (%s) is not running. Please start %s daemon and try again.\n"

REST_URL_SUBMIT_ENVIRONMENT = "http://testing.fe-app.dev.loggly.net:8000/chopper/account/overview" #"http://httpbin.org/post"
##REST_URL_GET_AUTH_TOKEN = "https://agistar.loggly.com/api/inputs"
REST_URL_GET_AUTH_TOKEN = "http://%s.frontend.chipper01.loggly.net/chopper/api/customer"
REST_URL_GET_SEARCH_ID = "http://%s.frontend.chipper01.loggly.net/chopper/api/search?q=%s&from=-2h&until=now&size=10"
REST_URL_GET_SEARCH_RESULT = "http://%s.frontend.chipper01.loggly.net/chopper/api/events?rsid=%s"
REST_URL_PUSH_INFO = "https://logs.frontend.chipper01.loggly.net/inputs/4f476788-f526-4744-a7c0-ff9b4b215689"

_LOG_SOCKET = None
OUR_PROGNAME      = "configure-syslog"
LOGGLY_PEN        = 41058
LOGGLY_AUTH_TOKEN = "f5b38b8c-ed99-11e2-8ee8-3c07541ea376"
LOGGLY_LOG_HOST = "logs-01.loggly.com"
LOGGLY_UDP_PORT = 514
# log priorities...
LOG_PRIORITIES = {"emerg":   0,  "alert":  1,  "crit": 2,   "error": 3,
                  "warning": 4,  "notice": 5,  "info": 6,   "debug": 7}

# log facilities...
LOG_FACILITIES = {"kern": 0<<3,    "user": 1<<3,      "mail": 2<<3,       "daemon": 3<<3,
                  "auth": 4<<3,    "syslog": 5<<3,    "lpr": 6<<3,        "news": 7<<3,
                  "uucp": 8<<3,    "cron": 9<<3,      "security": 10<<3,  "ftp": 11<<3,
                  "ntp": 12<<3,    "logaudit": 13<<3, "logalert": 14<<3,  "clock": 15<<3,
                  "local0": 16<<3, "local1": 17<<3,   "local2": 18<<3,    "local3": 19<<3,
                  "local4": 20<<3, "local5": 21<<3,   "local6": 22<<3,    "local7": 23<<3}

supported_os_environments = {
                                OS_UBUNTU: ["9.04", "9.10", "10.04", "10.10", "11.04", "11.10", "12.04", "12.10", "13.04"],
                                OS_FEDORA: ["11", "12", "13", "14", "15", "16", "17", "18", "19"],
                                OS_RHEL: ["5.2", "5.3", "5.4", "5.5", "5.6", "5.7", "5.8", "5.9", "6.1", "6.2", "6.3", "6.4", "6.0" ],
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

                                PROD_SYSLOG_NG: r"""#                -------------------------------------------------------
#                 Syslog Logging Directives for Loggly (www.loggly.com)
#                -------------------------------------------------------
%s
template t_LogglyFormat { template("<${PRI}>1 ${ISODATE} ${HOST} a:${PROGRAM} p:${PID} m:${MSGID} [%s@%s tag=\"Example1\"] $MSG\n");};
destination d_loggly { tcp("%s" port (%s) template(t_LogglyFormat)); };
log { source(%s); destination(d_loggly); };""",

                                
                                PROD_RSYSLOG: r"""#                -------------------------------------------------------
#                 Syslog Logging Directives for Loggly (www.loggly.com)
#                -------------------------------------------------------
# $template - Define logging format // $template <template_name> <logging_format>
# 
$template LogglyFormat,"<%%pri%%>%%protocol-version%% %%timestamp:::date-rfc3339%% %%HOSTNAME%% a:%%app-name%% p:%%procid%% m:%%msgid%% [%s@%s tag=\"Example1\"] %%msg:::drop-last-lf%%\n"

# Send messages to syslog server listening on TCP port using template

*.*             @@%s:%s;LogglyFormat

#                -------------------------------------------------------
""",

                                PROD_PLAIN_SYSLOG: "/etc/syslogd.conf"
                            }

SYSLOG_NG_SOURCE = 's_all'
SYSLOG_NG_SOURCE_TEXT = 'source %s { unix-stream("/dev/log"); internal(); file("/proc/kmsg" program_override("kernel: "));};' % SYSLOG_NG_SOURCE

yes = ['yes', 'ye', 'y']
no = ['no', 'n']

                
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
    sys.stdin = open("/dev/tty")
    get_input = ''
    try:
        get_input = raw_input
    except NameError:
        get_input = input
    
    st = get_input(st)
    return st
    
def version_compare(version1, version2):
    """
    Function will return following values.
    -1 : version1 is less than version2
    0 : version1 equals to version2
    1 : version1 is greater than version2
    """
    cmp_ex = lambda x, y: StrictVersion(x).__cmp__(y)
    return cmp_ex(version1, version2)

def get_os_id(os_name):
    """
    Get OS ID for corresponding OS present on machine
    """
    return {
        'ubuntu': OS_UBUNTU, 'fedora': OS_FEDORA, 'red hat enterprise linux server': OS_RHEL, 'centos': OS_CENTOS,
        }.get(os_name.lower(), OS_UNSUPPORTED)

def get_syslog_id(product_name):
    """
    Get syslog id from installed syslog product
    """
    return {
        'syslog-ng': PROD_SYSLOG_NG, 'rsyslog': PROD_RSYSLOG, 'syslogd': PROD_PLAIN_SYSLOG, 'sysklogd': PROD_PLAIN_SYSLOG,
        }.get(product_name.lower(), PROD_UNSUPPORTED)

def get_syslog_version(distro_id):
    """
    Derive which syslog version is installed
    """
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

def get_user_type():
    """
    Checks user type
    """
    if os.getuid() == 0:
        return ROOT_USER
    else:
        printLog("Script not started as root")
        return NON_ROOT_USER

def get_environment_details():
    """
    Get Distro Name, Distro ID, Version and ID.
    """
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

def perform_sanity_check(current_environment):
    """
    Performing quick check for OS and Syslog
    """
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

    #Check whether multiple syslogd running or not
    if len(current_environment['supported_syslog_versions']) > 1:
        index = 0
        running_syslog_count = 0
        for (syslog_name, syslog_version) in current_environment['supported_syslog_versions'].iteritems():
            if check_syslog_service_status(current_environment['distro_name'], list(current_environment['supported_syslog_versions'].keys())[index]):
                running_syslog_count += 1 
            index += 1
            printLog("\t%d. %s(%s)" % (index, syslog_name, syslog_version))
        if running_syslog_count > 1:
            printLog('Multiple syslogd are running')
            printLog('Can not automatically re-configure syslog for this Linux distribution')
            sys.exit(-1)
    printLog("Sanity Check Passed. Your environment is supported.")

def find_syslog_process():
    """Returns the running syslog type (syslog-ng, rsyslog) and the PID of the running process."""

    syslog_ps_commands = ["ps -U syslog | grep syslog | grep -v grep",
                          "ps -e | grep syslog | grep -v grep"]

    for ps_command in syslog_ps_commands:
        errorfname = TEMP_PREFIX + ".cmdout"
        errorfile = open(errorfname, 'w')
        print("Looking for syslog process: executing '%s'" % ps_command)
        nullfile = open(os.devnull)
        p = subprocess.Popen(ps_command, shell=True, stdin=nullfile,
                             stdout=subprocess.PIPE, stderr=errorfile)
        results = p.stdout.read().strip()
        p.stdout.close()
        errorfile.close()
        p.poll()
        print("Return code is %s" % p.returncode)

        try:
            os.remove(errorfname)
        except (IOError, OSError): pass

        if results:
            reslines = results.split('\n')
            if len(reslines) == 1:
                print("PS output: %s" % reslines[0])
                ps_out_fields = reslines[0].split()
                pid = int(ps_out_fields[0])
                progname = ps_out_fields[3]
                return (progname, pid)

    return None,0

def check_syslog_service_status(distro_name, syslog_type):
    """
    Checks for syslog daemon status
    """
    if not os.path.exists(syslog_processid_path.get(get_os_id(distro_name)).get(get_syslog_id(syslog_type))):
        return False
    return True

      
def product_for_configuration(current_environment, check_syslog_service = True):
    """
    Checks for multiple syslog daemon installed.
    """
    user_choice = 0
    
    if len(current_environment['supported_syslog_versions']) > 1:
        printLog("Multiple versions of syslog detected on your system.")
        index = 0
        for (syslog_name, syslog_version) in current_environment['supported_syslog_versions'].iteritems():
            index += 1
            printLog("\t%d. %s(%s)" % (index, syslog_name, syslog_version))
            
        for _ in range(0, 5):
            try:
                str_msg = "Please select (1-" + str(index) + ") to specify which version of syslog you'd like configured. (Default is 1): "
                user_choice = int(usr_input(str_msg)) - 1
                break
            except ValueError:
                printLog ("Not a valid response. Please retry.")
        if user_choice < 0 or user_choice > (index):
            printLog("Invalid choice entered. Continue with default value.")
            user_choice = 0
    syslog_type = list(current_environment['supported_syslog_versions'].keys())[user_choice]

    if check_syslog_service:
        if not check_syslog_service_status(current_environment['distro_name'], syslog_type):
            printLog(STR_SYSLOG_DAEMON_MESSAGE % (syslog_type, syslog_type))
            sys.exit(-1)
    printLog("Configuring %s-%s" % (list(current_environment['supported_syslog_versions'].keys())[user_choice], list(current_environment['supported_syslog_versions'].values())[user_choice]))
    return syslog_type



def get_installed_syslog_configuration(syslog_id):
    """
    Fetching installed/configured syslog details
    """
    default_directory = ''
    auth_token = ''
    source = ''
    printLog("Reading default configuration directory path from (%s)." % default_config_file_name.get(syslog_id))
    text_file = open(default_config_file_name.get(syslog_id), "r")
    
    if syslog_id == PROD_RSYSLOG:
        include_pattern = "^\s*[^#]\s*IncludeConfig\s+([\S]+/)"
        auth_token_pattern = "^\s*[^#]*\s*template\sLogglyFormat.*\[([a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}).*"
    elif syslog_id == PROD_SYSLOG_NG:
        include_pattern = "^\s*[^#]\s*Include\s+([\S]+/)"
        source_pattern = "^\s*source\s+([\S]+)\s*"
        auth_token_pattern = "^\s*template\s+t_LogglyFormat\s*.*\[([a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}).*\}"
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

def write_configuration(syslog_name_for_configuration, authorization_details, user_type):
    """
    Function to create/modify configuration file
    """
    printLog("Reading configuration directory path....")
    syslog_id = get_syslog_id(syslog_name_for_configuration)
    syslog_configuration_details = get_installed_syslog_configuration(syslog_id)

    if len(syslog_configuration_details.get("path")) > 0:
        printLog("The default syslog configuration file location is (%s)." % syslog_configuration_details.get("path"))
        question = "\nThe Loggly Syslog Configuration Script will either create a new configuration file or will add configuration parameters to the existing file (%s). The new configuration file will be located at (%s). The new file won't affect the existing configuration.\n\nDo you want the Loggly Syslog Configuration Script to create a new file? [Yes|No] " % (default_config_file_name.get(syslog_id), os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE))
        for _ in range(0, 5):
            user_input = usr_input(question).lower()
            if len(user_input) > 0:
                if  user_input in yes:
                    create_loggly_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type, syslog_name_for_configuration)
                    return
                elif user_input in no:
                    modify_syslog_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type)
                    return
    else:
        modify_syslog_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type)
        return

    printLog("\nFailed to read configuration directory path after maximum attempts.\nPlease contact support@loggly.com for more information.\n")
    printMessage("Aborting")
    sys.exit(-1)

def remove_configuration(syslog_name_for_configuration):
    
    syslog_id = get_syslog_id(syslog_name_for_configuration)
    syslog_configuration_details = get_installed_syslog_configuration(syslog_id)
    default_config_file = default_config_file_name.get(syslog_id)
    if len(syslog_configuration_details.get("path")) > 0:
        loggly_file_path = os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)
        if os.path.exists(loggly_file_path):
            printLog('Removing configuration file %s' % loggly_file_path)
            os.remove(loggly_file_path)
    printLog('Removing configuration settings from file %s for %s' % (default_config_file, syslog_name_for_configuration))
    if syslog_name_for_configuration == 'rsyslog':
        os.popen("sed -i 's/^\s*$template LogglyFormat/#$template LogglyFormat/g' %s" % default_config_file)
        pattern = "s/^\s*\*\.\*.*@@{0}:{1};LogglyFormat/#*.* @@{0}:{1};LogglyFormat/g".format(LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT)
        os.popen("sed -i '%s' %s" % (pattern, default_config_file))
    elif syslog_name_for_configuration == 'syslog-ng':
        os.popen("sed -i 's/^\s*template t_LogglyFormat/#template t_LogglyFormat/g' %s" % default_config_file)
        os.popen("sed -i 's/^\s*destination d_loggly/#destination d_loggly/g' %s" % default_config_file)
        output = os.popen('grep -P "^\s*log { source\(.*\); destination\(d_loggly\); };" -o %s' %  default_config_file).read().rstrip()
        if output and len(output) > 0:
            os.popen("sed -i 's/^\s*{0}/#{0}/g' {1}".format(output, default_config_file))
        os.popen("sed -i 's/^\s*source {0}/#source {0}/g' {1}".format(SYSLOG_NG_SOURCE, default_config_file))
        
def login():
    """
    Ask for Loggly credentials
    """
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


def get_json_data(url, user, password):
    """
    Retrieve Auth Token and Distribution ID from Loggly account
    """
    req = urllib_request.Request(url)
    req.add_header("Accept", "application/json")
    req.add_header("Content-type", "application/json")
    user_passwd = base64.b64encode((user + ":" + password).encode('utf-8'))
    req.add_header("Authorization", "Basic " + str(user_passwd.rstrip().decode("utf-8")))
    return json.loads(urllib_request.urlopen(req).read().decode("utf-8"))


    
def get_auth_token_and_distribution_id(loggly_user, loggly_password, loggly_subdomain):
    """
    Create the request object and set some headers
    """
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
            printLog("\nLoggly will be configured with \"%s\" Customer Token.\n" % token)
            return { "token" : token, "id": DISTRIBUTION_ID }
        else:
            printLog("Loggly credentials could not be verified.")
            sys.exit()

    except urllib_request.HTTPError as e:
        printLog ("%s" % e)
        sys.exit(-1)
        
    except urllib_request.URLError as e:
        printLog ("%s" % e)
        sys.exit(-1)
        
    except Exception as e:
        traceback.print_exc()
        printLog ("Exception %s" % e)
        sys.exit(-1)

def syslog_config_file_content(syslog_id, source, authorization_details):
    """
    Creating syslog content for configuring Loggly
    """
    content = ""
    
    if syslog_id == PROD_RSYSLOG:
        content = configuration_text.get(syslog_id) % (authorization_details.get("token"), authorization_details.get("id"), LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT)
    elif syslog_id == PROD_SYSLOG_NG:
        printLog("Reading configured source from (%s) file." % default_config_file_name.get(syslog_id))
        configured_source = source
        source_created = ''
       
        if len(configured_source) <= 0:
            source_created = SYSLOG_NG_SOURCE_TEXT
            configured_source = SYSLOG_NG_SOURCE
        content = configuration_text.get(syslog_id) % (source_created, authorization_details.get("token"), authorization_details.get("id"), LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT, configured_source)
    elif syslog_id == PROD_PLAIN_SYSLOG:
        content = "rpm -qa | grep -i 'sys' | grep -i 'log'"
    else:
        printLog("Failed to create content for syslog id %s\n" % syslog_id)
        printMessage("Aborting")
        sys.exit(-1)
        
    return content + "\n"

def create_bash_script(content):
    file_path = '/tmp/configure-syslog.%s.sh' % os.getpid()
    config_file =  open(file_path, "w")
    config_file.write(content)
    config_file.close()
    printLog("Current user is not root user. Run script % s as root and then run configure-syslog.py again with 'verify'" % file_path)
    printMessage("Finished")
    sys.exit()

    return file_path

def create_loggly_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type, syslog_name_for_configuration):
    """
    Create Loggly configuration file
    """
    file_path = os.path.join(os.getenv("HOME"), LOGGLY_CONFIG_FILE)
    printLog("Creating configuration file at %s" % file_path)
    content = syslog_config_file_content(syslog_id, syslog_configuration_details.get("source"), authorization_details)
    try:
        config_file =  open(file_path, "w")
        config_file.write(content)
        config_file.close()
        if user_type == NON_ROOT_USER:
            # print Instructions...
            content = "mv -f %s %s" % (file_path, os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE))
            bash_script_name = create_bash_script(content)
        else:
            if os.path.isfile(os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)):
                msg = "Loggly configuration file (%s) is already present. Do you want to overwrite it? [Yes|No]: " % os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)
                
                for _ in range(0, 5):
                    user_input = usr_input(msg).lower()
                    if len(user_input) > 0:
                        if  user_input in yes:
                            os.popen("mv -f %s %s" % (file_path, os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)))
                            return
                        elif user_input in no:
                            return
                        else:
                            printLog("Not a valid input. Please retry.")
            else:
                os.popen("mv -f %s %s" % (file_path, os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)))
                return
            
            printLog("Invalid input received after maximum attempts.")
            printMessage("Aborting")
            sys.exit(-1)
            
    except IOError as e:
        printLog ("IOError %s" % e)

def modify_syslog_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type):
    """
    Modifying configuration file by adding Loggly configuration text
    """
    comment = "\n#Configuration modified by Loggly Syslog Configuration Script (%s)\n#\n" % datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
    content = syslog_config_file_content(syslog_id, syslog_configuration_details.get("source"), authorization_details)

    if len(syslog_configuration_details.get("token")) <= 0:
        question = "\nThe Loggly configuration will be appended to (%s) file.\n\nDo you want this installer to modify the configuration file? [Yes|No]: " % default_config_file_name.get(syslog_id)
        for _ in range(0, 5):
            user_input = usr_input(question).lower()
            if len(user_input) > 0:
                if  user_input in yes:
                    
                    backup_file_name = "%s_%s.bak" % (default_config_file_name.get(syslog_id), datetime.now().strftime('%Y-%m-%dT%H:%M:%S'))

                    temp_file = tempfile.NamedTemporaryFile(delete=False)
                    temp_file.write(content)
                    temp_file.close()
                    if user_type == ROOT_USER:
                        os.popen("cp -p %s %s" % (default_config_file_name.get(syslog_id), backup_file_name))
                        os.popen("bash -c 'cat %s >> %s' " % (temp_file.name, default_config_file_name.get(syslog_id))).read()
                        os.unlink(temp_file.name)
                    else:
                        bash_script_content = "cp -p %s %s \nbash -c 'cat %s >> %s'" % (default_config_file_name.get(syslog_id), backup_file_name, temp_file.name, default_config_file_name.get(syslog_id))
                        create_bash_script(bash_script_content)
                    return backup_file_name
                
                elif user_input in no:
                    printLog("\n\nPlease add the following lines to the syslog configuration file (%s).\n\n%s%s" % (default_config_file_name.get(syslog_id), comment, content))
                    printMessage("Finished")
                    sys.exit(0)
    else:
        question = "\nLoggly is already configured with %s Customer Token. Do you want to overwrite it? [Yes|No]: " % syslog_configuration_details.get("token")
        for _ in range(0, 5):
            user_input = usr_input(question).lower()
            if len(user_input) > 0:
                if  user_input in yes:
                    pattern = "s/[a-z0-9]\{8\}\-[a-z0-9]\{4\}\-[a-z0-9]\{4\}\-[a-z0-9]\{4\}\-[a-z0-9]\{12\}/%s/g" % authorization_details.get("token")
                    if user_type == ROOT_USER:
                        os.popen("sed -i '%s' %s" % (pattern, default_config_file_name.get(syslog_id)))
                    else:
                        bash_script_content = "sed -i '%s' %s" % (pattern, default_config_file_name.get(syslog_id))
                        create_bash_script(bash_script_content)
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

def send_sighup_to_syslog(syslog_type, user_type, distro_id):
    """
    Sending sighup to syslog daemon
    """
    if user_type == ROOT_USER:
        syslog_processid_file = syslog_processid_path.get(distro_id).get(get_syslog_id(syslog_type))
        if os.path.exists(syslog_processid_file):
            question = "Do you want the Loggly Syslog Configuration Script to restart (SIGHUP) the syslog daemon. [Yes|No]: "
            for _ in range(0, 5):
                user_input = usr_input(question).lower()
                if len(user_input) > 0:
                    if  user_input in yes:
                        output = os.popen("sudo kill -SIGHUP `cat %s`" % syslog_processid_file).read()
                        #output = os.popen("/etc/init.d/rsyslog restart").read()
                        printLog("SIGHUP Sent. %s" % (output))
                        return True
                    elif user_input in no:
                        return False
                    else:
                        printLog("Not a valid input. Please retry.")
        else:
            printLog("Syslog daemon (%s) is not running. Configuration file has been modified, please start %s daemon manually." % (syslog_type, syslog_type))

    return False


def doverify(loggly_user, loggly_password, loggly_subdomain):
    
    printLog("Sending a test message using logger.")
    unique_string = str(uuid.uuid4()).replace("-","")
    dummy_message = "Testing that your log messages can make it to Loggly! %s" % unique_string
    printLog ("Sending message (%s) to Loggly server (%s)" % (dummy_message, LOGGLY_SYSLOG_SERVER))
    os.popen("logger -p INFO '%s'" % dummy_message).read()
    search_url = REST_URL_GET_SEARCH_ID % (loggly_subdomain, unique_string)
    # Implement REST APIs to search if dummy message has been sent.
    wait_time = 0
    while wait_time < VERIFICATION_SLEEP_INTERAVAL:
        printLog("Sending search request. %s" % search_url)
        data = get_json_data(search_url, loggly_user, loggly_password)
        rsid = data["rsid"]["id"]
        search_result_url = REST_URL_GET_SEARCH_RESULT % (loggly_user, rsid)
        printLog("Sending search result request. %s" % search_result_url)
        data = get_json_data(search_result_url, loggly_user, loggly_password)
        total_events = data["total_events"]
        if total_events >= 1:
            printLog("******* Congratulations! Loggly is configured successfully.")
            break
        wait_time += VERIFICATION_SLEEP_INTERAVAL_PER_ITERATION
        time.sleep(VERIFICATION_SLEEP_INTERAVAL_PER_ITERATION)
    if wait_time >= VERIFICATION_SLEEP_INTERAVAL:
        printLog("!!!!!! Loggly verification failed. Please contact support@loggly.com for more information.")


def write_env_details():
    """
    Write environment information to a file
    """
    try:
        file_path = os.path.join(os.getcwd(), LOGGLY_ENV_DETAILS_FILE)
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
            
    except Exception as e:
        printLog ("Error %s" % e)

def version_compatibility_check(minimum_version):
    """
    Checks for compatible Python version.
    """
    sys_version = ".".join(map(str, sys.version_info[:2]))
    if sys_version < minimum_version:
        printLog('Python version check fails: Installed version is ' + sys_version + '. Minimum required version is ' + str(minimum_version))
        return False
    
    printLog('Python version check successful: Installed version is ' + sys_version + '. Minimum required version is ' + str(minimum_version))
    return True

def log(msg, prio = 'info', facility = 'local0'):
    """
    Send a log message to Loggly; send a UDP datagram to Loggly rather than risk blocking.
    """

    global _LOG_SOCKET

    try:
        pri = LOG_PRIORITIES[prio] + LOG_FACILITIES[facility]
    except KeyError as errmsg:
        pass
        #raise IOError as ("Unknown facility or priority: %s" % errmsg)
    
    vals = {}
    vals['pri'] = pri
    vals['version'] = 1
    vals['timestamp'] = datetime.datetime.isoformat(datetime.datetime.now())
    vals['hostname'] = socket.gethostname()
    vals['app-name'] = OUR_PROGNAME
    vals['procid'] = os.getpid()
    vals['msgid'] = '-'
    vals['loggly-auth-token'] = LOGGLY_AUTH_TOKEN
    vals['loggly-pen'] = LOGGLY_PEN
    vals['msg'] = msg

    fullmsg = ("<%(pri)s>%(version)s %(timestamp)s %(hostname)s %(app-name)s %(procid)s %(msgid)s "
               "[%(loggly-auth-token)s@%(loggly-pen)s] %(msg)s") % vals

##  debug("Log: %s" % fullmsg)

    """if not _LOG_SOCKET:  # first time only...
        _LOG_SOCKET = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    _LOG_SOCKET.sendto(fullmsg, (LOGGLY_LOG_HOST, LOGGLY_UDP_PORT))"""


def install():
    
    # 1. Determine user type.
    user_type = get_user_type()
    # 2. Determine the environment in which it was invoked (i.e. which distro, release, and syslog daemon has been deployed)
    current_environment = get_environment_details()
    printEnvironment(current_environment)
    perform_sanity_check(current_environment)
    syslog_name_for_configuration = product_for_configuration(current_environment)  

    loggly_user, loggly_password, loggly_subdomain = login()
    authorization_details = get_auth_token_and_distribution_id(loggly_user, loggly_password, loggly_subdomain)
    # 4. If possible, determine the location of the syslog.conf file or the syslog.conf.d/ directory.
    # Provide the location as the default and prompt the user for confirmation.
    
    # 5. Create custom configuration file and place it in configuration directory path ($IncludeConfig), default path for rsyslog will be /etc/rsyslog.d/
    write_configuration(syslog_name_for_configuration, authorization_details, user_type)    

    # 6. SIGHUP the syslog daemon.
    sighup_status = send_sighup_to_syslog(syslog_name_for_configuration, user_type, current_environment['distro_id'])
    doverify(loggly_user, loggly_password, loggly_subdomain)
    
def verify():
    
    current_environment = get_environment_details()
    printEnvironment(current_environment)
    perform_sanity_check(current_environment)
    syslog_name_for_configuration = product_for_configuration(current_environment)
    loggly_user, loggly_password, loggly_subdomain = login()
    doverify(loggly_user, loggly_password, loggly_subdomain)

def uninstall():
    
    user_type = get_user_type()
    if user_type == NON_ROOT_USER:
        printLog("Current user in not root user")
        sys.exit()
    else:
        current_environment = get_environment_details()
        printEnvironment(current_environment)
        perform_sanity_check(current_environment)
        syslog_name_for_configuration = product_for_configuration(current_environment, check_syslog_service = False)
        remove_configuration(syslog_name_for_configuration)
        sighup_status = send_sighup_to_syslog(syslog_name_for_configuration, user_type, current_environment['distro_id'])

def parseOptions():
    """
    Parse command line argument
    """
    usage = "usage: %prog -i|--install "
    parser = OptionParser(usage=usage, version="Install Sender")
    parser.add_option("-i", "--install", action="store_true", dest="install", default=False,
                      help='Configure the syslog')
    parser.add_option("-u", "--uninstall", action="store_true", dest="uninstall", default=False,
                      help='Remove the changes made by the syslog configurator script')
    parser.add_option("-v", "--verify", action="store_true", dest="verify", default=False,
                      help='Verify the configuration explicitly')
    parser.add_option("-s", "--sysinfo", action="store_true", dest="sysinfo", default=False,
                      help='Print, write system information')
    parser.add_option("-l", "--loggly_help", action="store_true", dest="help", default=False,
                      help='Guideline for users for each step to configure syslog')
    parser.add_option("-p", "--verbose", action="store_true", dest="verbose", default=False,
                      help='Print detailed logs on console')
    parser.add_option("-d", "--dryrun", action="store_true", dest="dryrun", default=False,
                      help='Perform configuration steps without modifying anything')
    (options, args) = parser.parse_args()
    
    if not (options.install or options.uninstall or options.verify or options.sysinfo or options.dryrun or options.help):
        parser.print_usage()
        os._exit(0)

    return options


# Script starts here
def main():
    printMessage("Starting")
    
    if not version_compatibility_check('2.6'):
        sys.exit(-1)
        
    options = vars(parseOptions())
    
    if options['sysinfo']:
        write_env_details()
        printMessage("Finished")
        sys.exit()

    elif options['uninstall']:
        printLog("Uninstall")
        uninstall()
        
    elif options['install']:
        printLog("Install")
        install()

    elif options['verify']:
        printLog("Verify")
        verify()

    printMessage("Finished")

if __name__ == "__main__":
    main()
