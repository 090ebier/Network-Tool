#!/bin/bash
trap "clear; echo 'Exiting Network Tool Management Installer...'; exit" SIGINT
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges. Restarting with sudo..."
    exec sudo "$0" "$@"
    exit 1
fi

# 1. مسیر نصب
INSTALL_DIR="/opt/net-tool"
REPO_URL="https://github.com/090ebier/Network-Tool.git"

if [ -d "$INSTALL_DIR" ]; then
    echo "Directory $INSTALL_DIR already exists. Removing the existing directory..."
    sudo rm -rf $INSTALL_DIR || { echo "Failed to remove existing directory $INSTALL_DIR."; exit 1; }
fi

echo "Cloning the project from GitHub..."
if sudo git clone $REPO_URL $INSTALL_DIR; then
    echo "Project cloned successfully."
else
    echo "Failed to clone the project from GitHub."
    exit 1
fi

BIN_DIR="/usr/local/bin"
echo "Creating symlink in $BIN_DIR..."
if sudo ln -sf $INSTALL_DIR/net-tool.sh $BIN_DIR/net-tool; then
    echo "Symlink created successfully."
else
    echo "Failed to create symlink in $BIN_DIR."
    exit 1
fi

sudo apt-get update 
check_and_install() {
    PKG_NAME=$1
    if ! dpkg -s $PKG_NAME >/dev/null 2>&1; then
        echo "$PKG_NAME is not installed. Installing..."
        sudo DEBIAN_FRONTEND=noninteractive apt install -y $PKG_NAME || { echo "Failed to install $PKG_NAME."; exit 1; }
    else
        echo "$PKG_NAME is already installed."
    fi
}

check_and_install_pip() {
    PIP_PKG_NAME=$1
    if ! pip3 show $PIP_PKG_NAME >/dev/null 2>&1; then
        echo "$PIP_PKG_NAME is not installed. Installing with pip..."
        pip3 install $PIP_PKG_NAME --break-system-packages || { echo "Failed to install Python package: $PIP_PKG_NAME."; exit 1; }
    else
        echo "$PIP_PKG_NAME is already installed."
    fi
}

install_speedtest() {
    if ! command -v speedtest &> /dev/null; then
        echo "Speedtest CLI is not installed. Installing..."
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash || { echo "Failed to add speedtest-cli repository."; exit 1; }
        sudo apt-get install speedtest -y || { echo "Failed to install speedtest."; exit 1; }
    else
        echo "Speedtest CLI is already installed."
    fi
}

install_dependencies() {
    echo "Checking for system dependencies..."

    check_and_install dialog
    check_and_install nftables
    check_and_install nload
    check_and_install sysstat
    check_and_install net-tools  # for netstat
    check_and_install openvswitch-switch  # for ovs-vsctl
    check_and_install tcpdump
    check_and_install dnsutils  # for dig
    check_and_install iproute2  # for ss
    check_and_install ifstat
    check_and_install python3
    check_and_install python3-pip

    # Dependencies for WeasyPrint and other related libraries
    check_and_install libpango-1.0-0
    check_and_install libpangoft2-1.0-0
    check_and_install libcairo2
    check_and_install libffi-dev
    check_and_install libssl-dev

    echo "Installing Speedtest CLI..."
    install_speedtest  # نصب Speedtest CLI

    echo "Checking for Python packages..."

    read -p "Do you want to upgrade pip to the latest version (Default NO)? (y/N): " UPGRADE_PIP
    UPGRADE_PIP=${UPGRADE_PIP:-n}
    if [[ "$UPGRADE_PIP" == "y" || "$UPGRADE_PIP" == "Y" ]]; then
        pip3 install --upgrade pip --break-system-packages || { echo "Failed to upgrade pip."; exit 1; }
    else
        echo "Skipping pip upgrade."
    fi

    check_and_install_pip matplotlib
    check_and_install_pip weasyprint
    check_and_install_pip requests

    echo "All dependencies were successfully installed."
}

install_dependencies

# Set permissions for the script and modules
if [ -f "$INSTALL_DIR/net-tool.sh" ]; then
    sudo chmod +x $INSTALL_DIR/net-tool.sh || { echo "Failed to set executable permission on net-tool.sh."; exit 1; }
else
    echo "$INSTALL_DIR/net-tool.sh not found!"
    exit 1
fi

# Set permissions for the install.sh script
if [ -f "$INSTALL_DIR/install.sh" ]; then
    sudo chmod +x $INSTALL_DIR/install.sh || { echo "Failed to set executable permission on install.sh."; exit 1; }
else
    echo "$INSTALL_DIR/install.sh not found!"
    exit 1
fi

if [ -d "$INSTALL_DIR/Module" ]; then
    sudo chmod +x $INSTALL_DIR/Module/*.sh || { echo "Failed to set executable permission on module scripts."; exit 1; }
else
    echo "$INSTALL_DIR/Module directory not found!"
    exit 1
fi

clear;echo "Installation complete! You can now run 'net-tool' from the terminal."
