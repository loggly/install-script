Apache Script
=============

Configure your Apache server to send logs from access file and error file to Loggly

    chmod 755 configure-apache.sh
    sudo ./configure-apache -a SUBDOMAIN -u USERNAME
    
Stop sending your Apache logs to Loggly

    sudo ./configure-apache.sh -a SUBDOMAIN -r
