#!/usr/bin/env bash

sudo kubeadm reset -f
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo ip link delete cni0
sudo ip link delete flannel.1   # if exists
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/cni/

echo "Removing all Calico iptable rules"
for i in `iptables -L |grep cali|awk '{print $2}'`; do iptables -F $i && iptables -X $i; done
