#!/bin/bash

echo "Start minikube tunnel"
minikube tunnel --bind-address='10.200.200.1' &
tunnel_pid=$!
echo "Tunnel running with PID=${tunnel_pid}"

echo "Deploying tcpecho"
kubectl apply -f https://github.com/EmilZackrisson/thesis/blob/main/K8s/tcpecho/deployment.yaml

# Wait on deployment and service to be ready
kubectl rollout status deployment tcpecho -n default --timeout=90s
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' service/tcpecho

echo "Starting tcpserver"
tcpserver -e $EXP_ID -r $RUN_ID -k $KEY_ID -p 9000 &

echo "Starting tcpclient"
tcpclient -e $EXP_ID -r $RUN_ID -k $KEY_ID --server 10.200.200.1 -p 9000 -n 100 --pktsize u --wait u

echo "Killing tunnel"
trap 'kill -15 ${tunnel_pid}'; echo "killed: ${tunnel_pid}"; INT

echo "Waiting for kills..."
wait

echo "SUCCESS"