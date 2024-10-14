#!/bin/bash

# 1. ایجاد پوشه در /opt/ برای اسکریپت‌ها
INSTALL_DIR="/opt/net-tool"
BIN_DIR="/usr/local/bin"

echo "Installing net-tool to $INSTALL_DIR..."

# 2. ساخت دایرکتوری در /opt/net-tool/ و کپی کردن فایل‌ها
sudo mkdir -p $INSTALL_DIR
sudo cp -r ./* $INSTALL_DIR

# 3. ایجاد symlink برای اجرای دستور net-tool از هر جا
echo "Creating symlink in $BIN_DIR..."
sudo ln -sf $INSTALL_DIR/net-tool.sh $BIN_DIR/net-tool

    echo "Installing dependencies..."

    # چک و نصب پیش نیازهای سیستم
    sudo apt update
    sudo apt install -y dialog nftables nload sysstat net-tools openvswitch-switch tcpdump dnsutils iproute2 ifstat python3 python3-pip

    # نصب پکیج های پایتونی
    sudo python3 -m pip install --upgrade pip --ignore-installed --break-system-packages
    sudo python3 -m pip install matplotlib weasyprint requests --ignore-installed --break-system-packages


    echo "Dependencies installed successfully."

sudo chmod +x $INSTALL_DIR/net-tool.sh
sudo chmod +x $INSTALL_DIR/Module/*.sh

echo "Installation complete! You can now run 'net-tool' from the terminal."

