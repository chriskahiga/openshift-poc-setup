# OpenShift POC Setup Script (Beta)
### Requirements:
- Run these scripts on either a CENTOS\ORACLE LINUX\RHEL 8 bastion Server
- Must be logged in and ran as root user
- Ensure subscribed(RHEL 8) and repos are enabled

### Steps:
- Clone the repository to your working directory and CD into it
  ```
  # git clone https://github.com/chriskahiga/openshift-poc-setup.git
  # cd openshift-poc-setup
  ```
- Make the contents executable
  ```
  # chmod +x -R *
  ```
- Edit the setup.conf file and set the variables as described by the comments
  ```
  # vim setup.conf
  ```
- Run the script and monitor progress on the console
  ```
  # ./env_setup
  ```
- Logs will be created on the update.log file for any troubleshooting check this log file in the directory you ran the script
