#!/bin/bash
BASE_DIR=$(dirname "$(readlink -f "$0")")
# Title of the script
TITLE="Network Management Tool"

# Use a dark theme dialog configuration file if it exists in the same directory
export DIALOGRC="$BASE_DIR/dark_dialogrc"

# Function to display a welcome message
welcome_message() {
    dialog --colors --title "Welcome" --msgbox "\n\Zb\Z4Welcome to the Network Management Tool!\Zn\n\nThis tool helps you manage network configurations and view system information in an intuitive interface." 10 60
}

make_modules_executable() {
    chmod +x $BASE_DIR/Module/network_config.sh
    chmod +x $BASE_DIR/Module/firewall_management.sh
    chmod +x $BASE_DIR/Module/ovs_management.sh
    chmod +x $BASE_DIR/Module/network_monitoring.sh
    chmod +x $BASE_DIR/Module/about_script.sh
}


# Function to determine network configuration type
determine_network_config() {
    if [ -f /etc/network/interfaces ]; then
        echo "Interfaces file"
    elif [ -f /etc/netplan ]; then
        echo "Netplan"
    else
        echo "Unknown Configuration"
    fi
}



# Display system information within the main menu
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
        1 "Basic Linux Network Configuration" \
        2 "Firewall Management (NFTables)" \
        3 "Open vSwitch Management" \
        4 "Network Monitoring" \
        5 "About Script" \
        6 "Exit" 2>tempfile

    choice=$(<tempfile)
    case $choice in
        1) $BASE_DIR/Module/network_config.sh ;;        # فراخوانی اسکریپت جداگانه برای تنظیمات شبکه
        2) $BASE_DIR/Module/firewall_management.sh ;;   # فراخوانی اسکریپت جداگانه برای مدیریت فایروال
        3) $BASE_DIR/Module/ovs_management.sh ;;        # فراخوانی اسکریپت جداگانه برای Open vSwitch
        4) $BASE_DIR/Module/network_monitoring.sh ;;    # فراخوانی اسکریپت جداگانه برای نظارت بر شبکه
        5) $BASE_DIR/Module/about_script.sh ;;          # فراخوانی اسکریپت جداگانه برای اطلاعات اسکریپت
        6) exit_script ;;                # تابع داخلی برای خروج از برنامه
        *) echo "Invalid option"; main_menu ;;
    esac
}

# Exit script with a goodbye message
exit_script() {
    dialog --colors --title "Goodbye" --msgbox "\n\Zb\Z1Thank you for using the Network Management Tool!\Zn\n\nGoodbye!" 10 50
    clear
    exit 0
}

# Clean up temporary file upon exit
trap "rm -f tempfile" EXIT

# Start the script with a welcome message and display the main menu
welcome_message
main_menu
