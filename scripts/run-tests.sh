#!/bin/bash

DATAPLANE=$1
PROTOCOL=$2
POLICY_DIRECTION=$3

ISTIO_SIDECAR=$4
ISTIO_POLICY=$5

THESIS_REPO_PATH=$6

ISTIO_INSTALLED=false
MERBRIDGE_INSTALLED=false

export KUBECONFIG="/home/ubuntu/.kube/config"

cgroup_record_prefix=""

echo "Running as user=$USER"

exit_and_fail() {
    echo "FAILURE"
    exit 1
}

clean_up() {
    echo "Cleaning up Kubernetes resources"
    kubectl delete --wait=true --ignore-not-found=true -f "$THESIS_REPO_PATH/K8s/grecho/deployment.yaml"
    kubectl delete --wait=true --ignore-not-found=true -f "$THESIS_REPO_PATH/K8s/udpecho/deployment.yaml"

    kubectl delete --wait=true --ignore-not-found=true -f "$THESIS_REPO_PATH/K8s/policies/ingress.yaml"
    kubectl delete --wait=true --ignore-not-found=true -f "$THESIS_REPO_PATH/K8s/policies/egress.yaml"

    if [[ $ISTIO_INSTALLED = "true" ]]; then
        kubectl delete --ignore-not-found=true --wait=true -f "$THESIS_REPO_PATH/K8s/policies/grecho-authorization-policy.yaml"
    fi

    echo "Sleeping for 5 seconds"
    sleep 5
}

cgv2-k8s-record(){
    ssh apt-kitten sudo /home/ubuntu/thesis/cgroup_recorder/cgv2-k8s-record.sh $@
}

error_handler() {
    trap - ERR

    local exit_code=$?
    local line_no=$1
    local cmd=$2

    echo "❌ Error on line $line_no: '$cmd'"
    echo "Exit code: $exit_code"

    cgv2-k8s-record stop
    clean_up
    
    echo "FAILURE"
    exit 1
}

trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

check_istio_installed() {
    if kubectl get namespace istio-system >/dev/null 2>&1 && \
       kubectl get pods -n istio-system --no-headers 2>/dev/null | grep -q .; then
        echo "Istio is installed"
        ISTIO_INSTALLED=true
    else
        echo "Istio is not installed"
        ISTIO_INSTALLED=false
    fi
}

check_merbridge_installed() {
    if kubectl get namespace istio-system >/dev/null 2>&1 && \
       kubectl get pods -n istio-system -l app=merbridge --no-headers 2>/dev/null | grep -q .; then
        echo "Merbridge is installed"
        MERBRIDGE_INSTALLED=true
    else
        echo "Merbridge is not installed"
        MERBRIDGE_INSTALLED=false
    fi
}

# Check if repo path is givne
if [ -z "$THESIS_REPO_PATH" ]; then
    echo "No thesis repo path given"
    exit_and_fail
fi

# Check if thesis repo path exists
if [ ! -d "$THESIS_REPO_PATH" ]; then
    echo "Thesis repo given by the path does not exist"
    exit_and_fail
fi

# Validate dataplane
if [[ $DATAPLANE = "iptables" ]]; then
    echo "Using iptables"
elif [[ $DATAPLANE = "ebpf" ]]; then
    echo "Using eBPF"
else
    echo "Invalid dataplane option, must be (iptables, ebpf)"
    exit_and_fail
fi
cgroup_record_prefix+="$DATAPLANE-"

if [[ $PROTOCOL = "udp" ]]; then
    echo "Testing UDP"

    echo "Deploying UDP-echo"
    kubectl apply --wait=true --timeout=3m -f $THESIS_REPO_PATH/K8s/udpecho/deployment.yaml

elif [[ $PROTOCOL = "http" ]]; then
    echo "Testing HTTP"

    echo "Deploying grecho in k8s"
    kubectl apply --wait=true --timeout=3m -f $THESIS_REPO_PATH/K8s/grecho/deployment.yaml

else 
    echo "Invalid protocol, must be (udp, http)"
    exit_and_fail
fi
cgroup_record_prefix+="$PROTOCOL-"

if [[ $POLICY_DIRECTION = "none" ]]; then
    echo "No policies"
elif [[ $POLICY_DIRECTION = "ingress" ]]; then
    echo "With ingress policies"

    echo "Applying ingress policies"
    kubectl apply -f $THESIS_REPO_PATH/K8s/policies/ingress.yaml

elif [[ $POLICY_DIRECTION = "egress" ]]; then
    echo "With egress policies"

    echo "Applying egress policies"
    kubectl apply -f $THESIS_REPO_PATH/K8s/policies/egress.yaml

elif [[ $POLICY_DIRECTION = "both" ]]; then
    echo "With both ingress and egress policies"

    echo "Applying both ingress and egress policies"
    kubectl apply -f $THESIS_REPO_PATH/K8s/policies/ingress.yaml
    kubectl apply -f $THESIS_REPO_PATH/K8s/policies/egress.yaml

else 
    echo "Invalid policy direction, must be (none, ingress, egress, both)"
    exit_and_fail
fi
cgroup_record_prefix+="$POLICY_DIRECTION-"

