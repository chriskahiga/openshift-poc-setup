#! /bin/bash
WORK_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source $WORK_DIR/error_handler.sh
if [ -f "$CONFIG" ]; then
    source ${CONFIG}
    #Confirm required user declared variables are not empty
    ip_prefix='_IP'
    mac_prefix='_MAC_ADDRESS'
    num=0
    for i in ${!MASTER_*}; do
        is_variable_empty ${!i}
        [[ ${i} = *$ip_prefix ]] && valid_ip ${!i} ${i}
        [[ ${i} = *$mac_prefix ]] && valid_mac ${!i} ${i}
        let num=num+1
    done
    [ $num -lt 6 ] && { on_error 1 "Ensure at least 3 master ips and their respective mac addresses are defined"; }
    let num=0
    for i in ${!WORKER_*}; do
        is_variable_empty ${!i}
        [[ ${i} = *$ip_prefix ]] && valid_ip ${!i} ${i}
        [[ ${i} = *$mac_prefix ]] && valid_mac ${!i} ${i}
    done
    for i in ${!DNS*}; do
        is_variable_empty ${!i}
        valid_ip ${!i} ${i}
    done
    declare -A OTHERS
    OTHERS[BOOTSTRAP_IP]=$BOOTSTRAP_IP
    OTHERS[BOOTSTRAP_MAC_ADDRESS]=$BOOTSTRAP_MAC_ADDRESS
    OTHERS[BASE_DOMAIN_NAME]=$BASE_DOMAIN_NAME
    for i in ${!OTHERS[@]}; do
        is_variable_empty ${!i}
        [[ ${i} = *$ip_prefix ]] && valid_ip ${!i} ${i}
        [[ ${i} = *$mac_prefix ]] && valid_mac ${!i} ${i}
    done
    #Set additional variables
    HELPER_IP=$(ip route get 8.8.8.8 | awk '{print $7}')
    NETWORK_INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5}')
    GATEWAY=$(ip route get 8.8.8.8 | awk '{print $3}')
    BROADCAST=$(ip addr show | grep -w inet | grep -v 127.0.0.1 | awk '{ print $4}' | head -n 1)
    NETMASK=$(ifconfig | grep -w inet | grep -v 127.0.0.1 | awk '{print $4}' | cut -d ":" -f 2)
    #Calculate Network ID
    IFS=. read -r i1 i2 i3 i4 <<<"$(ip route get 8.8.8.8 | awk '{print $7}')"
    IFS=. read -r m1 m2 m3 m4 <<<"$(ifconfig | grep -w inet | grep -v 127.0.0.1 | awk '{print $4}' | cut -d ":" -f 2)"
    NET_ID="$((i1 & m1))"."$((i2 & m2))"."$((i3 & m3))"."$((i4 & m4))"

    #Create variable file to be used by ansible playbooks
    cd ocp4_ansible/
    eval "cat << EOF
    $(<vars/template.yml)
    EOF
    " >vars/main.yml

else
    echo "Cannot find config file. QUITING"
fi
