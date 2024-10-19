#!/bin/bash

trap "clear; echo 'Exiting Network Tool Management...'; exit" SIGINT
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges. Restarting with sudo..."
    exec sudo "$0" "$@"
    exit 1
fi

BASE_DIR=$(dirname "$(readlink -f "$0")")
TITLE="Network Management Tool"

# Flags to ensure theme selection and welcome message are shown only once
theme_selected=false
welcome_shown=false

# Function to choose theme (only once)
choose_theme() {
    if [ "$theme_selected" = false ]; then
        dialog --colors --title "Choose Theme" --menu "\n\Zb\Z4Choose your preferred theme:\Zn" 10 60 2 \
            1 "Dark Theme" \
            2 "Light Theme" 2>tempfile

        choice=$(<tempfile)
        case $choice in
            1)
                export DIALOGRC="$BASE_DIR/dark_dialogrc"
                ;;
            2)
                unset DIALOGRC
                ;;
            *)
                echo "Invalid option, defaulting to Dark Theme"
                export DIALOGRC="$BASE_DIR/dark_dialogrc"
                ;;
        esac
        theme_selected=true  # Mark the theme as selected
    fi
}

# Function to display a welcome message (only once)
welcome_message() {
    if [ "$welcome_shown" = false ]; then
        dialog --colors --title "Welcome" --msgbox "\n\Zb\Z4Welcome to the Network Management Tool!\Zn\n\nThis tool helps you manage network configurations and view system information in an intuitive interface." 10 60
        welcome_shown=true  # Mark the welcome message as shown
    fi
}

make_modules_executable() {
    chmod +x $BASE_DIR/Module/network_config.sh
    chmod +x $BASE_DIR/Module/firewall_management.sh
    chmod +x $BASE_DIR/Module/ovs_management.sh
    chmod +x $BASE_DIR/Module/network_monitoring.sh
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

    dialog --colors --backtitle "$TITLE" --title "$TITLE" --menu "$SYSTEM_INFO\n\n\Zb\Z0Choose an option:\Zn" 20 70 6 \
        1 "\Zb\Z2Basic Linux Network Configuration\Zn" \
        2 "\Zb\Z2Firewall Management (NFTables)\Zn" \
        3 "\Zb\Z2Open vSwitch Management\Zn" \
        4 "\Zb\Z2Network Monitoring\Zn" \
        5 "\Zb\Z2Install Or Update Script\Zn" \
        6 "\Zb\Z1Exit\Zn" 2>tempfile

    choice=$(<tempfile)
    case $choice in
        1) clear;$BASE_DIR/Module/network_config.sh "$0" "return_to_menu" ;;
        2) clear;$BASE_DIR/Module/firewall_management.sh "$0" "return_to_menu" ;;
        3) clear;$BASE_DIR/Module/ovs_management.sh "$0" "return_to_menu" ;;
        4) clear;$BASE_DIR/Module/network_monitoring.sh "$0" "return_to_menu" ;;
        5) clear;$BASE_DIR/install.sh "$0" "return_to_menu" ;;
        6) exit_script ;;
        *) echo "Invalid option"; main_menu ;;
    esac
}

exit_script() {
    dialog --colors --title "Goodbye" --msgbox "\n\Zb\Z1Thank you for using the Network Management Tool!\Zn\n\nGoodbye!" 10 50
    clear
    exit 0
}

trap "rm -f tempfile" EXIT

# Check if we're returning from a module
if [ "$2" = "return_to_menu" ]; then
    main_menu  # Skip theme and welcome message, directly to the menu
else
    make_modules_executable
    choose_theme  # Only once
    welcome_message  # Only once
    main_menu  # Main menu
fi