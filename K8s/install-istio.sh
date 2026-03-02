# patch calico configuration
kubectl patch installation default --type=merge -p '{"spec": {"flexVolumePath": "None"}}'
kubectl patch felixconfiguration default --type merge -p '{"spec":{"bpfConnectTimeLoadBalancing":"Disabled"}}'

# Install Istio
/home/ubuntu/istio-1.29.0/bin/istioctl install --set profile=minimal

# Label the namespace where to deploy Istio-enabled workloads:
kubectl label namespace default istio-injection=enabled --overwrite
