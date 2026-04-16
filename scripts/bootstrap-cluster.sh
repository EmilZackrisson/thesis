#!/usr/bin/env bash

set -e

calico_version="v3.31.4"
dataplane=$1

echo "Dataplane selected: $1"

if [[ "$dataplane" != "iptables" && "$dataplane" != "ebpf" ]]; then
    echo "Dataplane must be iptables or ebpf"
    exit 1
fi

echo "Running kubeadm init"
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket="unix:///var/run/crio/crio.sock"

echo "Copying kubeconfig"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "Installing Calico Operator and CRDs"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests/tigera-operator.yaml

if [ $dataplane == "iptables" ] ; then
    echo "Installing iptables dataplane"
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests/custom-resources.yaml
elif [ $dataplane == "ebpf" ] ; then
    echo "Installing ebpf dataplane"
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/${calico_version}/manifests/custom-resources-bpf.yaml

    echo "Sleeping for 10 seconds waiting for all CRDs and configs to be created"
    sleep 10

    echo "Applying Felix config to use vlan-1111 interface as a workaround"
    kubectl patch felixconfiguration default --type merge -p '{"spec":{"bpfDataIfacePattern":"^vlan-1111$"}}'
    echo "Sleeping for 5 seconds before restarting calico-node pod"
    sleep 5
    kubectl delete pod -n kube-system -l k8s-app=calico-node
else 
    echo "No valid dataplane selected"
    exit 1
fi

set -euo pipefail

MAX_RETRIES=60
DELAY=10

for ((i=1; i<=MAX_RETRIES; i++)); do
  if kubectl get tigerastatus -o json | jq -e '
    .items
    | length > 0
    and all(
      .[];
      . as $ts
      | ($ts.status.conditions // []) as $conds
      | (
          ($conds | map(select(.type=="Available"))   | length == 1 and .[0].status == "True")
          and
          ($conds | map(select(.type=="Degraded"))    | length == 1 and .[0].status == "False")
          and
          ($conds | map(select(.type=="Progressing")) | length == 1 and .[0].status == "False")
        )
    )
  ' >/dev/null; then
    echo "All TigeraStatus resources are fully ready."
    
    kubectl taint node apt-kitten node-role.kubernetes.io/control-plane:NoSchedule-
    exit 0
  fi

  echo "Waiting for TigeraStatus resources to be ready... ($i/$MAX_RETRIES)"
  sleep "$DELAY"
done

echo "ERROR: TigeraStatus resources did not become ready in time."
exit 1
