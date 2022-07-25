#! /bin/bash
WORK_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
CONFIG_FILE=$WORK_DIR/config.sh
source $WORK_DIR/error_handler.sh
source $WORK_DIR/helper.sh
source $WORK_DIR/set_progress.sh
PROGRESS_FILE=$WORK_DIR/set_progress.sh
LOGFILE=$WORK_DIR/update.log
rm -f $LOGFILE && touch $LOGFILE

#VALIDATE AND CONFIRM CONFIGS
if [ $CONFIGS != 'OK' ]; then
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "\nValidating Configuration File ...." | tee $LOGFILE
        source ${CONFIG}
        #Confirm required config file variables are not empty
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
        echo -e "\nSuccessfully validated Configuration File" | tee $LOGFILE

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
        on_error $? "Issue setting up config variables. Check logs at $LOGFILE\n"
        set_progress CONFIG
    fi
    #Check disk device if set else use /dev/sda
    [ -z $DEVICE ] && DEVICE=/dev/sda
    #Generate variable file to be used by ansible playbooks
    cd ocp4_ansible/
    eval "cat << EOF
$(<vars/template.yml)
EOF
" >vars/main.yml
    if [ $PRE_REQS != 'OK']; then
        #Checking pre-requisites
        echo -e "\nChecking pre-requisites ..." | tee $LOGFILE
        echo -e "\nConfirming OS Version .." | tee $LOGFILE
        source /etc/os-release >>$LOGFILE 2>&1
        on_error $? "Could not confirm OS version. Check logs at $LOGFILE\n"
        [ -z "$VERSION" ] && {on_error 1 "Could not confirm OS Version"}
        [[ $VERSION == 8* ]] && echo -e "\nSuccessfully Confirmed OS Version" || on_error 1 "Please run this setup on Red Hat Linux version 8.*.EXITING\n"
        echo -e "\nConfirming Forward and Reverse DNS Resolution" | tee $LOGFILE
        RECORDS=(bootstrap.ocp4.$BASE_DOMAIN_NAME master01.ocp4.$BASE_DOMAIN_NAME master02.ocp4.$BASE_DOMAIN_NAME master01.ocp4.$BASE_DOMAIN_NAME worker01.ocp4.$BASE_DOMAIN_NAME worker02.ocp4.$BASE_DOMAIN_NAME)
        for i in ${RECORDS[@]}; do
            dns_resolve $i
        done
        echo -e "\nSuccessfully Confirmed DNS requirements" | tee $LOGFILE
        echo -e "\nOK\n" >>$LOGFILE
        set_progress PRE_REQS
    fi
    #Begin environment setup
    echo -e "\nSTARTING SETUP OF ENVIRONMENT SERVICES ..." | tee $LOGFILE
    if [ $DHCP != 'OK' ]; then
        echo -e "\nInstalling DHCP .." | tee $LOGFILE
        sudo yum -y remove dhcp-server >>$LOGFILE 2>&1
        sudo yum -y install dhcp-server >>$LOGFILE 2>&1
        sudo systemctl enable dhcpd >>$LOGFILE 2>&1
        sudo mv /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak >>$LOGFILE 2>&1
        on_error $? "Issue installing dhcpd package. Check logs at $LOGFILE"
        echo -e "\nOK\n" >>$LOGFILE

        echo -e "\nSetting up DHCP .." | tee $LOGFILE
        ansible-playbook tasks/configure_dhcpd.yml >>$LOGFILE 2>&1
        on_error $? "Issue setting up DHCP. Check logs at $LOGFILE"
        echo -e "\nSuccessfully installed DHCP" | tee $LOGFILE
        echo -e "\nOK\n" >>$LOGFILE
        set_progress DHCP
    fi
    if [ $TFTP_INSTALL != 'OK' ]; then
        echo -e "\nInstalling TFTP Server .." | tee $LOGFILE
        sudo yum remove -y tftp-server syslinux >>$LOGFILE 2>&1
        sudo yum -y install tftp-server syslinux >>$LOGFILE 2>&1
        sudo firewall-cmd --add-service=tftp --permanent >>$LOGFILE 2>&1
        sudo firewall-cmd --reload >>$LOGFILE 2>&1
        rm -f /etc/systemd/system/helper-tftp.service >>$LOGFILE 2>&1
        cp files/helper-tftp.service /etc/systemd/system/helper-tftp.service >>$LOGFILE 2>&1
        rm -f /usr/local/bin/start-tftp.sh >>$LOGFILE 2>&1
        sudo echo '#!/bin/bash