if [[ $ISTIO_SIDECAR = "with" ]]; then

    # Check so that protocol is http
    if [[ $PROTOCOL != "http" ]]; then
        echo "Istio sidecar can only be used with http"
        exit_and_fail
    fi

    echo "With Istio Sidecar"

    check_istio_installed
    if [[ $ISTIO_INSTALLED = "false" ]]; then
        echo "Istio is not installed and this script was going to test with Istio installed, aborting"
        exit_and_fail
    fi

    if [[ $POLICY_DIRECTION != "none" ]]; then
        echo "Applying network policies to allow comms to istiod"
        kubectl apply -f "$THESIS_REPO_PATH/K8s/policies/istiod-networkpolicy.yaml"
    fi

elif [[ $ISTIO_SIDECAR = "no" ]]; then
    echo "Without Istio Sidecar"

    check_istio_installed
    if [[ $ISTIO_INSTALLED = "true" ]]; then
        echo "Istio is installed and this script was going to test with Istio not installed, aborting"
        exit_and_fail
    fi

elif [[ $ISTIO_SIDECAR = "withacceleration" ]]; then
    echo "With Istio Sidecar and Merbridge eBPF acceleration."

    # Check so that protocol is http
    if [[ $PROTOCOL != "http" ]]; then
        echo "Istio sidecar can only be used with http"
        exit_and_fail
    fi

    check_istio_installed
    if [[ $ISTIO_INSTALLED = "false" ]]; then
        echo "Istio is not installed and this script was going to test with Istio installed, aborting"
        exit_and_fail
    fi

    check_merbridge_installed
    if [[ $MERBRIDGE_INSTALLED = "false" ]]; then
        echo "Merbridge is not installed and this script was going to test with Merbridge installed, aborting"
        exit_and_fail
    fi

    if [[ $POLICY_DIRECTION != "none" ]]; then
        echo "Applying network policies to allow comms to istiod"
        kubectl apply -f "$THESIS_REPO_PATH/K8s/policies/istiod-networkpolicy.yaml"
    fi

else
    echo "Invalid Istio sidecar option, must be (with, withacceleration, no)"
    exit_and_fail
fi
cgroup_record_prefix+="$ISTIO_SIDECAR-"

if [[ $ISTIO_POLICY = "true" ]]; then
    if [[ $ISTIO_SIDECAR == "no" ]]; then
        echo "Cannot use Istio policies without istio sidecar"
        exit_and_fail
    fi

    echo "With Istio policies"

    echo "Applying Istio policy"
    kubectl apply -f "$THESIS_REPO_PATH/K8s/policies/grecho-authorization-policy.yaml"

elif [[ $ISTIO_POLICY = "false" ]]; then
    echo "Without Istio policy"
else 
    echo "Invalid Istio policy argument, must be (true, false)"
    exit_and_fail
fi
cgroup_record_prefix+="$ISTIO_POLICY-"


if [[ $PROTOCOL = "udp" ]]; then
    APP_SELECTOR="app=udpecho"
elif [[ $PROTOCOL = "http" ]]; then
    APP_SELECTOR="app=grecho"
else
    echo "Error matching protocol to app selector"
    exit_and_fail
fi

echo "Waiting for all pods to be ready"
kubectl wait pod \
    --all \
    --for=condition=Ready \
    --timeout=3m \
    --namespace=default

RECORDING_NAME=$cgroup_record_prefix-$EXPID-$RUNID-$KEYID
echo "Starting cgroup recording 'cgv2-k8s-record start /home/ubuntu/cgroup-recordings/$RECORDING_NAME default $APP_SELECTOR'"
cgv2-k8s-record start /home/ubuntu/cgroup-recordings/$RECORDING_NAME default $APP_SELECTOR
echo "Sleeping 5 seconds"
sleep 5

# Continue with specific protocol testing script
if [[ $PROTOCOL = "udp" ]]; then
    echo "Running UDP testing script"

    $THESIS_REPO_PATH/scripts/run-udp-test.sh "server=10.200.200.1 pktCount=1000 destPort=30002 minIfg=1000 maxIfg=1000000 minSize=10 maxSize=1420 wtDist=u pktDist=u"

elif [[ $PROTOCOL = "http" ]]; then
    echo "Running HTTP testing script"

    $THESIS_REPO_PATH/scripts/run-http-test.sh

fi

echo "Stopping cgroup recording"
cgv2-k8s-record stop
echo "Sleeping for 5 seconds"
sleep 5

echo "Parsing and converting the cgroup recordings to csv"
ssh apt-kitten sudo $THESIS_REPO_PATH/cgroup_recorder/parser/cg-record-parser.py --export-csv /home/ubuntu/cgroup-recordings/$RECORDING_NAME

# Remove all raw snapshots
recording_dir="/home/ubuntu/cgroup-recordings/$RECORDING_NAME"
for path in "$recording_dir"/*; do
    name="$(basename "$path")"
    [ "$name" = "export" ] && continue
    [ "$name" = "meta.txt" ] && continue
    sudo rm -rf "$path"
done

# Backup cgroup recordings to LONTAS
echo "Copying cgroup csv files to /mnt/LONTAS/ExpControl/k8test/cgroup-recordings/$RECORDING_NAME"
ssh apt-kitten sudo cp -r /home/ubuntu/cgroup-recordings/$RECORDING_NAME/export /mnt/LONTAS/ExpControl/k8test/cgroup-recordings/$RECORDING_NAME-export
ssh apt-kitten sudo chmod 775 -R /mnt/LONTAS/ExpControl/k8test/cgroup-recordings/$RECORDING_NAME-export

echo "Done copying"

# Clean up policies, deployments and services
echo "Cleaning up"
clean_up

echo "SUCCESS"