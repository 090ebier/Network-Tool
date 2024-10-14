#!/bin/bash

# Title of the script
TITLE="Network Management Tool"

# Use a dark theme dialog configuration file if it exists in the same directory
export DIALOGRC=./dark_dialogrc

# Function to display a welcome message
welcome_message() {
    dialog --colors --title "Welcome" --msgbox "\n\Zb\Z4Welcome to the Network Management Tool!\Zn\n\nThis tool helps you manage network configurations and view system information in an intuitive interface." 10 60
}

make_modules_executable() {
    chmod +x ./network_config.sh
    chmod +x ./firewall_management.sh
    chmod +x ./ovs_management.sh
    chmod +x ./network_monitoring.sh
    chmod +x ./about_script.sh
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



install_dependencies() {
    # فایل موقت برای ذخیره خروجی
    temp_log=$(mktemp)

    # لیست ابزارهای مورد نیاز (غیر پایتونی)
    dependencies=("dialog" "nload" "sysstat" "nftables" "net-tools" "openvswitch-switch" "tcpdump" "dnsutils" "iproute2" "ifstat" "python3" "python3-pip")

    # لیست پکیج‌های پایتونی برای نصب با pip
    python_packages=("matplotlib" "weasyprint" "requests")

    # بررسی نوع مدیر بسته (apt برای توزیع‌های Debian/Ubuntu و yum برای توزیع‌های CentOS/RedHat)
    echo "Checking for package manager..." | tee -a "$temp_log"
    echo "----------------------------------------" | tee -a "$temp_log"
    if command -v apt-get > /dev/null; then
        installer="apt-get"
        update_command="apt-get update -qq"
        check_installed="dpkg -l"
        install_flags="-y -qq"  # نصب بدون نمایش خروجی غیرضروری
        echo "Detected apt-get as package manager." | tee -a "$temp_log"
    elif command -v yum > /dev/null; then
        installer="yum"
        update_command="yum update -q"
        check_installed="yum list installed"
        install_flags="-y -q"  # نصب بدون نمایش خروجی غیرضروری
        echo "Detected yum as package manager." | tee -a "$temp_log"
    else
        echo "Error: No compatible package manager found (apt or yum)." | tee -a "$temp_log"
        exit 1
    fi

    # پرچم نصب بودن همه بسته‌ها
    all_installed=true

    # بررسی نصب بودن بسته‌های غیر پایتونی
    echo "----------------------------------------" | tee -a "$temp_log"
    echo "Checking system dependencies..." | tee -a "$temp_log"
    for package in "${dependencies[@]}"; do
        if $check_installed | grep -q "$package"; then
            echo "$package is already installed." | tee -a "$temp_log"
        else
            echo "$package is missing and will be installed." | tee -a "$temp_log"
            all_installed=false
        fi
    done

    # به‌روزرسانی لیست بسته‌ها (فقط برای بسته‌های غیر پایتونی)
    if ! $all_installed; then
        echo "----------------------------------------" | tee -a "$temp_log"
        echo "Updating package lists..." | tee -a "$temp_log"
        sudo $update_command > /dev/null 2>&1
    fi

    # نصب وابستگی‌های غیر پایتونی
    for package in "${dependencies[@]}"; do
        if ! $check_installed | grep -q "$package"; then
            echo "Installing $package..." | tee -a "$temp_log"
            sudo $installer install $install_flags $package > /dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                echo "$package installed successfully." | tee -a "$temp_log"
            else
                echo "Failed to install $package." | tee -a "$temp_log"
                exit 1
            fi
        fi
    done

    # بررسی نصب بودن پکیج‌های پایتونی
    echo "----------------------------------------" | tee -a "$temp_log"
    echo "Checking Python dependencies..." | tee -a "$temp_log"
    for py_package in "${python_packages[@]}"; do
        if python3 -m pip show "$py_package" > /dev/null 2>&1; then
            echo "Python package $py_package is already installed." | tee -a "$temp_log"
        else
            echo "Installing Python package: $py_package..." | tee -a "$temp_log"
            python3 -m pip install "$py_package" > /dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                echo "$py_package installed successfully." | tee -a "$temp_log"
            else
                echo "Failed to install Python package: $py_package." | tee -a "$temp_log"
                exit 1
            fi
        fi
    done

    echo "----------------------------------------" | tee -a "$temp_log"
    echo "All dependencies are installed successfully." | tee -a "$temp_log"
    echo "----------------------------------------" | tee -a "$temp_log"

    # نمایش فایل خروجی به کاربر
    less "$temp_log"
    # حذف فایل موقت بعد از نمایش
    rm -f "$temp_log"
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
        1) ./network_config.sh ;;        # فراخوانی اسکریپت جداگانه برای تنظیمات شبکه
        2) ./firewall_management.sh ;;   # فراخوانی اسکریپت جداگانه برای مدیریت فایروال
        3) ./ovs_management.sh ;;        # فراخوانی اسکریپت جداگانه برای Open vSwitch
        4) ./network_monitoring.sh ;;    # فراخوانی اسکریپت جداگانه برای نظارت بر شبکه
        5) ./about_script.sh ;;          # فراخوانی اسکریپت جداگانه برای اطلاعات اسکریپت
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
install_dependencies
welcome_message
main_menu
