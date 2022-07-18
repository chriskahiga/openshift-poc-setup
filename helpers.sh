replace_yaml_variables() {
    case $1 in
    HELPER_IP) yq '.helper.ipaddr = strenv(myenv) | .helper.ipaddr style="double"' vars/main.yml;;
    NETWORK_INTERFACE) yq '.helper.networifacename = strenv(myenv) | .helper.networifacename style="double"' vars/main.yml;;
    BOOTSTRAP_IP) myenv=$2 yq '.bootstrap.ipaddr = strenv(myenv) | .test style="double"' vars/main.yml;;
    BOOTSTRAP_MAC_ADDRESS) myenv=$2 yq '.bootstrap.macaddr = strenv(myenv) | .test style="double"' vars/main.yml;;
    MASTER_01_IP) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    MASTER_01_MAC_ADDRESS) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    MASTER_02_IP) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    MASTER_02_MAC_ADDRESS) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    MASTER_03_IP) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    MASTER_03_MAC_ADDRESS) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    WORKER_01_IP) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    WORKER_01_MAC_ADDRESS) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    WORKER_02_IP) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    WORKER_02_MAC_ADDRESS) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    BASE_DOMAIN_NAME) myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    DNS_1 myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml;;
    esac
    myenv=$2 yq '.test = strenv(myenv) | .test style="double"' vars/main.yml
}
