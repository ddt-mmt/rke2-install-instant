#!/bin/bash

# =============================================================================
# All-in-One RKE2 and Rancher Installation Script (Universal)
#
# Author: Gemini
# Description: This script automates the installation of RKE2, Rancher, and
#              necessary tools on multiple Linux distributions.
# Supported OS Families: Red Hat (CentOS, AlmaLinux), Debian (Ubuntu)
# = a==========================================================================

# --- Configuration ---
# Set to the latest stable versions
RKE2_VERSION="v1.34.1+rke2r1"
CERT_MANAGER_VERSION="v1.14.5"

# Exit on error
set -e

# --- Helper Functions ---

# Function to detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_FAMILY=$ID_LIKE
        if [ -z "$OS_FAMILY" ]; then
            OS_FAMILY=$ID
        fi

        case $OS_FAMILY in
            *rhel*|*fedora*|*centos*)
                PKG_MANAGER="yum"
                FIREWALL_SERVICE="firewalld"
                ;;
            *debian*|*ubuntu*)
                PKG_MANAGER="apt-get"
                FIREWALL_SERVICE="ufw"
                ;;
            *)
                echo "Unsupported Linux distribution: $ID. Exiting."
                exit 1
                ;;
        esac
        echo "Detected OS Family: $OS_FAMILY, Package Manager: $PKG_MANAGER, Firewall: $FIREWALL_SERVICE"
    else
        echo "Cannot detect Linux distribution. Exiting."
        exit 1
    fi
}

# Function to configure firewalld
configure_firewalld() {
    echo "Configuring firewalld..."
    # For RKE2 Server
    firewall-cmd --permanent --add-port=9345/tcp # RKE2 Agent
    firewall-cmd --permanent --add-port=6443/tcp # Kubernetes API
    firewall-cmd --permanent --add-port=2379-2380/tcp # etcd
    firewall-cmd --permanent --add-port=10250/tcp # Kubelet
    # For Rancher NodePort services
    firewall-cmd --permanent --add-port=30000-32767/tcp
    firewall-cmd --reload
    echo "firewalld configured."
}

# Function to configure ufw
configure_ufw() {
    echo "Configuring ufw..."
    # For RKE2 Server
    ufw allow 9345/tcp # RKE2 Agent
    ufw allow 6443/tcp # Kubernetes API
    ufw allow 2379:2380/tcp # etcd
    ufw allow 10250/tcp # Kubelet
    # For Rancher NodePort services
    ufw allow 30000:32767/tcp
    ufw reload
    echo "ufw configured."
}

# --- Main Script --- #

# 1. Pre-flight checks
echo "### 1. Running Pre-flight Checks ###"
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root or with sudo." >&2
  exit 1
fi

detect_os

# Install curl if not present
if ! command -v curl &> /dev/null; then
    echo "curl not found. Installing..."
    if [ "$PKG_MANAGER" == "yum" ]; then
        yum install -y curl
    else
        apt-get update && apt-get install -y curl
    fi
fi

# 2. Firewall Configuration
echo "### 2. Configuring Firewall ###"
if systemctl is-active --quiet $FIREWALL_SERVICE; then
    if [ "$FIREWALL_SERVICE" == "firewalld" ]; then
        configure_firewalld
    elif [ "$FIREWALL_SERVICE" == "ufw" ]; then
        configure_ufw
    fi
else
    echo "Warning: Firewall service ($FIREWALL_SERVICE) is not active. Skipping firewall configuration."
fi

# 3. User Input for Installation Mode
INSTALL_MODE=""
while [[ "$INSTALL_MODE" != "nodeport" && "$INSTALL_MODE" != "ingress" ]]; do
  read -p "Choose installation mode (nodeport/ingress): " INSTALL_MODE
  INSTALL_MODE=$(echo "$INSTALL_MODE" | tr '[:upper:]' '[:lower:]')
done

# 4. RKE2 and Tools Installation
echo "### 4. Installing RKE2 version ${RKE2_VERSION} ###"
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=${RKE2_VERSION} sh -
mkdir -p /etc/rancher/rke2/
systemctl enable rke2-server.service
systemctl start rke2-server.service

echo "### Waiting for RKE2 to be ready... ###"
while [ ! -f /var/lib/rancher/rke2/server/node-token ]; do
  echo "Waiting for node token..."
  sleep 5
done

echo "### Installing kubectl and helm ###"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# 5. Configure KUBECONFIG
echo "### 5. Configuring KUBECONFIG ###"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
if ! grep -q "KUBECONFIG=/etc/rancher/rke2/rke2.yaml" ~/.bashrc; then
    echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> ~/.bashrc
fi

# 6. Cert-Manager Installation
echo "### 6. Installing cert-manager version ${CERT_MANAGER_VERSION} ###"
helm repo add jetstack https://charts.jetstack.io --force-update
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version ${CERT_MANAGER_VERSION}

echo "### Waiting for cert-manager to be ready... ###"
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=300s

# 7. Rancher Installation
echo "### 7. Installing Rancher ###"
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update
kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -

if [ "$INSTALL_MODE" == "nodeport" ]; then
  echo "Installing Rancher in NodePort mode..."
  helm install rancher rancher-latest/rancher --namespace cattle-system --set service.type=NodePort --set tls=external
else # Ingress mode
  read -p "Enter the hostname for Rancher (e.g., rancher.my.org): " RANCHER_HOSTNAME
  echo "Installing Rancher in Ingress mode with hostname: $RANCHER_HOSTNAME"
  helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=$RANCHER_HOSTNAME
fi

echo "### Waiting for Rancher to be ready... ###"
kubectl wait --for=condition=Available deployment/rancher -n cattle-system --timeout=300s

# 8. Final Access Information
echo "### 8. Rancher Access Information ###"
BOOTSTRAP_PASSWORD=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')

echo "========================================================================"
echo "Rancher Installation Complete!"
echo ""

if [ "$INSTALL_MODE" == "nodeport" ]; then
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
  NODE_PORT=$(kubectl get service -n cattle-system rancher -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
  echo "Access URL: https://${NODE_IP}:${NODE_PORT}/dashboard/?setup=${BOOTSTRAP_PASSWORD}"
else # Ingress mode
  echo "Access URL: https://${RANCHER_HOSTNAME}/dashboard/?setup=${BOOTSTRAP_PASSWORD}"
  echo "Please make sure your DNS is configured to point $RANCHER_HOSTNAME to your Ingress Controller."
fi

echo ""
echo "Bootstrap Password: ${BOOTSTRAP_PASSWORD}"
echo "========================================================================"
