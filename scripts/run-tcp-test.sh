#!/bin/bash

# This is made to run on NodeB (casual-lamb) only

echo "Deploying tcpecho"
kubectl apply -f https://github.com/EmilZackrisson/thesis/blob/main/K8s/tcpecho/deployment.yaml

# Wait on deployment and service to be ready
kubectl rollout status deployment tcpecho -n default --timeout=90s
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' service/tcpecho

echo "Starting tcpserver"
tcpserver -e $EXP_ID -r $RUN_ID -k $KEY_ID -p 9000 &

echo "Starting tcpclient"
tcpclient -e $EXP_ID -r $RUN_ID -k $KEY_ID --server 10.200.200.1 -p 9000 -n 100 --pktsize u --wait u


echo "SUCCESS"
