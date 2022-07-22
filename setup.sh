#! /bin/bash
WORK_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
CONFIG=$WORK_DIR/config.sh
source $WORK_DIR/error_handler.sh
source $WORK_DIR/helper.sh
if [ -f "$CONFIG" ]; then
    echo -e "\nValidating Configuration File ....\n" | tee $LOGFILE
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
    declare -A OTHERS
    OTHERS[BOOTSTRAP_IP]=$BOOTSTRAP_IP
    OTHERS[BOOTSTRAP_MAC_ADDRESS]=$BOOTSTRAP_MAC_ADDRESS
    OTHERS[BASE_DOMAIN_NAME]=$BASE_DOMAIN_NAME
    OTHERS[DNS]=$DNS
    for i in ${!OTHERS[@]}; do
        is_variable_empty ${!i}
        [[ ${i} = *$ip_prefix ]] && valid_ip ${!i} ${i}
        [[ ${i} = *$mac_prefix ]] && valid_mac ${!i} ${i}
    done
    echo -e "Configuration successfully validated\n" | tee $LOGFILE
    #Set additional variables
    HELPER_IP=$(ip route get 8.8.8.8 | awk '{print $7}')
    NETWORK_INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5}')
    GATEWAY=$(ip route get 8.8.8.8 | awk '{print $3}')
    BROADCAST=$(ip addr show | grep -w inet | grep -v 127.0.0.1 | awk '{ print $4}' | head -n 1)
    NETMASK=$(ifconfig | grep -w inet | grep -v 127.0.0.1 | awk '{print $4}' | cut -d ":" -f 2)
    #Calculate Network ID
    IFS=. read -r i1 i2 i3 i4 <<<"$HELPER_IP"
    IFS=. read -r m1 m2 m3 m4 <<<"$NETMASK"
    NET_ID="$((i1 & m1))"."$((i2 & m2))"."$((i3 & m3))"."$((i4 & m4))"
    #Calculate ip range
    LOWER_LIMIT="$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).$(((i4 & m4) + 1))"
    UPPER_LIMIT="$((i1 & m1 | 255 - m1)).$((i2 & m2 | 255 - m2)).$((i3 & m3 | 255 - m3)).$(((i4 & m4 | 255 - m4) - 1))"

    #Check disk device if set else use /dev/sda
    [ -z $DEVICE ] && DEVICE=/dev/sda
    #Generate variable file to be used by ansible playbooks
    cd ocp4_ansible/
    eval "cat << EOF
$(<vars/template.yml)
EOF
" >vars/main.yml

    #Begin environment setup
    LOGFILE=$WORK_DIR/update.log
    rm -f $LOGFILE && touch $LOGFILE
    echo -e "\n STARTING SETUP OF ENVIRONMENT SERVICES ...\n" | tee $LOGFILE
    echo -e "\nInstalling DHCP .." | tee $LOGFILE
    sudo yum -y remove dhcp-server >>$LOGFILE
    sudo yum -y install dhcp-server >>$LOGFILE
    sudo systemctl enable dhcpd >>$LOGFILE
    sudo mv /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak >>$LOGFILE
    on_error $? "Issue installing dhcpd package. Check logs at $LOGFILE"
    echo -e "OK" >>$LOGFILE

    echo -e "\nSetting up DHCP ..\n" | tee $LOGFILE
    ansible-playbook tasks/configure_dhcpd.yml >>$LOGFILE
    on_error $? "Issue setting up DHCP. Check logs at $LOGFILE"
    echo -e "OK" >>$LOGFILE
    echo -e "DHCP Setup Complete\n"

    echo -e "\nInstalling TFTP Server ..\n"
    echo -e "\nInstalling TFTP Server ..\n" >>$LOGFILE
    sudo yum remove -y tftp-server syslinux >>$LOGFILE
    sudo yum -y install tftp-server syslinux >>$LOGFILE
    sudo firewall-cmd --add-service=tftp --permanent
    sudo firewall-cmd --reload
    rm -f /etc/systemd/system/helper-tftp.service >>$LOGFILE
    cp files/helper-tftp.service /etc/systemd/system/helper-tftp.service >>$LOGFILE
    rm -f /usr/local/bin/start-tftp.sh >>$LOGFILE
    sudo echo '#!/bin/bash
