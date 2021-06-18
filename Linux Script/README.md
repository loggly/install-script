# Linux Script

## Configure

Configure your Linux system to send syslogs to Loggly using the following command

```bash
sudo bash configure-linux.sh -a SUBDOMAIN -u USERNAME 
```

You can also pass your *customer token* as `-t TOKEN`. If it's omitted, the token will be loaded automatically.

## Stop

Stop sending your Linux System logs to Loggly

```bash
sudo bash configure-linux.sh -a SUBDOMAIN -r
```
