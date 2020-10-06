#!/bin/bash

# Greengrass installation script
# General Updates
# sudo apt-get -y update
# sudo apt-get -y upgrade

# greengrass dependencies
sudo adduser --system ggc_user
sudo addgroup --system ggc_group || sudo groupadd --system ggc_group

if test -f "/boot/cmdline.txt"; then
  sudo bash -c 'echo " cgroup_enable=memory cgroup_memory=1" >> /boot/cmdline.txt'
  sudo sed -i '$ s/$/ cgroup_enable=memory cgroup_memory=1/' /boot/cmdline.txt
fi


# Install greengrass
ggVersion="https://d1onfpft10uf5o.cloudfront.net/greengrass-core/downloads/1.10.0/greengrass-linux-armv7l-1.10.0.tar.gz"
myUser="pi"
if hostnamectl | grep "arm64"; then 
    ggVersion="https://d1onfpft10uf5o.cloudfront.net/greengrass-core/downloads/1.10.0/greengrass-linux-aarch64-1.10.0.tar.gz"
    myUser="jetson"
fi

sudo wget -O /greengrass.tar.gz $ggVersion
sudo tar -C / -xvf /greengrass.tar.gz
sudo rm /greengrass.tar.gz
sudo wget -O /greengrass/certs/root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem
