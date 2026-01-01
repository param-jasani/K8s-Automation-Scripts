#!/bin/bash
# Script to set up a Kubernetes v1.33.1 control plane node with Calico CNI on Ubuntu 22.04
# and integrate a load balancer (e.g., HAProxy) as the API endpoint.

# Exit on any error
set -e

# Check system requirements
echo "Checking system requirements..."
if [ $(nproc) -lt 2 ]; then
  echo "Error: At least 2 CPUs required."
  exit 1
fi
if [ $(free -m | awk '/^Mem:/{print $2}') -lt 2000 ]; then
  echo "Error: At least 2GB RAM required."
  exit 1
fi
if [ $(df -BG / | awk 'NR==2 {print $4}' | cut -d'G' -f1) -lt 20 ]; then
  echo "Error: At least 20GB free disk space required on /."
  exit 1
fi

# Update package index and install prerequisites
echo "Installing prerequisites..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg openssl

# Create keyrings directory
mkdir -p -m 755 /etc/apt/keyrings

# Add Kubernetes apt repository key
echo "Adding Kubernetes repository key..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes apt repository
echo "Adding Kubernetes repository..."
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Disable swap and validate
echo "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
if swapon --show | grep -q .; then
  echo "Error: Swap is still enabled. Please disable it manually."
  exit 1
fi

# Install and configure containerd
echo "Installing containerd..."
apt-get update
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Enable CRI integration
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
if ! systemctl is-active --quiet containerd; then
  echo "Error: containerd failed to start."
  exit 1
fi

# Load required kernel modules
echo "======== Loading required kernel modules ========"
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Set sysctl parameters for Kubernetes
echo "======== Setting sysctl parameters for Kubernetes ========"
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Set up firewall rules
echo "======== Setting up firewall rules ========"
ufw allow 6443/tcp  # API server
ufw allow 10250/tcp # Kubelet
ufw allow 2379:2380/tcp # etcd (managed by kubeadm)
ufw allow 179/tcp   # Calico BGP
ufw allow 10248/tcp # Kubelet healthz
ufw allow 10249/tcp # Kube proxy metrics
ufw allow 10259/tcp # Kube scheduler
ufw allow 10257/tcp # Kube controller manager

# Install Kubernetes components
echo "Installing kubelet, kubeadm, kubectl..."
apt-get update
apt-get install -y kubelet=1.33.1-1.1 kubeadm=1.33.1-1.1 kubectl=1.33.1-1.1
apt-mark hold kubelet kubeadm kubectl

# Enable and start kubelet
echo "Starting kubelet..."
systemctl enable --now kubelet
if ! systemctl is-active --quiet kubelet; then
  echo "Error: kubelet failed to start."
  exit 1
fi

# Initialize control plane
echo "Initializing control plane..."
kubeadm init \
  --control-plane-endpoint="192.168.12.80:6443" \
  --upload-certs \
  --apiserver-advertise-address="192.168.12.93" \
  --apiserver-cert-extra-sans="192.168.12.93,192.168.12.80,localhost,127.0.0.1" \
  --service-dns-domain=cluster.local \
  --pod-network-cidr=192.168.0.0/16 \
  --token-ttl=24h \
  --v=5

# Set up kubeconfig for admin user
echo "Setting up kubeconfig..."
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
chmod 600 $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config

# Provision Kubernetes user account for Calico CNI
echo "Provisioning Calico CNI user account..."
openssl req -newkey rsa:4096 \
            -keyout cni.key \
            -nodes \
            -out cni.csr \
            -subj "/CN=calico-cni"
openssl x509 -req -in cni.csr \
             -CA /etc/kubernetes/pki/ca.crt \
             -CAkey /etc/kubernetes/pki/ca.key \
             -CAcreateserial \
             -out cni.crt \
             -days 365
chown $(id -u):$(id -g) cni.crt

APISERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
kubectl config set-cluster kubernetes \
    --certificate-authority=/etc/kubernetes/pki/ca.crt \
    --embed-certs=true \
    --server=$APISERVER \
    --kubeconfig=cni.kubeconfig
