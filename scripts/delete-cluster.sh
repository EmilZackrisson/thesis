#!/usr/bin/env bash

sudo kubeadm reset -f --cri-socket="unix:///var/run/crio/crio.sock"
sudo rm -rf /etc/cni/net.d
docker run --privileged --rm registry.k8s.io/kube-proxy:v1.35.0 sh -c "kube-proxy --cleanup && echo DONE"
sudo ip link delete cni0
sudo ip link delete flannel.1   # if exists
sudo rm -rf /var/lib/cni/

echo "Removing all Kube iptable rules"
for i in `sudo iptables -L |grep KUBE|awk '{print $2}'`; do sudo iptables -F $i && sudo iptables -X $i; done
