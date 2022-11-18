# OpenShift POC Setup (Beta)
### Requirements:
- Run these scripts on CENTOS\ORACLE LINUX\RHEL 8 Server
- Must be logged in and ran as root user
- Ensure subscribed(RHEL 8) and repos are enabled

### Steps:
- Upload/Download the zipped folder to the root directory 
- Create new folder and unzip into it
  ```
  # mkdir openshift-poc-setup
  # mv openshift-poc-setup.zip openshift-poc-setup
  # cd openshift-poc-setup && unzip openshift-poc-setup.zip
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
