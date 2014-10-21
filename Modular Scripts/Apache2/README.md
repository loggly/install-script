Apache Script
=============

Configure your Apache server to send logs from access file and error file to Loggly

    sudo bash configure-apache.sh -a SUBDOMAIN -u USERNAME
    
Stop sending your Apache logs to Loggly

    sudo bash configure-apache.sh -a SUBDOMAIN -r
