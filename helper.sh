WORK_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source $WORK_DIR/setup.conf
PROGRESS_FILE=$WORK_DIR/set_progress.sh
LOGFILE=$WORK_DIR/update.log

success_logger() {
    echo -e "\n$@ ....................... SUCCESS" | tee -a $LOGFILE
}
failed_logger() {
    echo -e "\n$@ ....................... FAILED\n" | tee -a $LOGFILE
}
is_variable_empty() {
    [ -z "$1" ] && {
        action_comment="1.Validating Configuration File"
        failed_logger $action_comment
        on_error 1 "$i is not set. Ensure all required values are provided in the setup.conf file before proceeding with setup"
    }
}
valid_ip() {
    ip=$1
    ip_var=$2
    stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 &&
            ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    [ $stat = 1 ] && {
        action_comment="1.Validating Configuration File"
        failed_logger $action_comment
        on_error 1 "'$ip' set for $ip_var is not a valid IP. Please make the necessary modifications and try again"
    }
}
valid_mac() {
    MAC_ADDR=${1^^}
    mac_var=$2
    if [ $(echo $MAC_ADDR | egrep "^([0-9A-F]{2}:){5}[0-9A-F]{2}$") ]; then
        return 0
    else
        action_comment="1.Validating Configuration File"
        failed_logger $action_comment
        on_error 1 "'$1' set for $2 is not a valid MAC ADDRESS. Please make the necessary modifications in the config.sh file and try again"
    fi
}
dns_resolve() {
    RECORD=$1
    #forward resolution
    RESULT=$(dig @${DNS} +short $RECORD)
    [ $? != 0 ] && {
        action_comment="1.Validating Configuration File"
        failed_logger $action_comment
        on_error 1 "\nUnable to resolve $RECORD. Please add $RECORD to DNS server $DNS and its associated IP or check if the correct IP of your DNS Server is configured on this server by running\n\ncat /etc/resolv.conf\n"
    }
    REVERSE=$(dig @${DNS} +short $RESULT)
    [ $? != 0 ] && {
        action_comment="1.Validating Configuration File"
        failed_logger $action_comment
        on_error 1 "\nUnable to perform reverse dns resolution on $RECORD. Please add the associated PTR Record on DNS server $DNS or check if the correct IP of your DNS Server is configured on this server by running\n\ncat /etc/resolv.conf\n"
    }
}
set_progress() {
    sed -i "s/$1=0/$1=OK/g" $WORK_DIR/set_progress.sh
}
reset_progress() {
    sed -i "s/OK/0/g" $WORK_DIR/set_progress.sh
}
