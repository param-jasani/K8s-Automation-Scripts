#!/bin/bash
# Script to set up a Kubernetes v1.33.1 control plane node with Calico CNI on Ubuntu 22.04

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
