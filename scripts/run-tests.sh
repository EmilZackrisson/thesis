#!/bin/bash

DATAPLANE=$1
PROTOCOL=$2
POLICY_DIRECTION=$3

ISTIO_SIDECAR=$4
ISTIO_POLICY=$5

THESIS_REPO_PATH=$6

ISTIO_INSTALLED=false

export KUBECONFIG="/home/ubuntu/.kube/config"

echo "Running as user=$USER"

exit_and_fail() {
    echo "FAILURE"
    exit 1
}

error_handler() {
    local exit_code=$?
    local line_no=$1
    local cmd=$2

    echo "❌ Error on line $line_no: '$cmd'"
    echo "Exit code: $exit_code"
    
    echo "FAILURE"
    exit 1
}

trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

cgv2-k8s-record(){
    ssh apt-kitten sudo /home/ubuntu/thesis/cgroup_recorder/cgv2-k8s-record.sh $@
}

check_istio_installed() {
    if kubectl get pods -n istio-system | grep -q 'No resources found in istio-syste namespace.'; then
        echo "Istio is not installed"
    else
        echo "Istio is installed"
        ISTIO_INSTALLED=true
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

if [[ $PROTOCOL = "udp" ]]; then
    echo "Testing UDP"

    echo "Deploying UDP-echo"
    kubectl apply -f $THESIS_REPO_PATH/K8s/udpecho/deployment.yaml

elif [[ $PROTOCOL = "http" ]]; then
    echo "Testing HTTP"

    echo "Deploying grecho in k8s"
    kubectl apply -f $THESIS_REPO_PATH/K8s/grecho/deployment.yaml

else 
    echo "Invalid protocol, must be (udp, http)"
    exit_and_fail
fi

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

elif [[ $ISTIO_SIDECAR = "no" ]]; then
    echo "Without Istio Sidecar"

    check_istio_installed
    if [[ $ISTIO_INSTALLED = "true" ]]; then
        echo "Istio is installed and this script was going to test with Istio not installed, aborting"
        exit_and_fail
    fi

elif [[ $ISTIO_SIDECAR = "withacceleration" ]]; then
    echo "Without Istio Sidecar"

    check_istio_installed
    if [[ $ISTIO_INSTALLED = "true" ]]; then
        echo "Istio is installed and this script was going to test with Istio not installed, aborting"
        exit_and_fail
    fi

else
    echo "Invalid Istio sidecar option, must be (with, withacceleration, no)"
    exit_and_fail
fi

if [[ $ISTIO_POLICY = "true" ]]; then
    if [[ $ISTIO_SIDECAR != "true" ]]; then
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


if [[ $PROTOCOL = "udp" ]]; then
    APP_SELECTOR="app=udpecho"
elif [[ $PROTOCOL = "http" ]]; then
    APP_SELECTOR="app=grecho"
else
    echo "Error matching protocol to app selector"
    exit_and_fail
fi

RECORDING_NAME=$PROTOCOL-$EXP_ID-$RUN_ID-$KEY_ID
echo "Starting cgroup recording 'cgv2-k8s-record start /home/ubuntu/cgroup-recordings/$RECORDING_NAME default $APP_SELECTOR'"
cgv2-k8s-record start /home/ubuntu/cgroup-recordings/$RECORDING_NAME default $APP_SELECTOR
echo "Sleeping 5 seconds"
sleep 5

# Continue with specific protocol testing script
if [[ $PROTOCOL = "udp" ]]; then
    echo "Running UDP testing script"

    $THESIS_REPO_PATH/scripts/run-udp-test.sh "server=10.200.200.1 pktCount=1000 destPort=30002 minIfg=1 maxIfg=1000000 minSize=10 maxSize=1500"

elif [[ $PROTOCOL = "http" ]]; then
    echo "Running HTTP testing script"

    $THESIS_REPO_PATH/scripts/run-http-test.sh

fi

echo "Stopping cgroup recording"
cgv2-k8s-record stop
echo "Sleeping for 5 seconds"
sleep 5

# Backup cgroup recordings to LONTAS
echo "Copying cgroup recordings to /mnt/LONTAS/ExpControl/k8test/cgroup-recordings/$RECORDING_NAME"
ssh apt-kitten cp -r /home/ubuntu/cgroup-recordings/$RECORDING_NAME /mnt/LONTAS/ExpControl/k8test/cgroup-recordings
echo "Done copying"

# Clean up policies, deployments and services
echo "Cleaning up"
kubectl delete -f "$THESIS_REPO_PATH/K8s/grecho/deployment.yaml"
kubectl delete -f "$THESIS_REPO_PATH/K8s/udpecho/deployment.yaml"

kubectl delete -f "$THESIS_REPO_PATH/K8s/policies/ingress.yaml"
kubectl delete -f "$THESIS_REPO_PATH/K8s/policies/egress.yaml"

kubectl delete -f "$THESIS_REPO_PATH/K8s/policies/grecho-authorization-policy.yaml"

echo "SUCCESS"