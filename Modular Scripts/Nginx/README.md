Nginx Script
=============

Configure your Nginx server to send logs from access file and error file to Loggly

    sudo bash configure-nginx.sh -a SUBDOMAIN -u USERNAME
    
Stop sending your Nginx logs to Loggly

    sudo bash configure-nginx.sh -a SUBDOMAIN -r
