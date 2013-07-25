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
import socket
import subprocess

#Constants
TEMP_PREFIX = 'temp'
ROOT_USER = 1
NON_ROOT_USER = 2

MINIMUM_SUPPORTED_PYTHON_VERSION = '2.6'
VERIFICATION_SLEEP_INTERAVAL = 15
VERIFICATION_SLEEP_INTERAVAL_PER_ITERATION = 5

OS_UBUNTU = 1
OS_FEDORA = 2
OS_RHEL = 3
OS_CENTOS = 4
OS_UNSUPPORTED = -1

PROD_SYSLOG_NG = 1
PROD_RSYSLOG = 2
PROD_UNSUPPORTED = -1

#LOGGLY_SYSLOG_SERVER = "10.10.15.101"
LOGGLY_SYSLOG_SERVER = "collector01.chipper01.loggly.net"
LOGGLY_SYSLOG_PORT = 514
DISTRIBUTION_ID = "41058"
LOGGLY_CONFIG_FILE = "22-loggly.conf"
LOGGLY_ENV_DETAILS_FILE = "env_details.txt"
PROCESS_ID = -1

STR_EXIT_MESSAGE = "\nThis environment (OS) is not supported by the Loggly Syslog Configuration Script.  Please contact support@loggly.com for more information.\n"
STR_NO_SYSLOG_MESSAGE = "\nSupported syslog type/version not found."
STR_ERROR_MESSAGE = "\nCan not automatically re-configure syslog for this Linux distribution.\nUse the help option for instructions to manually re-configure syslog for Loggly."
STR_SYSLOG_DAEMON_MESSAGE = "\nSyslog daemon (%s) is not running. Please start %s daemon and try again.\n"
REST_URL_GET_AUTH_TOKEN = "http://%s.frontend.chipper01.loggly.net/chopper/api/customer"
REST_URL_GET_SEARCH_ID = "http://%s.frontend.chipper01.loggly.net/chopper/api/search?q=%s&from=-2h&until=now&size=10"
REST_URL_GET_SEARCH_RESULT = "http://%s.frontend.chipper01.loggly.net/chopper/api/events?rsid=%s"
REST_URL_PUSH_INFO = "https://logs.frontend.chipper01.loggly.net/inputs/4f476788-f526-4744-a7c0-ff9b4b215689"

_LOG_SOCKET = None
OUR_PROGNAME      = "configure-syslog"
LOGGLY_PEN        = 41058
LOGGLY_AUTH_TOKEN = "f5b38b8c-ed99-11e2-8ee8-3c07541ea376"
LOGGLY_LOG_HOST = "logs-01.loggly.com"
#LOGGLY_LOG_HOST = "10.10.15.105"
LOGGLY_UDP_PORT = 514


RSYSLOG_PROCESS = 'rsyslogd'
SYSLOG_NG_PROCESS = 'syslog-ng'

supported_syslog_versions = {
                                PROD_SYSLOG_NG: ["1.6", "2.0", "2.1", "3.1", "3.2", "3.3", "3.4", "3.5"],
                                PROD_RSYSLOG: ["1.19", "2.0", "3.14", "3.21", "3.22", "4.2", "4.4", "4.6", "5.7", "5.8", "7.2", "7.3"],
                            }

