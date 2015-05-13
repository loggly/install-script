# Publishes the scripts to Loggly's S3 bucket where they are publically hosted.
# For Loggly's internal use only. Requires keys to publish.

s3cmd put --acl-public Linux\ Script/configure-linux.sh s3://loggly-install/install/
s3cmd put --acl-public Modular\ Scripts/File\ Monitoring/configure-file-monitoring.sh s3://loggly-install/install/
s3cmd put --acl-public Modular\ Scripts/Apache2/configure-apache.sh s3://loggly-install/install/
s3cmd put --acl-public Modular\ Scripts/Nginx/configure-nginx.sh s3://loggly-install/install/
s3cmd put --acl-public Modular\ Scripts/S3Logs\ Monitoring/configure-s3-file-monitoring.sh s3://loggly-install/install/
s3cmd put --acl-public Modular\ Scripts/Tomcat/configure-tomcat.sh s3://loggly-install/install/
s3cmd put --acl-public Mac\ Script/configure-mac.sh s3://loggly-install/install/