/usr/bin/systemctl start tftp > /dev/null 2>&1
##
##' >>/usr/local/bin/start-tftp.sh
        sudo chmod a+x /usr/local/bin/start-tftp.sh >>$LOGFILE 2>&1
        sudo systemctl daemon-reload >>$LOGFILE 2>&1
        sudo systemctl enable --now tftp helper-tftp >>$LOGFILE 2>&1
        on_error $? "Issue installing TFTP. Check logs at $LOGFILE"
        echo -e "\nSuccessfully installed TFTP" | tee $LOGFILE
        echo -e "\nOK\n" >>$LOGFILE
        set_progress TFTP_INSTALL
    fi
    sudo rm -rf /var/lib/tftpboot >>$LOGFILE 2>&1
    sudo mkdir -p /var/lib/tftpboot/pxelinux.cfg >>$LOGFILE 2>&1
    sudo cp -rvf /usr/share/syslinux/* /var/lib/tftpboot >>LOGFILE >>$LOGFILE 2>&1
    sudo mkdir -p /var/lib/tftpboot/rhcos >>$LOGFILE 2>&1

    if [ $RHCOS_KERNEL != 'OK' ]; then
        echo -e "\nDownloading RHCOS Kernel and Installer Image. Please wait this might take some time .." | tee $LOGFILE
        wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-installer-kernel-x86_64 >>$LOGFILE 2>&1
        on_error $? "Could not download kernel file. Check logs at $LOGFILE"
        sudo mv rhcos-installer-kernel-x86_64 /var/lib/tftpboot/rhcos/kernel >>$LOGFILE 2>&1
        set_progress RHCOS_KERNEL
    fi
    if [ $RHCOS_INSTALLER != 'OK' ]; then
        wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-installer-initramfs.x86_64.img >>$LOGFILE 2>&1
        on_error $? "Could not download installer image. Check logs at $LOGFILE"
        sudo mv rhcos-installer-initramfs.x86_64.img /var/lib/tftpboot/rhcos/initramfs.img >>$LOGFILE 2>&1
        set_progress RHCOS_INSTALLER
    fi
    sudo restorecon -RFv /var/lib/tftpboot/rhcos >>$LOGFILE 2>&1
    echo -e "\nSuccessfully Downloaded" >>$LOGFILE
    ls /var/lib/tftpboot/rhcos >>$LOGFILE 2>&1
    echo -e "\nOK\n" >>$LOGFILE

    if [ $APACHE != 'OK' ]; then
        echo -e "\nInstalling Apache .." | tee $LOGFILE
        sudo yum -y remove httpd >>$LOGFILE 2>&1
        sudo yum -y install httpd >>$LOGFILE 2>&1
        on_error $? "Could not install Apache. Check logs at $LOGFILE"
        sed -i 's/Listen 80/Listen 8080/g' /etc/httpd/conf/httpd.conf >>$LOGFILE 2>&1
        systemctl enable --now httpd >>$LOGFILE 2>&1
        sudo firewall-cmd --add-port=8080/tcp --permanent >>$LOGFILE 2>&1
        sudo firewall-cmd --reload >>$LOGFILE 2>&1
        sudo mkdir -p /var/www/html/rhcos >>$LOGFILE 2>&1
        if [ $RHCOS_ROOTFS != 'OK' ]; then
            echo -e "\nDownloading Red HatCoreOSroofs image. This might take some time .." | tee $LOGFILE
            wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-live-rootfs.x86_64.img >>$LOGFILE 2>&1
            on_error $? "Could not download Red Hat CoreOSrootfs image. Check logs at $LOGFILE"
            echo -e "\nRed Hat CoreOSrootfs image donwloaded" | tee $LOGFILE
            sudo mv rhcos-live-rootfs.x86_64.img /var/www/html/rhcos/rootfs.img >>$LOGFILE 2>&1
            sudo restorecon -RFv /var/www/html/rhcos >>$LOGFILE 2>&1
            set_progress RHCOS_ROOTFS
        fi
        echo -e "\nSuccessfully setup Apache" | tee $LOGFILE
        echo -e "\nOK\n" >>$LOGFILE
        set_progress APACHE
    fi
    if [ $TFTP_SETUP != 'OK' ]; then
        echo -e "\nConfiguring TFTP Server .." | tee $LOGFILE
        ansible-playbook tasks/configure_tftp_pxe.yml >>$LOGFILE 2>&1
        on_error $? "Issue Setting up TFTP Server. Check logs at $LOGFILE"
        echo -e "\nSuccessfully setup TFTP" | tee $LOGFILE
        set_progress TFTP_SETUP
    fi
    if [ $HAPROXY != 'OK' ]; then
        echo -e "\nInstalling HAProxy .." | tee $LOGFILE
        sudo yum remove -y haproxy >>$LOGFILE 2>&1
        sudo yum install -y haproxy >>$LOGFILE 2>&1
        on_error $? "Issue Installing HAProxy. Check logs at $LOGFILE"
        sudo setsebool -P haproxy_connect_any 1 >>$LOGFILE 2>&1
        sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.default >>$LOGFILE 2>&1

        echo -e "\nConfiguring HAProxy .." | tee $LOGFILE
        ansible-playbook tasks/configure_haproxy_lb.yml >>$LOGFILE 2>&1
        on_error $? "Issue Configuring HAProxy. Check logs at $LOGFILE"
        sudo semanage port -a 6443 -t http_port_t -p tcp >>$LOGFILE 2>&1
        sudo semanage port -a 22623 -t http_port_t -p tcp >>$LOGFILE 2>&1
        sudo semanage port -a 32700 -t http_port_t -p tcp >>$LOGFILE 2>&1
        #on_error $? "Issue Configuring HAProxy. Check logs at $LOGFILE"
        sudo firewall-cmd --add-service={http,https} --permanent >>$LOGFILE 2>&1
        sudo firewall-cmd --add-port={6443,22623}/tcp --permanent >>$LOGFILE 2>&1
        sudo firewall-cmd --reload >>$LOGFILE 2>&1
        echo -e "\nSuccessfully setup HAProxy" | tee $LOGFILE
        echo -e "\nOK\n" >>$LOGFILE
        set_progress HAPROXY
    fi
    echo -e "\nEnvironment Setup Successful" | tee $LOGFILE

    if [ $OPENSHIFT_CLIENTS != 'OK' ]; then
        echo -e "\nDownloading openshift-install, client binaries and generating SSH Keys .." | tee $LOGFILE
        echo -e "\nDownloading openshift client binaries" >>$LOGFILE
        rm -f openshift-client-linux.tar.gz >>$LOGFILE 2>&1
        wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz >>$LOGFILE 2>&1
        on_error $? "Could not download openshift client binaries. Check logs at $LOGFILE"
        tar xvf openshift-client-linux.tar.gz >>$LOGFILE 2>&1
        sudo rm -f /usr/local/bin/oc && sudo rm -f /usr/local/bin/kubectl >>$LOGFILE 2>&1
        sudo mv oc kubectl /usr/local/bin >>$LOGFILE 2>&1
        rm -f README.md LICENSE openshift-client-linux.tar.gz >>$LOGFILE 2>&1
        echo -e "Successfully downloaded and installed openshshift client libraries" | tee $LOGFILE
        echo -e "\nOK\n" >>$LOGFILE
        set_progress OPENSHIFT_CLIENTS
    fi

    if [ $OCP_INSTALLER != "OK" ]; then
        echo -e "\nDownloading openshift install" | tee $LOGFILE
        rm -f openshift-install-linux.tar.gz >>$LOGFILE 2>&1
        wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz >>$LOGFILE 2>&1
        on_error $? "Could not download openshift-nstall. Check logs at $LOGFILE"
        tar xvf openshift-install-linux.tar.gz >>$LOGFILE 2>&1
        sudo rm -f /usr/local/bin/openshift-install >>$LOGFILE 2>&1
        sudo mv openshift-install /usr/local/bin >>$LOGFILE 2>&1
        rm -f README.md LICENSE openshift-install-linux.tar.gz >>$LOGFILE 2>&1
        echo -e "Successfully donwloaded and installed openshift-install" | tee $LOGFILE
        set_progress OCP_INSTALLER
    fi

    if [ $OCP_FILES != "OK" ]; then
        echo -e "Generating SSH Keys" | tee $LOGFILE
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa <<<y >>$LOGFILE 2>&1
        on_error $? "Could not generate SSH Keys. Check logs at $LOGFILE"
        echo -e "SSH keys generated" | tee $LOGFILE

        echo -e "\nPreparing to generate ignition files.." | tee $LOGFILE
        echo -e "Getting pull secret" | tee $LOGFILE
        source files/secret.sh >>$LOGFILE 2>&1

        rm -rf ~/ocp4 && mkdir -p ~/ocp4 >>$LOGFILE 2>&1
        eval "cat << EOF
$(<files/install-config-base.yaml)
EOF
" >~/ocp4/install-config.yaml
        echo -e "Creating Manifest Files" | tee $LOGFILE
        openshift-install --dir ~/ocp4 create manifests >>$LOGFILE 2>&1
        on_error $? "\nUnable to create manifest files. Check logs at $LOGFILE" | tee $LOGFILE
        #Disabling pod scheduling on masters >>$LOGFILE 2>&1
        sed -i 's/true/false/' ~/ocp4/manifests/cluster-scheduler-02-config.yml >>$LOGFILE 2>&1
        echo -e "Creating Ignition Files" | tee $LOGFILE
        openshift-install --dir ~/ocp4 create ignition-configs >>$LOGFILE 2>&1
        on_error $? "Unable to create ignition files. Check logs at $LOGFILE"
        echo -e "\nIgnition Files successfully generated" | tee $LOGFILE

        echo -e "\nCopying ignition files to Apache .." | tee $LOGFILE
        sudo rm -rf /var/www/html/ignition && sudo mkdir -p /var/www/html/ignition >>$LOGFILE 2>&1
        sudo cp -v ~/ocp4/*.ign /var/www/html/ignition >>$LOGFILE 2>&1
        sudo chmod 644 /var/www/html/ignition/*.ign >>$LOGFILE 2>&1
        sudo restorecon -RFv /var/www/html/ >>$LOGFILE 2>&1
        set_progress OCP_FILES
    fi

    echo -e "\nConfirming all services are running .." | tee $LOGFILE
    SERVICES=(haproxy dhcpd tftp httpd)
    for i in ${SERVICES[@]}; do
        systemctl enable $i >>$LOGFILE >>$LOGFILE 2>&1
        systemctl is-active --quiet $i >>$LOGFILE 2>&1
        if [ "$?" != 0 ]; then
            systemctl restart $i >>$LOGFILE >>$LOGFILE 2>&1
            systemctl is-active --quiet $i >>$LOGFILE 2>&1
            on_error $? "$i is not running and is unable to restart. Check logs at $LOGFILE"
        fi
    done

    echo -e "\nENVIRONMENT SERVICES SETUP SUCCESSFUL\n" | tee $LOGFILE
    reset_progress
else
    echo "Cannot find config file. QUITING" >>$LOGFILE
fi
