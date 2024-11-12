#!/bin/bash
# Check if the script was called with 'net-tool update or net-tool uninstall'
if [ "$1" == "update" ]; then
    echo "Updating Network Tool..."
    curl -Ls https://raw.githubusercontent.com/090ebier/Network-Tool/main/install.sh -o /tmp/install.sh
    sudo bash /tmp/install.sh
    exit 0
elif [ "$1" == "uninstall" ]; then
    echo "Uninstalling Network Tool..."
    sudo rm -rf /opt/net-tool
    sudo rm /usr/local/bin/net-tool
    echo "Network Tool has been uninstalled."
    exit 0
fi

fi
trap "clear; echo 'Exiting Network Tool Management...'; exit" SIGINT
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges. Restarting with sudo..."
    exec sudo "$0" "$@"
    exit 1
fi

BASE_DIR=$(dirname "$(readlink -f "$0")")
TITLE="Network Management Tool"

if [ -z "$THEME" ]; then
    export THEME="dark"  # تم پیش‌فرض دارک
    export DIALOGRC="$BASE_DIR/dark_dialogrc" 
fi

make_modules_executable() {
    chmod +x $BASE_DIR/Module/network_config.sh
    chmod +x $BASE_DIR/Module/firewall_management.sh
    chmod +x $BASE_DIR/Module/ovs_management.sh
    chmod +x $BASE_DIR/Module/network_monitoring.sh
    chmod +x $BASE_DIR/Module/telegram_module.sh
    chmod +x $BASE_DIR/Module/resource_monitoring.sh
    chmod +x $BASE_DIR/install.sh
}

determine_network_config() {
    if systemctl is-active systemd-networkd > /dev/null 2>&1 || [ -d /etc/netplan ] && [ "$(ls -A /etc/netplan)" ]; then
        echo "Netplan"
    elif systemctl is-active NetworkManager > /dev/null 2>&1; then
        echo "NetworkManager"
    elif [ -f /etc/network/interfaces ]; then
        echo "Interfaces file"
    else
        echo "Unknown Configuration"
    fi
}

switch_theme() {
    if [ "$THEME" = "dark" ]; then
        unset DIALOGRC  
        export THEME="light"
    else
        export DIALOGRC="$BASE_DIR/dark_dialogrc"  
        export THEME="dark"
    fi
    main_menu 
}

main_menu() {
    OS_VERSION=$(uname -r)
    HOSTNAME=$(hostname)
    CPU_MODEL=$(lscpu | grep "Model name" | head -1 | awk -F ':' '{print $2}' | sed 's/^ *//g' | sed 's/ *$//g')
    RAM_TOTAL=$(free -h | grep "Mem" | awk '{print $2}')
    RAM_USED=$(free -h | grep "Mem" | awk '{print $3}')
    DISK_TOTAL=$(df -h | grep '/$' | awk '{print $2}')
    DISK_USED=$(df -h | grep '/$' | awk '{print $3}')
    NETWORK_CONFIG=$(determine_network_config)

    SYSTEM_INFO="OS Version: \Zb\Z4$OS_VERSION\Zn\nHostname: \Zb\Z4$HOSTNAME\Zn\nCPU: \Zb\Z3$CPU_MODEL\Zn\nRAM: \Zb\Z3$RAM_TOTAL used: \Zb\Z3$RAM_USED\Zn\nDisk: \Zb\Z3$DISK_TOTAL used: \Zb\Z3$DISK_USED\Zn\nNetwork Config: \Zb\Z1$NETWORK_CONFIG\Zn"

    if [ "$THEME" = "dark" ]; then
        THEME_OPTION="Switch to Light Theme"
    else
        THEME_OPTION="Switch to Dark Theme"
    fi

    dialog --colors --backtitle "$TITLE" --title "$TITLE" --menu "$SYSTEM_INFO\n\n\Zb\Z0Choose an option:\Zn" 22 70 7 \
        1 "\Zb\Z2Basic Linux Network Configuration\Zn" \
        2 "\Zb\Z2Firewall Management (NFTables)\Zn" \
        3 "\Zb\Z2Open vSwitch Management\Zn" \
        4 "\Zb\Z2Network Monitoring\Zn" \
        5 "\Zb\Z4Install Or Update Script\Zn" \
        6 "\Zb\Z3$THEME_OPTION\Zn" \
        7 "\Zb\Z1Exit\Zn" 2>tempfile

    choice=$(<tempfile)
    case $choice in
        1) clear;$BASE_DIR/Module/network_config.sh ;;
        2) clear;$BASE_DIR/Module/firewall_management.sh ;;
        3) clear;$BASE_DIR/Module/ovs_management.sh ;;
        4) clear;$BASE_DIR/Module/network_monitoring.sh ;;
        5) clear; curl -Ls https://raw.githubusercontent.com/090ebier/Network-Tool/main/install.sh -o /tmp/install.sh
        sudo bash /tmp/install.sh ;;
        6) switch_theme ;;  
        7) exit_script ;;
        *) echo "Invalid option"; main_menu ;;
    esac
}

exit_script() {
    dialog --colors --title "Goodbye" --msgbox "\n\Zb\Z1Thank you for using the Network Management Tool!\Zn\n\nGoodbye!" 10 50
    clear
    exit 0
}

trap "rm -f tempfile" EXIT


make_modules_executable
main_menu
