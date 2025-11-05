# RKE2 and Rancher Universal Installation Script

This repository contains a universal Bash script to automate the installation of RKE2 (Kubernetes) and Rancher on various Linux distributions.

## Features

-   **All-in-One**: Installs RKE2, `kubectl`, `helm`, `cert-manager`, and Rancher.
-   **Universal Compatibility**: Supports Red Hat-based (e.g., AlmaLinux, CentOS) and Debian-based (e.g., Ubuntu) distributions.
-   **Firewall Configuration**: Automatically configures `firewalld` or `ufw` to open necessary ports for RKE2 and Rancher.
-   **Latest Stable Versions**: Uses specified stable versions for RKE2 and cert-manager, and the latest stable chart for Rancher.
-   **Interactive Mode**: Allows choosing between NodePort or Ingress mode for Rancher access.

## Versions Used

-   **RKE2**: `v1.34.1+rke2r1` (Kubernetes `v1.34.1`)
-   **Cert-Manager**: `v1.14.5`
-   **Rancher**: Latest stable version from `rancher-latest` Helm chart (currently `v2.12.3`)

## Prerequisites

-   A fresh Linux installation (supported distributions mentioned above).
-   Internet connectivity to download packages and images.
-   The script must be run as `root` or with `sudo`.

## How to Use

1.  **Clone this repository** to your Linux machine:
    ```bash
    git clone https://github.com/ddt-mmt/rke2-install-instant.git
    cd rke2-install-instant
    ```

2.  **Make the script executable**:
    ```bash
    chmod +x install_rancher_universal.sh
    ```

3.  **Run the script as root**:
    ```bash
    sudo ./install_rancher_universal.sh
    ```

4.  **Follow the interactive prompts**:
    -   The script will ask you to choose between `nodeport` or `ingress` mode for Rancher access.
    -   If you choose `ingress`, it will prompt you to enter a hostname for Rancher (e.g., `rancher.yourdomain.com`).

5.  **Wait for the installation to complete**: The script will perform all necessary steps, including RKE2 installation, tool setup, firewall configuration, cert-manager deployment, and Rancher deployment. This process can take several minutes.

6.  **Access Rancher**: Once the script finishes, it will output the Rancher access URL and the bootstrap password. Use this information to log in to your Rancher UI.

## Important Notes

-   **Firewall**: The script attempts to configure the firewall automatically. If you have a custom firewall setup, you might need to manually open ports 9345/tcp, 6443/tcp, 2379-2380/tcp, 10250/tcp, and the NodePort range (30000-32767/tcp) if using NodePort mode.
-   **Ingress Mode**: If you choose Ingress mode, ensure your DNS records are correctly configured to point your chosen hostname to the IP address of your RKE2 node (or your Ingress Controller's external IP).
-   **Single Node**: This script is designed for a single-node RKE2 server installation. For multi-node clusters, you would install RKE2 agents on additional nodes separately.