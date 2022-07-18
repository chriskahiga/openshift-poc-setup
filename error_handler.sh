on_error() {
        if [ "$1" -ne 0 ]; then
                [[ ! -z "$2" ]] && echo "$2" || echo "Command Failed"
                exit 1
        fi
}
is_variable_empty() {
        [ -z "$1" ] && {
                on_error 1 "$i is not set. Ensure all required values are provided in the config.sh file before proceeding with setup"
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
                on_error 1 "'$ip' set for $ip_var is not a valid IP. Please make the necessary modifications and try again"
        }
}
valid_mac() {
        MAC_ADDR=${1^^}
        mac_var=$2
        if [ $(echo $MAC_ADDR | egrep "^([0-9A-F]{2}:){5}[0-9A-F]{2}$") ]; then
                return 0
        else
                on_error 1 "'$1' set for $2 is not a valid MAC ADDRESS. Please make the necessary modifications in the config.sh file and try again"
        fi
}
