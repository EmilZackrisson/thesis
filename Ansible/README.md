# Ansible Playbooks

| Playbook      | Purpose |
| ----------- | ----------- |
| host_setup.yaml      | Install and configure kvm, minikube and kubectl       |
| create_cluster.yaml   | Create a minikube single-node cluster with Calico CNI and iptables or eBPF dataplane        |

## How to run

```bash
ansible-playbook -u <REMOTE_USER> -i inventory.ini playbook.yaml -K
```