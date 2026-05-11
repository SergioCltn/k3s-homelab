How to check performance
1. Node health
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl get nodes -o wide
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl describe node aetherion
Look at:
- Ready
- MemoryPressure
- DiskPressure
- PIDPressure
- Allocated resources
2. Live CPU and memory
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl top nodes
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl top pods -A
Use these to see:
- node CPU %
- node memory %
- which pods are consuming the most CPU/memory
3. Pod health
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl get pods -A
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl get pods -A -o wide
Watch for:
- CrashLoopBackOff
- ImagePullBackOff
- frequent restarts
- pods stuck in Pending
4. Recent problems/events
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl get events -A --sort-by=.lastTimestamp
Useful for:
- failed image pulls
- probe failures
- scheduling failures
- storage issues
5. Service and ingress reachability
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl get svc -A
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl get ingress -A -o wide
Check:
- MetalLB external IPs
- ingress address
- expected hostnames
6. Storage usage
Kubernetes itself won’t show disk usage nicely by default. Check the node directly:
ssh aetherion@192.168.1.134 'df -h'
ssh aetherion@192.168.1.134 'sudo du -sh /var/lib/rancher/k3s /var/lib/rancher/k3s/storage /var/lib/rancher/k3s/agent/containerd'
Important for:
- image storage growth
- PVC/local-path usage
- disk pressure risk
7. k3s / control plane health
ssh aetherion@192.168.1.134 'sudo systemctl status k3s --no-pager'
ssh aetherion@192.168.1.134 'sudo journalctl -u k3s -n 200 --no-pager'
Use when:
- API is slow
- pods won’t start
- storage/networking acts strangely
Best indicators to watch regularly
- kubectl top nodes
- kubectl top pods -A
- kubectl describe node aetherion
- kubectl get events -A --sort-by=.lastTimestamp
