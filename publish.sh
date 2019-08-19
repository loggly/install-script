# Publishes the scripts to Loggly's S3 bucket where they are publically hosted.
# For Loggly's internal use only. Requires keys to publish.

copy_to_aws() {
	aws s3 cp "$1" s3://loggly-install/install/ --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers
}

declare -a files=("Linux Script/configure-linux.sh"
				  "Modular Scripts/File Monitoring/configure-file-monitoring.sh"
				  "Modular Scripts/Apache2/configure-apache.sh"
				  "Modular Scripts/Nginx/configure-nginx.sh"
				  "Modular Scripts/S3Logs Monitoring/configure-s3-file-monitoring.sh"
				  "Modular Scripts/Tomcat/configure-tomcat.sh"
				  "Mac Script/configure-mac.sh"
				  "AWSscripts/SQS3script.py")

for file in "${files[@]}";do
	copy_to_aws "$file"
done
