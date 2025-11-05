#!/bin/bash

# Exit on error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# --- Installation Mode --- #
INSTALL_MODE=""
while [[ "$INSTALL_MODE" != "nodeport" && "$INSTALL_MODE" != "ingress" ]]; do
  read -p "Choose installation mode (nodeport/ingress): " INSTALL_MODE
  INSTALL_MODE=$(echo "$INSTALL_MODE" | tr '[:upper:]' '[:lower:]')
done

# --- RKE2 and Tools Installation --- #
echo "### 1. Installing RKE2 ###"
curl -sfL https://get.rke2.io | sh -
mkdir -p /etc/rancher/rke2/
systemctl enable rke2-server.service
systemctl start rke2-server.service

echo "### Waiting for RKE2 to be ready... ###"
while [ ! -f /var/lib/rancher/rke2/server/node-token ]; do
  sleep 5
done

echo "### 2. Installing kubectl and helm ###"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

echo "### 3. Configuring KUBECONFIG ###"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> ~/.bashrc

# --- Cert-Manager Installation --- #
echo "### 4. Installing cert-manager ###"
CERT_MANAGER_VERSION="v1.14.5"
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version ${CERT_MANAGER_VERSION}

echo "### Waiting for cert-manager to be ready... ###"
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=300s

# --- Rancher Installation --- #
echo "### 5. Installing Rancher ###"
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update
kubectl create namespace cattle-system

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

# --- Access Information --- #
echo "### 6. Rancher Access Information ###"
BOOTSTRAP_PASSWORD=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')

echo "========================================================================"
echo "Rancher is ready to be accessed!"
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
