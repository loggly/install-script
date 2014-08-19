Linux Script
============

Configure your Linux system to send syslogs to Loggly using the following command

    chmod 755 configure-linux.sh
    sudo ./configure-linux.sh -a SUBDOMAIN -u USERNAME 
    

Stop sending your Linux System logs to Loggly

    sudo ./configure-linux.sh -a SUBDOMAIN -r
