AWS S3 File Monitoring Script
======================

Configure your S3 bucket and file logs to send to Loggly with synchronization

    sudo bash configure-s3-file-monitoring.sh -a SUBDOMAIN -u USERNAME -s3url S3-BUCKET-PATH -s3l S3-BUCKET-ALIAS 
    
**Note:** S3 Bucket Alias should be unique for each file.
  
  
  
Stop sending your S3 bucket logs to Loggly

    sudo ./configure-s3-file-monitoring.sh -a SUBDOMAIN -s3l S3-BUCKET-ALIAS -r
