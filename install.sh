#!/bin/bash

# 1. کلون کردن پروژه از گیت‌هاب
INSTALL_DIR="/opt/net-tool"
REPO_URL="https://github.com/090ebier/Network-Tool.git"

echo "Cloning the project from GitHub..."
if sudo git clone $REPO_URL $INSTALL_DIR; then
    echo "Project cloned successfully."
else
    echo "Failed to clone the project from GitHub."
    exit 1
fi

# 2. ایجاد symlink برای اجرای دستور net-tool از هر جا
BIN_DIR="/usr/local/bin"
echo "Creating symlink in $BIN_DIR..."
if sudo ln -sf $INSTALL_DIR/net-tool.sh $BIN_DIR/net-tool; then
    echo "Symlink created successfully."
else
    echo "Failed to create symlink in $BIN_DIR."
    exit 1
fi

check_and_install() {
    PKG_NAME=$1
    if ! dpkg -s $PKG_NAME >/dev/null 2>&1; then
        echo "$PKG_NAME is not installed. Installing..."
        sudo apt install -y $PKG_NAME || { echo "Failed to install $PKG_NAME."; exit 1; }
    else
        echo "$PKG_NAME is already installed."
    fi
}

check_and_install_pip() {
    PIP_PKG_NAME=$1
    if ! pip3 show $PIP_PKG_NAME >/dev/null 2>&1; then
        echo "$PIP_PKG_NAME is not installed. Installing with pip..."
        pip3 install $PIP_PKG_NAME || { echo "Failed to install Python package: $PIP_PKG_NAME."; exit 1; }
    else
        echo "$PIP_PKG_NAME is already installed."
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

    echo "Checking for Python packages..."

    pip3 install --upgrade pip || { echo "Failed to upgrade pip."; exit 1; }

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

if [ -d "$INSTALL_DIR/Module" ]; then
    sudo chmod +x $INSTALL_DIR/Module/*.sh || { echo "Failed to set executable permission on module scripts."; exit 1; }
else
    echo "$INSTALL_DIR/Module directory not found!"
    exit 1
fi

echo "Installation complete! You can now run 'net-tool' from the terminal."
