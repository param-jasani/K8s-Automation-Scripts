#!/bin/bash 
# Deploy Rook Ceph and CephFS on a Kubernetes bare-metal cluster 
# Based on Rook Ceph Quickstart: https://rook.io/docs/rook/latest-release/Getting-Started/quickstart/ 
# Variables 
ROOK_VERSION="v1.17.2" 
# Latest stable version as of documentation 
NAMESPACE="rook-ceph" 
git clone --single-branch --branch v1.17.4 https://github.com/rook/rook.git 
cd rook/deploy/examples 
kubectl create -f crds.yaml -f common.yaml -f operator.yaml 
# Step 4: Wait for Rook operator to be ready echo "Waiting for Rook operator to be ready..." 
kubectl -n ${NAMESPACE} wait --for=condition=Available deployment/rook-ceph-operator --timeout=300s 
# Step 5: Create Ceph cluster (configured for bare-metal with device discovery) 
cat << EOF | kubectl apply -f - 
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v19.2.2
  dataDirHostPath: /data
  mon:
    # For testing a single worker node, set monitor count to 1 and allow multiple per node if necessary.
    count: 1
    allowMultiplePerNode: true
  dashboard:
    enabled: true
  # Use specific nodes instead of all nodes
  storage:
    useAllNodes: false
    nodes:
      - name: node1
        deviceFilter: "^sda6$" 
      - name: node2 
        deviceFilter: "^sda6$" 
      - name: node3 
        deviceFilter: "^sda6$" 
      - name: node4
        deviceFilter: "^sda6$" 
      - name: node5 
        deviceFilter: "^sda5$" 
      - name: node6 
        deviceFilter: "^sda6$" 
      - name: node7 
        deviceFilter: "^sda6$" 
      - name: node9 
        deviceFilter: "^sda6$" 
      - name: node10 
        deviceFilter: "^sda6$" 
      - name: node11
        deviceFilter: "^sda6$" 
      - name: node12
        deviceFilter: "^sda5$" 
      - name: node13
        deviceFilter: "^sda6$" 
      - name: node14
        deviceFilter: "^sda5$" 
      - name: node15
        deviceFilter: "^sda6$" 
      - name: node16
        deviceFilter: "^sda5$" 
    config:
      storeType: bluestore
EOF