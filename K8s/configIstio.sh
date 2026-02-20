# patch calico configuration
kubectl patch felixconfiguration default --type merge -p '{"spec":{"policySyncPathPrefix":"/var/run/nodeagent"}}'
kubectl patch installation default --type=merge -p '{"spec": {"flexVolumePath": "None"}}'
kubectl patch felixconfiguration default --type merge -p '{"spec":{"bpfConnectTimeLoadBalancing":"Disabled"}}'

# Install Istio
istioctl install -f istio-operator-dikastes.yaml -y

# Configure Istio's Envoy proxies to use Dikastes as an external authorization service.
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/alp/istio-app-layer-policy-envoy-v3.yaml

# Label the namespace where to deploy Istio-enabled workloads:
kubectl label namespace default istio-injection=enabled
