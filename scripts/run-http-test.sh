#!/bin/bash

# This is made to run on NodeB (casual-lamb) only

echo "Deploying grecho"
kubectl apply -f https://github.com/EmilZackrisson/thesis/blob/main/K8s/grecho/deployment.yaml

# Wait on deployment and service to be ready
kubectl rollout status deployment grecho -n default --timeout=90s
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' service/grecho

echo "Running httptrafficgenerator"
PKT_COUNT = 100000
MIN_SIZE = 200
MAX_SIZE = 2000
MIN_INT_MS = 1
MAX_INT_MS = 1000
DEST_URL = http://10.200.200.1
httptrafficgenerator $PKT_COUNT $MIN_SIZE $MAX_SIZE $MIN_INT_MS $MAX_INT_MS $DEST_URL


echo "SUCCESS"