default_config_file_name = {
                                PROD_SYSLOG_NG: "/etc/syslog-ng/syslog-ng.conf",
                                PROD_RSYSLOG: "/etc/rsyslog.conf",
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
"""
                            }
USER = None
SUBDOMAIN = None
SYSLOG_NG_SOURCE = 's_loggly'
SYSLOG_NG_SOURCE_TEXT = r'source %s { \nunix-stream("/dev/log"); \ninternal(); \nfile("/proc/kmsg" program_override("kernel: "));\n};'

yes = ['yes', 'ye', 'y']
no = ['no', 'n']

LOGGLY_HELP = r"""
Instructions to manually re-configure syslog for Loggly
=======================================================

1.Modification in configuration file
 rsyslog
 -------
 
 -Edit your rsyslog.conf file, usually found in /etc/rsyslog.conf, and add the following line at the bottom of the file:
 $template LogglyFormat,"<%%pri%%>%%protoco-version%% %%timestamp:::date-rfc3339%% %%HOSTNAME%% a:%%app-name%% p:%%procid%% m:%%msgid%% [%s@%s tag=\"Example1\"] %%msg:::drop-last-lf%%"
 *.*             @@%s:%s;LogglyFormat
 
 syslog-ng
 ---------
 
 -Edit your syslog-ng.conf file, usually found in /etc/syslog-ng/syslog-ng.conf, and add the following line at the bottom of the file:
 template t_LogglyFormat { template("<${PRI}>1 ${ISODATE} ${HOST} a:${PROGRAM\ p:${PID} m:${MSGID} [%s@%s tag=\"Example1\"] $MSG");};
 destination d_loggly { tcp("%s" port (%s) template(t_LogglyFormat)); };
 log { source(%s); destination(d_loggly); };
 
 Also make sure that your source should be like as below
    source %s {
    internal();
    unix-stream("/dev/log");
    file("/path/to/your/file" follow_freq(1) flags(no-parse));
    };
    
2. Once you are done configuring syslog-ng or rsyslog, restart it
   Example:  /etc/init.d/syslog-ng restart
   
3. Send some data through syslog-ng or rsyslog to have it forwarded to your Loggly account
   logger 'loggly is better than a bee in your aunt's bonnet'
   """

LOGGLY_HELP = LOGGLY_HELP % ('auth-token', DISTRIBUTION_ID, LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT, 'auth-token', DISTRIBUTION_ID, LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT, 'source_name', 'source_name')
#% (configuration_text.get(PROD_RSYSLOG) % ('auth-token', 'enterprise id', LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT))
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



class Logger:
    is_printLog = False
    #Display messages or not based on command line argument
    @staticmethod
    #def log(msg, prio = 'info', facility = 'local0'):
    def printLog(message, prio = 'info', print_comp = False):
        if Logger.is_printLog or print_comp:
            print(message)
        log(message, prio = prio)
                
def printLog(message):
    print(message)

def printMessage(message):
    Logger.printLog("\n*************************************************************", print_comp = True)
    Logger.printLog("****** " + message + " Loggly Syslog Configuration Script ******", print_comp = True)
    Logger.printLog("*************************************************************\n", print_comp = True)

def printEnvironment(current_environment):
    Logger.printLog("Operating System: %s-%s(%s)" % (current_environment['distro_name'], current_environment['version'], current_environment['id']), print_comp = True)
    Logger.printLog("Syslog versions:", print_comp = True)
    if len(current_environment['syslog_versions']) > 0:
        for index in range(0, len(current_environment['syslog_versions'])):
            Logger.printLog("\t%d.   %s(%s)" % (index + 1, current_environment['syslog_versions'][index][0], current_environment['syslog_versions'][index][1]), print_comp = True)
    else:
        Logger.printLog("\tNo Syslog Version Found......", prio = 'crit', print_comp = True)

def sendEnvironment(data):
    Logger.printLog("Sending Environment Details to Loggly Server.")
    try:
        urllib_request.urlopen(REST_URL_PUSH_INFO, data)
    except urllib_request.HTTPError as e:
        Logger.printLog("%s" % e, prio = 'error', print_comp = True)
        sys.exit(-1)
    except urllib_request.URLError as e:
        Logger.printLog("%s" % e, prio = 'error', print_comp = True)
        sys.exit(-1)
    except Exception as e:
        Logger.printLog("Exception %s" % e, prio = 'error', print_comp = True)
        sys.exit(-1)
    #distro_name


def sys_exit(reason = None):
    current_environment = get_environment_details()
    data = json.dumps({"operating_system": current_environment['operating_system'], "syslog_versions": current_environment['syslog_versions'], "reason":reason, "username":USER, "subdomain": SUBDOMAIN})
    sendEnvironment(data)
    sys.exit(-1)
    

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
        'syslog-ng': PROD_SYSLOG_NG, 'rsyslog': PROD_RSYSLOG,
        }.get(product_name.lower(), PROD_UNSUPPORTED)

def get_syslog_process_name(product_name):
    return {
        'syslog-ng': SYSLOG_NG_PROCESS, 'rsyslog': RSYSLOG_PROCESS,
        }.get(product_name.lower(), PROD_UNSUPPORTED)

def get_syslog_version(distro_id):
    """
    Derive which syslog version is installed
    """
    Logger.printLog("Reading Installed Syslog Versions....", prio = 'debug')
    if distro_id == OS_UBUNTU:
        command = "dpkg -l \*sys\*log\* | grep ^ii"
        pattern = 'ii\s+(rsyslog|syslog-ng)\s+(\d+\.\d+)'
    elif distro_id == OS_FEDORA:
        command = "rpm -qa | grep -i 'sys' | grep -i 'log'"
        pattern = '(rsyslog|syslog-ng)-(\d+\.\d+)'
    elif distro_id == OS_RHEL:
        command = "rpm -qa | grep -i 'sys' | grep -i 'log'"
        pattern = '(rsyslog|syslog-ng)-(\d+\.\d+)'
    elif distro_id == OS_CENTOS:
        command = "rpm -qa | grep -i 'sys' | grep -i 'log'"
        pattern = '(rsyslog|syslog-ng)-(\d+\.\d+)'
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
        Logger.printLog("Script not started as root", print_comp = True)
        return NON_ROOT_USER

def get_environment_details():
    """
    Get Distro Name, Distro ID, Version and ID.
    """
    Logger.printLog("Reading Environment Details....", prio = 'debug')
    environment = {}
    distribution = platform.linux_distribution()
    environment['distro_name'] = distribution[0]
    environment['distro_id'] = get_os_id(distribution[0])
    environment['version'] = distribution[1]
    environment['id'] = distribution[2]
    environment['syslog_versions'] = get_syslog_version(environment['distro_id']) 
    environment['supported_syslog_versions'] = {}
    environment['operating_system'] = "%s-%s(%s)" % (environment['distro_name'], environment['version'], environment['id'])
    return environment

def perform_sanity_check(current_environment):
    """
    Performing quick check for OS and Syslog
    """
    Logger.printLog("Performing Sanity Check....", prio = 'debug')
    if (current_environment['distro_id'] == OS_UNSUPPORTED):
        printLog(STR_EXIT_MESSAGE)
        printMessage("Aborting")
        sys_exit(reason = STR_EXIT_MESSAGE)

    syslog_versions = {}
    for (syslog_type, syslog_version) in current_environment['syslog_versions']:
        syslog_id = get_syslog_id(syslog_type)
        if syslog_version in supported_syslog_versions.get(syslog_id):
            syslog_versions[syslog_type] = syslog_version

    current_environment['supported_syslog_versions'] = syslog_versions

    if(current_environment['supported_syslog_versions'] == None or len(current_environment['supported_syslog_versions']) <= 0):
        printLog(STR_NO_SYSLOG_MESSAGE)
        printLog(STR_ERROR_MESSAGE)
        printMessage("Aborting")
        sys_exit(reason = STR_NO_SYSLOG_MESSAGE)

    #Check whether multiple syslogd running or not
    if len(current_environment['supported_syslog_versions']) > 1:
        index = 0
        running_syslog_count = 0
        for (syslog_name, syslog_version) in current_environment['supported_syslog_versions'].iteritems():
            if check_syslog_service_status(list(current_environment['supported_syslog_versions'].keys())[index]):
                running_syslog_count += 1 
            index += 1
            Logger.printLog("\t%d. %s(%s)" % (index, syslog_name, syslog_version), print_comp = True)
        if running_syslog_count > 1:
            Logger.printLog('Multiple syslogd are running', prio = 'error', print_comp = True)
            Logger.printLog(STR_ERROR_MESSAGE, prio = 'error', print_comp = True)
            sys_exit(reason = 'Multiple syslogd are running')
    Logger.printLog("Sanity Check Passed. Your environment is supported.")

def find_syslog_process():
    """Returns the running syslog type (syslog-ng, rsyslog) and the PID of the running process."""

    syslog_ps_commands = ["ps -U syslog | grep syslog | grep -v grep",
                          "ps -ef | grep syslog | grep -v supervising | grep -v python | grep $USER | grep -v grep"]

    for ps_command in syslog_ps_commands:
        errorfname = TEMP_PREFIX + ".cmdout"
        errorfile = open(errorfname, 'w')
        nullfile = open(os.devnull)
        p = subprocess.Popen(ps_command, shell=True, stdin=nullfile,
                             stdout=subprocess.PIPE, stderr=errorfile)
        results = p.stdout.read().strip()
        p.stdout.close()
        errorfile.close()
        p.poll()
        try:
            os.remove(errorfname)
        except (IOError, OSError): pass

        if results:
            reslines = results.split('\n')
            if len(reslines) == 1:
                ps_out_fields = reslines[0].split()
                pid = int(ps_out_fields[1])
                progname = ps_out_fields[7]
                if '/' in progname:
                    progname = progname.split('/')[-1]
                return (progname, pid)
    return None, 0

def check_syslog_service_status(syslog_type):
    """
    Checks for syslog daemon status
    """
    process_name, pid = find_syslog_process()
    if process_name is None:
        pass
    else:
        global PROCESS_ID
        PROCESS_ID = pid
        syslog_process_name = get_syslog_process_name(syslog_type)
        if syslog_process_name == PROD_UNSUPPORTED:
            return False
        elif syslog_process_name == process_name:
            return True
    return False

      
def product_for_configuration(current_environment, check_syslog_service = True):
    """
    Checks for multiple syslog daemon installed.
    """
    user_choice = 0
    
    if len(current_environment['supported_syslog_versions']) > 1:
        Logger.printLog("Multiple versions of syslog detected on your system.", prio = 'notice', print_comp = True)
        index = 0
        for (syslog_name, syslog_version) in current_environment['supported_syslog_versions'].iteritems():
            index += 1
            Logger.printLog("\t%d. %s(%s)" % (index, syslog_name, syslog_version), print_comp = True)
            
        for _ in range(0, 5):
            try:
                str_msg = "Please select (1-" + str(index) + ") to specify which version of syslog you'd like configured. (Default is 1): "
                user_choice = int(usr_input(str_msg)) - 1
                break
            except ValueError:
                printLog ("Not a valid response. Please retry.")
        if user_choice < 0 or user_choice > (index):
            Logger.printLog("Invalid choice entered. Continue with default value.", prio = 'warning', print_comp = True)
            user_choice = 0
    syslog_type = list(current_environment['supported_syslog_versions'].keys())[user_choice]
    service_status = check_syslog_service_status(syslog_type)
    if check_syslog_service:
        if not service_status:
            Logger.printLog(STR_SYSLOG_DAEMON_MESSAGE % (syslog_type, syslog_type), prio = 'crit', print_comp = True)
            sys_exit(reason = STR_SYSLOG_DAEMON_MESSAGE % (syslog_type, syslog_type))
    Logger.printLog("Configuring %s-%s" % (list(current_environment['supported_syslog_versions'].keys())[user_choice], list(current_environment['supported_syslog_versions'].values())[user_choice]))
    return syslog_type



def get_installed_syslog_configuration(syslog_id):
    """
    Fetching installed/configured syslog details
    """
    default_directory = ''
    auth_token = ''
    source = ''
    Logger.printLog("Reading default configuration directory path from (%s)." % default_config_file_name.get(syslog_id), prio = 'debug')
    text_file = open(default_config_file_name.get(syslog_id), "r")
    
    if syslog_id == PROD_RSYSLOG:
        include_pattern = "^\s*[^#]\s*IncludeConfig\s+([\S]+/)"
        auth_token_pattern = "^\s*[^#]*\s*template\sLogglyFormat.*\[([a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}).*"
    elif syslog_id == PROD_SYSLOG_NG:
        include_pattern = "^\s*[^#]\s*Include\s+([\S]+/)"
        source_pattern = "^\s*source\s+([\S]+)\s*"
        auth_token_pattern = "^\s*template\s+t_LogglyFormat\s*.*\[([a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}).*\}"
        source_compiled_regex = re.compile(source_pattern, re.MULTILINE | re.IGNORECASE)
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
    Logger.printLog("Reading configuration directory path....", prio = 'debug')
    syslog_id = get_syslog_id(syslog_name_for_configuration)
    syslog_configuration_details = get_installed_syslog_configuration(syslog_id)

    if len(syslog_configuration_details.get("path")) > 0:
        Logger.printLog("The Loggly Syslog Configuration Script will create a new configuration file %s" % (os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)))
        create_loggly_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type)
        return
    else:
        modify_syslog_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type)
        return

    Logger.printLog("\nFailed to read configuration directory path after maximum attempts.\nPlease contact support@loggly.com for more information.\n", prio = 'error', print_comp = True)
    printMessage("Aborting")
    sys_exit(reason = 'Failed to read configuration directory path after maximum attempts')

def remove_configuration(syslog_name_for_configuration):
    """
    Remove configuration files 22-loggly.conf and comment configuration settings in default config file
    """    
    syslog_id = get_syslog_id(syslog_name_for_configuration)
    syslog_configuration_details = get_installed_syslog_configuration(syslog_id)
    default_config_file = default_config_file_name.get(syslog_id)
    if len(syslog_configuration_details.get("path")) > 0:
        loggly_file_path = os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)
        if os.path.exists(loggly_file_path):
            Logger.printLog('Removing configuration file %s' % loggly_file_path, print_comp = True)
            os.remove(loggly_file_path)
    Logger.printLog('Removing configuration settings from file %s for %s' % (default_config_file, syslog_name_for_configuration), print_comp = True)
    if syslog_name_for_configuration == 'rsyslog':
        os.popen("sed -i 's/^\s*$template\s*LogglyFormat/#$template LogglyFormat/g' %s" % default_config_file)
        pattern = "s/^\s*\*\.\*.*@@{0}:{1};LogglyFormat/#*.* @@{0}:{1};LogglyFormat/g".format(LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT)
        os.popen("sed -i '%s' %s" % (pattern, default_config_file))
    elif syslog_name_for_configuration == 'syslog-ng':
        os.popen("sed -i 's/^\s*template\s*t_LogglyFormat/#template t_LogglyFormat/g' %s" % default_config_file)
        os.popen("sed -i 's/^\s*destination\s*d_loggly/#destination d_loggly/g' %s" % default_config_file)
        output = os.popen('grep -P "^\s*log\s*{\s*source\(.*\);\s*destination\(d_loggly\);\s*};" -o %s' %  default_config_file).read().rstrip()
        if output and len(output) > 0:
            os.popen("sed -i 's/^\s*{0}/#{0}/g' {1}".format(output, default_config_file))
        syslog_ng_source_text_with_comment = (SYSLOG_NG_SOURCE_TEXT % SYSLOG_NG_SOURCE).replace('\\n', '\\n#')
        os.popen("sed -i '/^\s*source\s*%s\s*{/,/^\s*};$/c #%s' %s" % (SYSLOG_NG_SOURCE, syslog_ng_source_text_with_comment, default_config_file))
        
def login():
    """
    Ask for Loggly credentials
    """
    Logger.printLog("Reading Loggly credentials from user....", prio = 'debug')
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
                global USER
                global SUBDOMAIN
                USER = user
                SUBDOMAIN = subdomain
                return user, password, subdomain

    Logger.printLog("\nLoggly credentials not provided after maximum attempts.", prio = 'crit', print_comp = True)
    printMessage("Aborting")
    sys.exit()


def get_json_data(url, user, password):
    """
    Retrieve Auth Token and Distribution ID from Loggly account
    """
    try:
        req = urllib_request.Request(url)
        req.add_header("Accept", "application/json")
        req.add_header("Content-type", "application/json")
        user_passwd = base64.b64encode((user + ":" + password).encode('utf-8'))
        req.add_header("Authorization", "Basic " + str(user_passwd.rstrip().decode("utf-8")))
        return json.loads(urllib_request.urlopen(req).read().decode("utf-8"))
    except urllib_request.HTTPError as e:
        Logger.printLog("%s" % e, prio = 'error', print_comp = True)
        sys_exit(reason = "%s" % e)
    except urllib_request.URLError as e:
        Logger.printLog("%s" % e, prio = 'error', print_comp = True)
        sys_exit(reason = "%s" % e)
    except Exception as e:
        Logger.printLog("Exception %s" % e, prio = 'error', print_comp = True)
        sys_exit(reason = "%s" % e)

    
def get_auth_token(loggly_user, loggly_password, loggly_subdomain):
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
                Logger.printLog("No Customer Tokens were found.", prio = 'crit', print_comp = True)
                sys_exit(reason = "No Customer Tokens were found.")

            if len(auth_tokens) > 1:
                Logger.printLog("Multiple Customer Tokens received from server.", print_comp = True)
                for index in range(0, len(auth_tokens)):
                    Logger.printLog("\t%d. %s"%(index + 1, auth_tokens[index]), print_comp = True)
                for _ in range(0, 5):
                    try:
                        str_msg = "Please select (1-" + str(index + 1) + ") to specify which Customer Token you want to use. (Default is 1): "
                        user_choice = int(usr_input(str_msg)) - 1
                        if user_choice < 0 or user_choice > (index):
                            Logger.printLog("Invalid choice entered.", prio = 'error', print_comp = True)
                            continue
                        break
                    except ValueError:
                        Logger.printLog ("Not a valid selection. Please retry.", prio = 'warning', print_comp = True)
                if user_choice < 0 or user_choice > (index):
                    Logger.printLog("Invalid choice entered. Continue with default value.", prio = 'warning', print_comp = True)
                    user_choice = 0
            token = auth_tokens[user_choice]
            Logger.printLog("\nLoggly will be configured with \"%s\" Customer Token.\n" % token)
            return { "token" : token, "id": DISTRIBUTION_ID }
        else:
            Logger.printLog("Loggly credentials could not be verified.", prio = 'crit', print_comp = True)
            sys_exit(reason = "Loggly credentials could not be verified.")
        
    except Exception as e:
        Logger.printLog ("Exception %s" % e, prio = 'error', print_comp = True)
        sys_exit(reason = "%s" % e)

def syslog_config_file_content(syslog_id, source, authorization_details):
    """
    Creating syslog content for configuring Loggly
    """
    content = ""
    modify_source_content = ""
    if syslog_id == PROD_RSYSLOG:
        content = configuration_text.get(syslog_id) % (authorization_details.get("token"), authorization_details.get("id"), LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT)
    elif syslog_id == PROD_SYSLOG_NG:
        Logger.printLog("Reading configured source from (%s) file." % default_config_file_name.get(syslog_id))
        configured_source = source
        source_created = ''
        modify_source_content = None
        if len(configured_source) <= 0:
            source_created = SYSLOG_NG_SOURCE_TEXT % SYSLOG_NG_SOURCE
            configured_source = SYSLOG_NG_SOURCE
        else:
            modify_source_content = SYSLOG_NG_SOURCE_TEXT % source
        content = configuration_text.get(syslog_id) % (source_created, authorization_details.get("token"), authorization_details.get("id"), LOGGLY_SYSLOG_SERVER, LOGGLY_SYSLOG_PORT, configured_source)
    else:
        Logger.printLog("Failed to create content for syslog id %s\n" % syslog_id, prio = 'error', print_comp = True)
        printMessage("Aborting")
        sys_exit(reason = "Failed to create content for syslog id %s" % syslog_id)
        
    return content + "\n", modify_source_content

def create_bash_script(content):
    """
    If user is not ROOT user then create bash script in /tmp folder
    """
    file_path = '/tmp/configure-syslog.%s.sh' % os.getpid()
    config_file =  open(file_path, "w")
    config_file.write(content)
    config_file.close()
    Logger.printLog("Current user is not root user. Run script % s as root and then run configure-syslog.py again with 'verify'" % file_path, prio = 'crit', print_comp = True)
    printMessage("Finished")
    sys.exit()

def create_loggly_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type):
    """
    Create Loggly configuration file
    """
    file_path = os.path.join(os.getenv("HOME"), LOGGLY_CONFIG_FILE)
    Logger.printLog("Creating configuration file at %s" % file_path)
    command_content = ""
    content, modified_syslog_content = syslog_config_file_content(syslog_id, syslog_configuration_details.get("source"), authorization_details)
    try:
        config_file =  open(file_path, "w")
        config_file.write(content)
        config_file.close()
        if user_type == NON_ROOT_USER:
            # print Instructions...
            if modified_syslog_content and len(modified_syslog_content) > 0:
                command_content = "sed -i '/^source/,/};$/c %s' %s" % (modified_syslog_content, default_config_file_name.get(syslog_id))
            content = "mv -f %s %s\n%s" % (file_path, os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE), command_content)
            create_bash_script(content)
        else:
            if os.path.isfile(os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)):
                msg = "Loggly configuration file (%s) is already present. Do you want to overwrite it? [Yes|No]: " % os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)
                
                for _ in range(0, 5):
                    user_input = usr_input(msg).lower()
                    if len(user_input) > 0:
                        if user_input in yes:
                            os.popen("mv -f %s %s" % (file_path, os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)))
                            if modified_syslog_content and len(modified_syslog_content) > 0:
                                os.popen("sed -i '/^source/,/};$/c %s' %s" % (modified_syslog_content, default_config_file_name.get(syslog_id)))
                            return
                        elif user_input in no:
                            return
                        else:
                            Logger.printLog("Not a valid input. Please retry.", prio = 'warning', print_comp = True)
            else:
                os.popen("mv -f %s %s" % (file_path, os.path.join(syslog_configuration_details.get("path"), LOGGLY_CONFIG_FILE)))
                if modified_syslog_content and len(modified_syslog_content) > 0:
                    os.popen("sed -i '/^source/,/};$/c %s' %s" % (modified_syslog_content, default_config_file_name.get(syslog_id)))
                return
            
            Logger.printLog("Invalid input received after maximum attempts.", prio = 'error', print_comp = True)
            printMessage("Aborting")
            sys.exit(-1)
            
    except IOError as e:
        Logger.printLog ("IOError %s" % e, prio = 'crit', print_comp = True)

def modify_syslog_config_file(syslog_id, syslog_configuration_details, authorization_details, user_type):
    """
    Modifying configuration file by adding Loggly configuration text
    """
    comment = "\n#Configuration modified by Loggly Syslog Configuration Script (%s)\n#\n" % datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
    content, modified_syslog_content = syslog_config_file_content(syslog_id, syslog_configuration_details.get("source"), authorization_details)
    command_content = ''
         
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
                        if modified_syslog_content and len(modified_syslog_content) > 0:
                            os.popen("sed -i '/^source/,/};$/c %s' %s" % (modified_syslog_content, default_config_file_name.get(syslog_id)))
                        os.unlink(temp_file.name)
                    else:
                        if modified_syslog_content and len(modified_syslog_content) > 0:
                            command_content = "sed -i '/^source/,/};$/c %s' %s" % (modified_syslog_content, default_config_file_name.get(syslog_id))
                        bash_script_content = "cp -p %s %s \nbash -c 'cat %s >> %s'\n%s" % (default_config_file_name.get(syslog_id), backup_file_name, temp_file.name, default_config_file_name.get(syslog_id), command_content)
                        create_bash_script(bash_script_content)
                    return backup_file_name
                
                elif user_input in no:
                    Logger.printLog("\nPlease add the following lines to the syslog configuration file (%s).\n\n%s%s" % (default_config_file_name.get(syslog_id), comment, content), prio = 'notice', print_comp = True)
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
                        if modified_syslog_content and len(modified_syslog_content) > 0:
                            os.popen("sed -i '/^source/,/};/c %s' %s" % (modified_syslog_content, default_config_file_name.get(syslog_id)))
                    else:
                        if modified_syslog_content and len(modified_syslog_content) > 0:
                            command_content = "sed -i '/^source/,/};$/c %s' %s" % (modified_syslog_content, default_config_file_name.get(syslog_id))
                        bash_script_content = "sed -i '%s' %s\n%s" % (pattern, default_config_file_name.get(syslog_id), command_content)
                        create_bash_script(bash_script_content)
                    return
                elif user_input in no:
                    return
                else:
                    Logger.printLog("Not a valid input. Please retry.", prio = 'warning', print_comp = True)
        printMessage("Aborting")
        sys.exit(-1)
    
    Logger.printLog("Invalid input received after maximum attempts.", prio = 'error', print_comp = True)
    printMessage("Aborting")
    sys.exit(-1)

def send_sighup_to_syslog(syslog_type):
    """
    Sending sighup to syslog daemon
    """
    if PROCESS_ID != -1:
        question = "Do you want the Loggly Syslog Configuration Script to restart (SIGHUP) the syslog daemon. [Yes|No]: "
        for _ in range(0, 5):
            user_input = usr_input(question).lower()
            if len(user_input) > 0:
                if  user_input in yes:
                    output = os.popen("kill -HUP %d" % PROCESS_ID).read()
                    #output = os.popen("/etc/init.d/rsyslog restart").read()
                    Logger.printLog("SIGHUP Sent. %s" % (output))
                    return True
                elif user_input in no:
                    return False
                else:
                    Logger.printLog("Not a valid input. Please retry.", prio = 'warning', print_comp = True)
    else:
        Logger.printLog("Syslog daemon (%s) is not running. Configuration file has been modified, please start %s daemon manually." % (syslog_type, syslog_type), prio = 'warning', print_comp = True)
    return False


def doverify(loggly_user, loggly_password, loggly_subdomain):
    """
    Send test message to loggly server using logger and search this message to verify whether message is received or not.    
    """    
    Logger.printLog("Sending a test message using logger.")
    unique_string = str(uuid.uuid4()).replace("-","")
    dummy_message = "Testing that your log messages can make it to Loggly! %s" % unique_string
    Logger.printLog("Sending message (%s) to Loggly server (%s)" % (dummy_message, LOGGLY_SYSLOG_SERVER))
    os.popen("logger -p INFO '%s'" % dummy_message).read()
    search_url = REST_URL_GET_SEARCH_ID % (loggly_subdomain, unique_string)
    # Implement REST APIs to search if dummy message has been sent.
    wait_time = 0
    while wait_time < VERIFICATION_SLEEP_INTERAVAL:
        Logger.printLog("Sending search request. %s" % search_url)
        data = get_json_data(search_url, loggly_user, loggly_password)
        rsid = data["rsid"]["id"]
        search_result_url = REST_URL_GET_SEARCH_RESULT % (loggly_user, rsid)
        Logger.printLog("Sending search result request. %s" % search_result_url)
        data = get_json_data(search_result_url, loggly_user, loggly_password)
        total_events = data["total_events"]
        if total_events >= 1:
            Logger.printLog("******* Congratulations! Loggly is configured successfully.", print_comp = True)
            break
        wait_time += VERIFICATION_SLEEP_INTERAVAL_PER_ITERATION
        time.sleep(VERIFICATION_SLEEP_INTERAVAL_PER_ITERATION)
    if wait_time >= VERIFICATION_SLEEP_INTERAVAL:
        Logger.printLog("!!!!!! Loggly verification failed. Please contact support@loggly.com for more information.", prio = 'crit', print_comp = True)


def write_env_details(current_environment):
    """
    Write environment information to a file
    """
    try:
        file_path = os.path.join(os.getcwd(), LOGGLY_ENV_DETAILS_FILE)
        env_file = open(file_path, "w")
        env_file.write(os.popen("uname -a").read())
        env_file.write("Operating System: %s" % (current_environment['operating_system']))
        env_file.write("\nSyslog versions:\n")
        if len(current_environment['syslog_versions']) > 0:
            for index in range(0, len(current_environment['syslog_versions'])):
                env_file.write("\t%d.   %s(%s)" % (index + 1, current_environment['syslog_versions'][index][0], current_environment['syslog_versions'][index][1]))
        else:
            env_file.write("\tNo Syslog version Found......")

        env_file.close()
        Logger.printLog("Created environment details file at %s, please forward it to support@loggly.com" % file_path, print_comp = True)
        printEnvironment(current_environment)
    except Exception as e:
        Logger.printLog("Error %s" % e, prio = 'error', print_comp = True)
        sys_exit(reason = "Error %s" % e)

def version_compatibility_check(minimum_version):
    """
    Checks for compatible Python version.
    """
    sys_version = ".".join(map(str, sys.version_info[:2]))
    if sys_version < minimum_version:
        Logger.printLog('Python version check fails: Installed version is ' + sys_version + '. Minimum required version is ' + str(minimum_version), prio = 'crit', print_comp = True)
        sys_exit(reason = 'Python version check fails: Installed version is ' + sys_version + '. Minimum required version is ' + str(minimum_version))
    Logger.printLog('Python version check successful: Installed version is ' + sys_version + '. Minimum required version is ' + str(minimum_version))

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
    vals['timestamp'] = datetime.isoformat(datetime.now())
    vals['hostname'] = socket.gethostname()
    vals['app-name'] = OUR_PROGNAME
    vals['procid'] = os.getpid()
    vals['msgid'] = '-'
    vals['loggly-auth-token'] = LOGGLY_AUTH_TOKEN
    vals['loggly-pen'] = LOGGLY_PEN
    vals['msg'] = msg

    fullmsg = ("<%(pri)s>%(version)s %(timestamp)s %(hostname)s %(app-name)s %(procid)s %(msgid)s "
               "[%(loggly-auth-token)s@%(loggly-pen)s] %(msg)s") % vals

    if not _LOG_SOCKET:  # first time only...
        _LOG_SOCKET = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    _LOG_SOCKET.sendto(fullmsg, (LOGGLY_LOG_HOST, LOGGLY_UDP_PORT))

def perform_sanity_check_and_get_product_for_configuration(current_environment, check_syslog_service = True):
    printEnvironment(current_environment)
    perform_sanity_check(current_environment)
    syslog_name_for_configuration = product_for_configuration(current_environment, check_syslog_service = check_syslog_service)
    current_environment['syslog_name_for_configuration'] = syslog_name_for_configuration
    return syslog_name_for_configuration

def install(current_environment):
    Logger.printLog('Installation started', prio = 'debug')
    # 1. Determine user type.
    user_type = get_user_type()
    # 2. Determine the environment in which it was invoked (i.e. which distro, release, and syslog daemon has been deployed)
    syslog_name_for_configuration = perform_sanity_check_and_get_product_for_configuration(current_environment)
    loggly_user, loggly_password, loggly_subdomain = login()
    authorization_details = get_auth_token(loggly_user, loggly_password, loggly_subdomain)
    # 4. If possible, determine the location of the syslog.conf file or the syslog.conf.d/ directory.
    # Provide the location as the default and prompt the user for confirmation.
    
    # 5. Create custom configuration file and place it in configuration directory path ($IncludeConfig), default path for rsyslog will be /etc/rsyslog.d/
    write_configuration(syslog_name_for_configuration, authorization_details, user_type)    

    # 6. SIGHUP the syslog daemon.
    send_sighup_to_syslog(syslog_name_for_configuration)
    doverify(loggly_user, loggly_password, loggly_subdomain)
    Logger.printLog('Installation completed', prio = 'debug')
    return syslog_name_for_configuration
    
def verify(current_environment):
    Logger.printLog('Verification started', prio = 'debug')
    perform_sanity_check_and_get_product_for_configuration(current_environment)
    loggly_user, loggly_password, loggly_subdomain = login()
    doverify(loggly_user, loggly_password, loggly_subdomain)
    Logger.printLog('Verification completed', prio = 'debug')

def uninstall(current_environment):
    Logger.printLog('Uninstall started', prio = 'debug')
    user_type = get_user_type()
    if user_type == NON_ROOT_USER:
        Logger.printLog("Current user in not root user", prio = 'warning', print_comp = True)
        sys.exit()
    #No need to check syslog service for uninstall
    syslog_name_for_configuration = perform_sanity_check_and_get_product_for_configuration(current_environment, check_syslog_service = False)
    remove_configuration(syslog_name_for_configuration)
    send_sighup_to_syslog(syslog_name_for_configuration)
    Logger.printLog('Uninstall completed', prio = 'debug')

def dryrun(current_environment):
    Logger.printLog('Dryrun started', prio = 'debug')
    user_type = get_user_type()
    if user_type == NON_ROOT_USER:
        Logger.printLog("Current user in not root user", prio = 'warning', print_comp = True)
        sys.exit()
    syslog_name_for_configuration = install(current_environment)
    remove_configuration(syslog_name_for_configuration)
    send_sighup_to_syslog(syslog_name_for_configuration)
    Logger.printLog('Dryrun completed', prio = 'debug')

def loggly_help():
    print(LOGGLY_HELP)

def parseOptions():
    """
    Parse command line argument
    """
    usage = "usage: %prog [option]\n"
    usage += "Options:\n"
    usage += "\t-i|--install      Configure the syslog\n"
    usage += "\t-u|--uninstall    Remove the changes made by the syslog configuration script\n"
    usage += "\t-v|--verify       Verify the configuration explicitly\n"
    usage += "\t-s|--sysinfo      Print, write system information\n"
    usage += "\t-l|--loggly_help  Guideline for users for each step to configure syslog\n"
    usage += "\t-p|--verbose      Print detailed logs on console\n"
    usage += "\t-d|--dryrun       Perform configuration steps without modifying anything\n"
    
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
    options = vars(parseOptions())
    Logger.is_printLog = options['verbose']
    version_compatibility_check(MINIMUM_SUPPORTED_PYTHON_VERSION)

    if options['help']:
        loggly_help()
        sys.exit()
        
    current_environment = get_environment_details()
    data = json.dumps({"operating_system": current_environment['operating_system'], "syslog_versions": current_environment['syslog_versions']})
    sendEnvironment(data)                     
    
    if options['sysinfo']:
        write_env_details(current_environment)

    elif options['uninstall']:
        uninstall(current_environment)
        
    elif options['install']:
        install(current_environment)

    elif options['verify']:
        verify(current_environment)

    elif options['dryrun']:
        dryrun(current_environment) 

    printMessage("Finished")

if __name__ == "__main__":

    try:
        main()
    except KeyboardInterrupt:
        Logger.printLog('KeyboardInterrupt', prio = 'error')

        
