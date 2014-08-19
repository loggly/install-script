File Monitoring Script
======================

Configure your any text file to send it contents to Loggly

    chmod 755 configure-file-monitoring.sh
    sudo ./configure-file-monitoring.sh -a SUBDOMAIN -u USERNAME -f FILENAME -l FILE_ALIAS
    
**Note:** File Alias should be unique for each file.
  
  
  
Stop sending your file contents to Loggly

    sudo ./configure-file-monitoring.sh -a SUBDOMAIN -l FILE_ALIAS -r