kubectl config set-credentials calico-cni \
    --client-certificate=cni.crt \
    --client-key=cni.key \
    --embed-certs=true \
    --kubeconfig=cni.kubeconfig
kubectl config set-context default \
    --cluster=kubernetes \
    --user=calico-cni \
    --kubeconfig=cni.kubeconfig
kubectl config use-context default --kubeconfig=cni.kubeconfig

# Provision RBAC for Calico CNI
echo "Provisioning RBAC for Calico CNI..."
kubectl apply -f - <<EOF
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: calico-cni
rules:
  - apiGroups: [""]
    resources:
      - pods
      - nodes
      - namespaces
    verbs:
      - get
  - apiGroups: [""]
    resources:
      - pods/status
    verbs:
      - patch
  - apiGroups: ["crd.projectcalico.org"]
    resources:
      - blockaffinities
      - ipamblocks
      - ipamhandles
    verbs:
      - get
      - list
      - create
      - update
      - delete
  - apiGroups: ["crd.projectcalico.org"]
    resources:
      - ipamconfigs
      - clusterinformations
      - ippools
    verbs:
      - get
      - list
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: calico-cni
subjects:
  - kind: User
    name: calico-cni
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: calico-cni
  apiGroup: rbac.authorization.k8s.io
EOF

# Install Calico CNI binaries
echo "Installing Calico CNI binaries..."
mkdir -p /opt/cni/bin
curl -L -o /opt/cni/bin/calico https://github.com/projectcalico/cni-plugin/releases/download/v3.30.1/calico-amd64
chmod 755 /opt/cni/bin/calico
curl -L -o /opt/cni/bin/calico-ipam https://github.com/projectcalico/cni-plugin/releases/download/v3.30.1/calico-ipam-amd64
chmod 755 /opt/cni/bin/calico-ipam

# Create CNI configuration
echo "Creating Calico CNI configuration..."
mkdir -p /etc/cni/net.d
cp cni.kubeconfig /etc/cni/net.d/calico-kubeconfig
chmod 600 /etc/cni/net.d/calico-kubeconfig
cat > /etc/cni/net.d/10-calico.conflist <<EOF
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "calico",
      "log_level": "info",
      "datastore_type": "kubernetes",
      "mtu": 1500,
      "ipam": {
        "type": "calico-ipam"
      },
      "policy": {
        "type": "k8s"
      },
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/calico-kubeconfig"
      }
    },
    {
      "type": "portmap",
      "snat": true,
      "capabilities": {"portMappings": true}
    }
  ]
}
EOF

# Install Calico network plugin
echo "Installing Calico network plugin..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.1/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.1/manifests/tigera-operator.yaml
# Wait for Tigera operator to be ready
echo "Waiting for Tigera operator to be ready..."
kubectl wait --for=condition=Available -n tigera-operator deployment/tigera-operator --timeout=300s
# Apply Calico custom resources
curl -s https://raw.githubusercontent.com/projectcalico/calico/v3.30.1/manifests/custom-resources.yaml -o custom-resources.yaml
kubectl apply -f custom-resources.yaml

# Wait for control plane node to be ready
echo "Waiting for control plane node to be ready..."
kubectl wait --for=condition=Ready node/$(hostname) --timeout=300s

# Wait for core system pods to be running
echo "Waiting for core system pods to be running..."
kubectl wait --for=condition=Ready pod -n kube-system -l k8s-app=kube-dns --timeout=300s
kubectl wait --for=condition=Ready pod -n kube-system -l component=kube-apiserver --timeout=300s
kubectl wait --for=condition=Ready pod -n kube-system -l component=kube-controller-manager --timeout=300s
kubectl wait --for=condition=Ready pod -n kube-system -l component=kube-scheduler --timeout=300s

# Print join command for worker nodes and additional control planes
echo "Control plane initialized successfully. Save the following join command for worker nodes or additional control plane nodes (with --control-plane flag for control planes):"
kubeadm token create --print-join-command

# Verify cluster status
echo "Verifying cluster status..."
kubectl get nodes
kubectl get pods -n kube-system