/usr/bin/systemctl start tftp > /dev/null 2>&1
##
##' >>/usr/local/bin/start-tftp.sh
    sudo chmod a+x /usr/local/bin/start-tftp.sh
    sudo systemctl daemon-reload
    sudo systemctl enable --now tftp helper-tftp
    on_error $? "Issue installing TFTP. Check logs at $LOGFILE"
    echo -e "\nTFTP Installed\n"
    echo -e "OK" >>$LOGFILE

    sudo rm -rf /var/lib/tftpboot >>$LOGFILE
    sudo mkdir -p /var/lib/tftpboot/pxelinux.cfg
    sudo cp -rvf /usr/share/syslinux/* /var/lib/tftpboot >>LOGFILE
    sudo mkdir -p /var/lib/tftpboot/rhcos

    echo -e "\nDownloading Required Files ..\n" | tee $LOGFILE
    wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-installer-kernel-x86_64 >>$LOGFILE
    on_error $? "Could not download kernel file. Check logs at $LOGFILE"
    sudo mv rhcos-installer-kernel-x86_64 /var/lib/tftpboot/rhcos/kernel
    wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-installer-initramfs.x86_64.img >>$LOGFILE
    on_error $? "Could not download installer image. Check logs at $LOGFILE"
    sudo mv rhcos-installer-initramfs.x86_64.img /var/lib/tftpboot/rhcos/initramfs.img
    sudo restorecon -RFv /var/lib/tftpboot/rhcos
    echo -e "\nFiles Successfully Downloaded"
    ls /var/lib/tftpboot/rhcos
    echo -e "OK" >>$LOGFILE

    echo -e "\nInstalling Apache ..\n" | tee $LOGFILE
    sudo yum -y remove httpd >>$LOGFILE
    sudo yum -y install httpd >>$LOGFILE
    on_error $? "Could not install Apache. Check logs at $LOGFILE"
    sed -i 's/Listen 80/Listen 8080/g' /etc/httpd/conf/httpd.conf
    systemctl enable --now httpd
    sudo firewall-cmd --add-port=8080/tcp --permanent
    sudo firewall-cmd --reload
    sudo mkdir -p /var/www/html/rhcos
    echo -e "\nDownloading Red HatCoreOSroofs image. This might take some time ..\n"
    wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-live-rootfs.x86_64.img >>$LOGFILE
    on_error $? "Could not download Red Hat CoreOSrootfs image. Check logs at $LOGFILE"
    sudo mv rhcos-live-rootfs.x86_64.img /var/www/html/rhcos/rootfs.img
    sudo restorecon -RFv /var/www/html/rhcos
    echo -e "\nApache Setup Complete\n"
    echo -e "OK" >>$LOGFILE

    echo -e "\nConfiguring TFTP Server ..\n" | tee $LOGFILE
    ansible-playbook tasks/configure_tftp_pxe.yml >>$LOGFILE
    on_error $? "Issue Setting up TFTP Server. Check logs at $LOGFILE"
    echo -e "\nTFTP Setup Complete\n"

    echo -e "\nInstalling HAProxy ..\n"
    echo -e "\nInstalling HAProxy ..\n" >>$LOGFILE
    sudo yum remove -y haproxy >>$LOGFILE
    sudo yum install -y haproxy >>$LOGFILE
    on_error $? "Issue Installing HAProxy. Check logs at $LOGFILE"
    sudo setsebool -P haproxy_connect_any 1
    sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.default

    echo -e "\nConfiguring HAProxy ..\n" | tee $LOGFILE
    ansible-playbook tasks/configure_haproxy_lb.yml >>$LOGFILE
    on_error $? "Issue Configuring HAProxy. Check logs at $LOGFILE"
    sudo semanage port -a 6443 -t http_port_t -p tcp >>$LOGFILE
    sudo semanage port -a 22623 -t http_port_t -p tcp >>$LOGFILE
    sudo semanage port -a 32700 -t http_port_t -p tcp >>$LOGFILE
    #on_error $? "Issue Configuring HAProxy. Check logs at $LOGFILE"
    sudo firewall-cmd --add-service={http,https} --permanent
    sudo firewall-cmd --add-port={6443,22623}/tcp --permanent
    sudo firewall-cmd --reload
    echo -e "\nHAProxy Setup Complete\n"
    echo -e "OK" >>$LOGFILE
    echo -e "\nEnvironment Setup Complete\n"

    echo -e "\nConfirming Forward and Reverse DNS Resolution\n"
    RECORDS=(bootstrap.ocp4.$BASE_DOMAIN_NAME master01.ocp4.$BASE_DOMAIN_NAME master02.ocp4.$BASE_DOMAIN_NAME master01.ocp4.$BASE_DOMAIN_NAME worker01.ocp4.$BASE_DOMAIN_NAME worker02.ocp4.$BASE_DOMAIN_NAME)
    for i in ${RECORDS[@]}; do
        dns_resolve $i
    done
    echo -e "\nDNS Requirements Successfully Confirmed\n"
    echo -e "OK" >>$LOGFILE

    echo -e "\nDownloading openshift-install, client binaries and generating SSH Keys ..\n"
    echo -e "\nDownloading openshift client binaries"
    rm -f openshift-client-linux.tar.gz >>$LOGFILE
    wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz >>$LOGFILE
    on_error $? "Could not download openshift client binaries. Check logs at $LOGFILE"
    tar xvf openshift-client-linux.tar.gz >>$LOGFILE
    sudo rm -f /usr/local/bin/oc && sudo rm -f /usr/local/bin/kubectl >>$LOGFILE
    sudo mv oc kubectl /usr/local/bin
    rm -f README.md LICENSE openshift-client-linux.tar.gz >>$LOGFILE
    echo -e "openshift client binaries downloaded and installed\n" | tee $LOGFILE
    echo -e "OK" | tee $LOGFILE

    echo -e "Downloading openshift install\n" | tee $LOGFILE
    rm -f openshift-install-linux.tar.gz >>$LOGFILE
    wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz >>$LOGFILE
    on_error $? "Could not download openshift install. Check logs at $LOGFILE"
    tar xvf openshift-install-linux.tar.gz >>$LOGFILE
    sudo rm -f /usr/local/bin/openshift-install >>$LOGFILE
    sudo mv openshift-install /usr/local/bin
    rm -f README.md LICENSE openshift-install-linux.tar.gz
    echo -e "openshift install downloaded and installed\n" | tee $LOGFILE

    echo -e "Generating SSH Keys\n" | tee $LOGFILE
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa <<<y >>$LOGFILE
    on_error $? "Could not generate SSH Keys. Check logs at $LOGFILE"
    echo -e "SSH keys generated\n" | tee $LOGFILE

    echo -e "\nPreparing to generate ignition files..\n" | tee $LOGFILE
    echo -e "Getting pull secret\n" | tee $LOGFILE
    source files/secret.sh

    rm -rf ~/ocp4 && mkdir -p ~/ocp4 >>$LOGFILE
    eval "cat << EOF
$(<files/install-config-base.yaml)
EOF
" >~/ocp4/install-config.yaml
    echo -e "Creating Manifest Files\n" | tee $LOGFILE
    openshift-install --dir ~/ocp4 create manifests >>$LOGFILE
    on_error $? "\nUnable to create manifest files. Check logs at $LOGFILE\n"
    #Disabling pod scheduling on masters
    sed -i 's/true/false/' manifests/cluster-scheduler-02-config.yml
    echo -e "Creating Ignition Files\n" | tee $LOGFILE
    openshift-install --dir ~/ocp4 create ignition-configs >>$LOGFILE
    on_error $? "Unable to create ignition files. Check logs at $LOGFILE"
    echo -e "\nIgnition Files successfully generated" | tee $LOGFILE

    echo -e "\nCopying ignition files to Apache ..\n"
    sudo rm -rf /var/www/html/ignition && sudo mkdir -p /var/www/html/ignition >>$LOGFILE
    sudo cp -v ~/ocp4/*.ign /var/www/html/ignition
    sudo chmod 644 /var/www/html/ignition/*.ign
    sudo restorecon -RFv /var/www/html/

    echo -e "\nConfirming all services are running ..\n" | tee $LOGFILE
    SERVICES=(haproxy dhcpd tftp httpd)
    for i in ${SERVICES[@]}; do
        systemctl enable $i >> $LOGFILE
        systemctl is-active --quiet $i
        if [ "$?" -ne 0 ]; then
                systemctl restart $i >> $LOGFILE
                systemctl is-active --quiet $i
                on_error $? "$i is not running and is unable to restart. Check logs at $LOGFILE"
        fi
    done

    echo -e "\nENVIRONMENT SERVICES SETUP COMPLETE. PROCEED TO START INSTALLATION\n"

else

    echo "Cannot find config file. QUITING"
fi
