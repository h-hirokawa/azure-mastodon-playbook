#!/bin/bash

get_os_bit() {
    echo $(uname -m);
}

# Get Linux distribution name
get_os_distribution() {
    if   [ -e /etc/debian_version ] ||
         [ -e /etc/debian_release ]; then
        # Debian
        distri_name="debian"
    elif [ -e /etc/fedora-release ] ||
         [ -e /etc/redhat-release ]; then
        # RedHat
        distri_name="redhat"
    else
        # Other
        echo "unkown distribution"
        distri_name="unkown"
    fi
    echo ${distri_name}
}

dist=$(get_os_distribution)
case ${dist} in
debian)
    sudo apt-get update && sudo apt-get install -y build-essential libssl-dev libffi-dev python-dev curl
    ;;
redhat)
    sudo yum install -y gcc libffi-devel python-devel openssl-devel curl
    ;;
esac

curl -kL https://bootstrap.pypa.io/get-pip.py | sudo python
sudo pip install "ansible<2.4"
