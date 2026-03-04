#!/bin/bash

DATAPLANE=$1
PROTOCOL=$2
POLICY_DIRECTION=$3

ISTIO_SIDECAR=$4
ISTIO_POLICY=$5

THESIS_REPO_PATH=$7

exit_and_fail() {
    echo "FAILURE"
    exit 1
}

# Check if repo path is givne
if [ -z $THESIS_REPO_PATH ]; then
    echo "No thesis repo path given"
    exit_and_fail
fi

# Check if thesis repo path exists
if [ ! -d $THESIS_REPO_PATH ]; then
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

if [[ $PROTOCOL = "tcp" ]]; then
    echo "Testing TCP"

    echo "TCP testing not implemented"
    exit_and_fail

elif [[ $PROTOCOL = "http" ]]; then
    echo "Testing HTTP"

    echo "Deploying grecho in k8s"
    kubectl apply -f $THESIS_REPO_PATH/K8s/grecho/deployment.yaml

else 
    echo "Invalid protocol, must be (tcp, http)"
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

    echo "Istio sidecar deployment not implemented"
    exit_and_fail

    # TODO: Check if Istio is installed, if not ABORT or install (not sure)

elif [[ $ISTIO_SIDECAR = "no" ]]; then
    echo "Without Istio Sidecar"

    # TODO: Check if Istio is installed, if so ABORT

elif [[ $ISTIO_SIDECAR = "withacceleration" ]]; then
    echo "Without Istio Sidecar"

    # TODO: Check if Istio is installed, if so ABORT
    
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
    kubectl apply -f $THESIS_REPO_PATH/K8s/policies/grecho-authorization-policy.yaml

elif [[ $ISTIO_POLICY = "false" ]]; then
    echo "Without Istio policy"
else 
    echo "Invalid Istio policy argument, must be (true, false)"
    exit_and_fail
fi

# TODO: Start cgroup recorder, wait 5 seconds

# Continue with specific protocol testing script
if [[ $PROTOCOL = "tcp" ]]; then
    echo "Running TCP testing script"

    $THESIS_REPO_PATH/scripts/run-tcp-test.sh

elif [[ $PROTOCOL = "http" ]]; then
    echo "Running HTTP testing script"

    $THESIS_REPO_PATH/scripts/run-http-test.sh

# TODO: Stop cgroup recorder, wait 5 seconds

echo "SUCCESS"