source config.sh

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
dns_resolve() {
    RECORD=$1
    #forward resolution
    RESULT=$(dig @${DNS} +short $RECORD)
    [ -z "$RESULT" ] && {
        on_error 1 "\nUnable to resolve $RECORD. Please add $RECORD DNS server $DNS and its associated IP or check if the DNS server is configured on this server by running\n\ncat /etc/resolv.conf\n"
    }
    REVERSE=$(dig @${DNS} +short $RECORD)
    [ -z "$REVERSE" ] && {
        on_error 1 "\nUnable to perform reverse dns resolution on $RECORD. Please add the associated PTR Record on DNS server $DNS or check if the DNS server is configured on this server by running\n\ncat /etc/resolv.conf\n"
    }
}