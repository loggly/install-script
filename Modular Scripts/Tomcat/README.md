Tomcat Script
=============

Send your Tomcat logs to Loggly

    chmod 755 configure-tomcat.sh
    sudo ./configure-tomcat.sh -a SUBDOMAIN -u USERNAME
    
Stop sending your Tomcat logs to Loggly

    sudo ./configure-tomcat.sh -a SUBDOMAIN -r
