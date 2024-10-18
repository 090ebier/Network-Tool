#!/bin/bash
BASE_DIR=$(dirname "$(readlink -f "$0")")
TITLE="Network Monitoring"

get_terminal_size() {
    term_height=$(tput lines)
    term_width=$(tput cols)
    dialog_height=$((term_height - 5))
    dialog_width=$((term_width - 10))
    if [ "$dialog_height" -lt 15 ]; then dialog_height=15; fi
    if [ "$dialog_width" -lt 50 ]; then dialog_width=50; fi
}

# Function to ping devices and display live results

# تابع پینگ دستگاه‌ها و نمایش نتایج به‌صورت زنده
function ping_devices() {
    get_terminal_size

    # گرفتن IPها و تنظیمات از کاربر
    devices=$(dialog --colors --backtitle "\Zb\Z4Ping Devices\Zn" --title "\Zb\Z3Enter IP Addresses\Zn" \
        --inputbox "Enter IP addresses to ping (comma-separated):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$devices" ]; then
        dialog --msgbox "No IP addresses entered." 10 30
        return  # بازگشت به منوی قبلی در صورت کنسل کردن
    fi

    ping_count=$(dialog --colors --backtitle "\Zb\Z4Ping Devices\Zn" --title "\Zb\Z3Number of Pings\Zn" \
        --inputbox "Enter the number of pings to send:" "$dialog_height" "$dialog_width" 3 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$ping_count" ]; then
        ping_count=3  # مقدار پیش‌فرض 3
    fi  

    timeout=$(dialog --colors --backtitle "\Zb\Z4Ping Devices\Zn" --title "\Zb\Z3Ping Timeout\Zn" \
        --inputbox "Enter timeout for each ping (in seconds):" "$dialog_height" "$dialog_width" 1 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$timeout" ]; then
        timeout=1  # مقدار پیش‌فرض 1
    fi  

    # تبدیل IPها به آرایه
    IFS=',' read -ra ip_array <<< "$devices"

    # ایجاد فایل موقت برای ذخیره نتایج
    tmpfile=$(mktemp)

    # خروجی جدول پینگ
    echo -e "| IP Address     | Status                | Time (ms) | Packet Loss |" > $tmpfile
    echo -e "------------------------------------------------------------------" >> $tmpfile

    (
    for ip in "${ip_array[@]}"; do
        unknown_host=0  

        for ((i = 1; i <= ping_count; i++)); do
            if [ "$unknown_host" -eq 1 ]; then
                break
            fi

            # ارسال پینگ و بررسی نتیجه
            ping_result=$(ping -c 1 -W "$timeout" "$ip" 2>&1)

            if echo "$ping_result" | grep -q "Name or service not known"; then
                status="Unknown Host"
                time="-"
                loss="N/A"
                unknown_host=1  
            elif echo "$ping_result" | grep -q "0 received"; then
                status="Not Reachable"
                time="-"
                loss="100%"
            elif echo "$ping_result" | grep -q "100% packet loss"; then
                status="Reachable but 100% Packet Loss"
                time="-"
                loss="100%"
            elif echo "$ping_result" | grep -q "Destination Host Unreachable"; then
                status="Host Unreachable"
                time="-"
                loss="100%"
            else
                status="Reachable"
                time=$(echo "$ping_result" | awk -F'/' '/rtt/ {print $5}')  # میانگین زمان پینگ
                loss=$(echo "$ping_result" | grep -oP '\d+(?=% packet loss)')
            fi

            printf "| %-14s | %-20s | %-9s | %-11s |\n" "$ip" "$status" "$time" "$loss%" >> $tmpfile

            echo "---"
            tail -n 10 $tmpfile  
            echo "---"
            sleep 0.5  
        done
    done

    echo "----"
    echo -e "\nPing operation completed. Press OK to return." >> $tmpfile
    echo "---"
    ) | dialog --colors --backtitle "\Zb\Z4Ping Devices\Zn" --title "\Zb\Z3Ping Results (Live)\Zn" --progressbox "$dialog_height" "$dialog_width"

    dialog --textbox $tmpfile "$dialog_height" "$dialog_width"
    rm -f $tmpfile

    # افزودن منوی انتخاب پس از پایان
    dialog --yesno "Do you want to ping again?" 10 30
    response=$?
    if [ $response -eq 0 ]; then
        ping_devices  # اگر کاربر "Yes" را انتخاب کند، به تابع ping_devices برگردد.
    else
        device_monitoring_submenu  # اگر کاربر "No" را انتخاب کند، به منوی device_monitoring_submenu برگردد.
    fi
}

view_connections() {
    get_terminal_size
    # مسیر برای ذخیره‌سازی خروجی‌ها
    backup_dir="$PWD/backup_Log/Network_Monitoring/View_Connection/"

    # ایجاد دایرکتوری‌ها اگر وجود ندارند
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi

    while true; do
        # انتخاب فیلتر
        filter=$(dialog --colors --menu "\Zb\Z2Choose Filter for Viewing Connections\Zn" "$dialog_height" "$dialog_width" 5 \
            1 "\Zb\Z2View All Active Connections\Zn" \
            2 "\Zb\Z2View Listening Ports\Zn" \
            3 "\Zb\Z2Filter by Port or Protocol\Zn" \
            4 "\Zb\Z2View Saved Outputs\Zn" \
            5 "\Zb\Z1Return to Main Menu\Zn" 3>&1 1>&2 2>&3)

        case $filter in
            1)
                # نمایش تمام اتصالات فعال با جداول زیبا و رنگ‌بندی
                ss -tunap | awk 'BEGIN {print "| Protocol | Source IP:Port         | Destination IP:Port    | Status          | Process"; print "----------------------------------------------------------------------------------------------"} \
                {split($5, src, ":"); split($6, dst, ":"); printf "| %-8s | %-21s | %-21s | %-15s | %s\n", $1, src[1] ":" src[2], dst[1] ":" dst[2], $4, $7}' > /tmp/connections.txt
                dialog --colors --backtitle "\Zb\Z4Active Connections\Zn" --textbox /tmp/connections.txt 30 100

                # پرسش برای ذخیره‌سازی
                dialog --yesno "Do you want to save the output to a text file?" 7 40
                if [ $? = 0 ]; then
                    timestamp=$(date +"%Y-%m-%d_%H-%M")
                    filename=$(dialog --inputbox "Enter the file name to save (without extension):" 10 30 3>&1 1>&2 2>&3)
                    full_filename="${backup_dir}${filename}_${timestamp}.txt"
                    cp /tmp/connections.txt "$full_filename"
                    dialog --msgbox "Output saved to $full_filename" 7 40
                fi
                ;;
            2)
                # نمایش پورت‌های در حالت Listen
                ss -tunlp | awk 'BEGIN {print "| Protocol | Local Address:Port    | PID/Program name"; print "---------------------------------------------------------"} \
                {split($4, local, ":"); printf "| %-8s | %-21s | %-30s\n", $1, local[1] ":" local[2], $NF}' > /tmp/listening_ports.txt
                dialog --colors --backtitle "\Zb\Z4Listening Ports\Zn" --textbox /tmp/listening_ports.txt 30 100

                # پرسش برای ذخیره‌سازی
                dialog --yesno "Do you want to save the output to a text file?" 7 40
                if [ $? = 0 ]; then
                    timestamp=$(date +"%Y-%m-%d_%H-%M")
                    filename=$(dialog --inputbox "Enter the file name to save (without extension):" 10 30 3>&1 1>&2 2>&3)
                    full_filename="${backup_dir}${filename}_${timestamp}.txt"
                    cp /tmp/listening_ports.txt "$full_filename"
                    dialog --msgbox "Output saved to $full_filename" 7 40
                fi
                ;;
            3)
                while true; do
                    # فیلتر بر اساس پروتکل یا پورت
                    protocol=$(dialog --colors --menu "\Zb\Z2Choose Protocol\Zn" "$dialog_height" "$dialog_width" 3 \
                        1 "\Zb\Z2TCP\Zn" \
                        2 "\Zb\Z2UDP\Zn" \
                        3 "\Zb\Z1Back\Zn" 3>&1 1>&2 2>&3)

                    if [ "$protocol" = "3" ]; then
                        break  # بازگشت به منوی اصلی
                    fi

                    # پروتکل پیش‌فرض TCP باشد
                    if [ -z "$protocol" ]; then
                        protocol=1
                    fi

                    # فیلتر پورت با پیش‌فرض خالی برای همه پورت‌ها
                    port=$(dialog --inputbox "Enter port to filter (or leave blank for all ports):" 10 30 3>&1 1>&2 2>&3)

                    if [ "$protocol" = "1" ]; then
                        if [ -z "$port" ]; then
                            # اگر پورت وارد نشده باشد، همه اتصالات TCP نمایش داده می‌شوند
                            ss -t | awk 'BEGIN {print "| Protocol | Source IP:Port         | Destination IP:Port    | Status"; print "----------------------------------------------------------------------------------------------"} \
                            {split($5, src, ":"); split($6, dst, ":"); printf "| %-8s | %-21s | %-21s | %-15s\n", $1, src[1] ":" src[2], dst[1] ":" dst[2], $4}' > /tmp/tcp_connections.txt
                        else
                            # فیلتر کردن TCP با پورت خاص
                            ss -t state established '( sport = :'"$port"' or dport = :'"$port"' )' | awk 'BEGIN {print "| Protocol | Source IP:Port         | Destination IP:Port    | Status"; print "----------------------------------------------------------------------------------------------"} \
                            {split($5, src, ":"); split($6, dst, ":"); printf "| %-8s | %-21s | %-21s | %-15s\n", $1, src[1] ":" src[2], dst[1] ":" dst[2], $4}' > /tmp/tcp_connections.txt
                        fi
                        dialog --colors --backtitle "\Zb\Z4TCP Connections\Zn" --textbox /tmp/tcp_connections.txt 30 100
                    elif [ "$protocol" = "2" ]; then
                        if [ -z "$port" ]; then
                            # اگر پورت وارد نشده باشد، همه اتصالات UDP نمایش داده می‌شوند
                            ss -u | awk 'BEGIN {print "| Protocol | Source IP:Port         | Destination IP:Port    | Status"; print "----------------------------------------------------------------------------------------------"} \
                            {split($5, src, ":"); split($6, dst, ":"); printf "| %-8s | %-21s | %-21s | %-15s\n", $1, src[1] ":" src[2], dst[1] ":" dst[2], $4}' > /tmp/udp_connections.txt
                        else
                            # فیلتر کردن UDP با پورت خاص
                            ss -u state established '( sport = :'"$port"' or dport = :'"$port"' )' | awk 'BEGIN {print "| Protocol | Source IP:Port         | Destination IP:Port    | Status"; print "----------------------------------------------------------------------------------------------"} \
                            {split($5, src, ":"); split($6, dst, ":"); printf "| %-8s | %-21s | %-21s | %-15s\n", $1, src[1] ":" src[2], dst[1] ":" dst[2], $4}' > /tmp/udp_connections.txt
                        fi
                        dialog --colors --backtitle "\Zb\Z4UDP Connections\Zn" --textbox /tmp/udp_connections.txt 30 100
                    fi

                    # پرسش برای ذخیره‌سازی
                    dialog --yesno "Do you want to save the output to a text file?" 7 40
                    if [ $? = 0 ]; then
                        timestamp=$(date +"%Y-%m-%d_%H-%M")
                        filename=$(dialog --inputbox "Enter the file name to save (without extension):" 10 30 3>&1 1>&2 2>&3)
                        full_filename="${backup_dir}${filename}_${timestamp}.txt"
                        cp /tmp/tcp_connections.txt "$full_filename"
                        dialog --msgbox "Output saved to $full_filename" 7 40
                    fi
                done
                ;;
            4)
                # مسیر فولدر پشتیبان
                backup_files=$(ls "$backup_dir"/*.txt 2>/dev/null)
                if [ -z "$backup_files" ]; then
                    dialog --msgbox "No backup files found in $backup_dir!" 7 40
                    view_connections
                fi

                # ساخت لیستی از فایل‌ها با شماره‌گذاری
                file_list=()
                declare -A file_map  # برای نگهداری مسیر کامل فایل‌ها

                for file in $backup_files; do
                    filename=$(basename "$file")  # فقط نام فایل بدون مسیر
                    file_list+=("$filename" "")  # فایل را به لیست اضافه می‌کنیم
                    file_map["$filename"]="$file"  # مسیر کامل فایل را در file_map ذخیره می‌کنیم
                done

                # نمایش لیست فایل‌های بکاپ به کاربر برای انتخاب
                selected_backup=$(dialog --colors --menu "\Zb\Z2Select a file to view\Zn" "$dialog_height" "$dialog_width" 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

                # بررسی اینکه کاربر فایلی انتخاب کرده یا خیر
                if [ $? -ne 0 ] || [ -z "$selected_backup" ]; then
                    dialog --msgbox "No file selected!" 7 40
                    view_connections
                fi

                # دریافت مسیر کامل فایل انتخاب‌شده از file_map
                selected_backup_full_path="${file_map[$selected_backup]}"

                # نمایش محتوای فایل انتخاب‌شده
                if [ -f "$selected_backup_full_path" ]; then
                    dialog --colors --backtitle "\Zb\Z4Saved Output\Zn" --textbox "$selected_backup_full_path" 30 100
                    view_connections
                else
                    dialog --msgbox "Error: File not found or cannot be opened." 7 40
                    view_connections
                fi
                ;;
            5)
                # خروج از برنامه
                clear
                exit 0
                ;;
        esac
    done
}

# Function to monitor and manage DNS-related tasks
function monitor_dns() {
    get_terminal_size  # تابع برای دریافت ابعاد ترمینال

    # مسیر جدید برای ذخیره لاگ‌ها
    backup_dir="$PWD/backup_Log/Network_Monitoring/Monitor_DNS"
    mkdir -p "$backup_dir"  # ایجاد دایرکتوری اگر وجود ندارد

    while true; do
        # نمایش منوی اصلی مانیتورینگ DNS
        action=$(dialog --colors --menu "\Zb\Z2DNS Monitoring Options\Zn" "$dialog_height" "$dialog_width" 6 \
            1 "\Zb\Z2Live DNS Query Monitoring\Zn" \
            2 "\Zb\Z2Test DNS Performance\Zn" \
            3 "\Zb\Z2Clear DNS Cache\Zn" \
            4 "\Zb\Z2View DNS Cache\Zn" \
            5 "\Zb\Z2View Saved DNS Logs\Zn" \
            6 "\Zb\Z1Back to Main Menu\Zn" 3>&1 1>&2 2>&3)

        case $action in
            1)
                # نمایش لیست اینترفیس‌های شبکه و انتخاب اینترفیس
                interfaces=$(ip -o link show | awk -F': ' '{print $2}')
                interface_list=()
                for iface in $interfaces; do
                    interface_list+=("$iface" "")
                done

                interface=$(dialog --colors --menu "\Zb\Z2Select a network interface for monitoring\Zn" "$dialog_height" "$dialog_width" 6 "${interface_list[@]}" 3>&1 1>&2 2>&3)

                if [ -z "$interface" ]; then
                    dialog --msgbox "No interface selected!" 10 40
                    continue
                fi
                
                clear
                log_file="$backup_dir/dns_log_$(date +'%Y-%m-%d_%H-%M-%S').txt"
                echo "Monitoring DNS Queries on $interface (Press Ctrl+C to stop)..."

                # مانیتورینگ زنده درخواست‌های DNS
                sudo tcpdump -i "$interface" -l -n port 53 | awk 'BEGIN {print "| Timestamp        | Source IP       | Query Type | Query\n"} \
                {print "| " strftime("%Y-%m-%d %H:%M:%S") " | " $3 " | " $6 " | " $8 }' | tee "$log_file"

                # بعد از زدن Ctrl+C از کاربر بپرسد که آیا قصد ذخیره لاگ‌ها را دارد یا خیر
                dialog --yesno "Do you want to save the DNS logs?" 10 40
                if [ $? -eq 0 ]; then
                    dialog --msgbox "Logs saved to $log_file" 10 40
                else
                    rm -f "$log_file"
                    dialog --msgbox "Logs discarded." 10 40
                fi
                ;;

            2)
                # تست عملکرد DNS با انتخاب سرورهای DNS توسط کاربر یا استفاده از DNSهای معروف
                dns_servers_input=$(dialog --colors --inputbox "\Zb\Z2Enter DNS servers (comma-separated) or leave empty for default:\Zn" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                
                # تنظیم سرورهای پیش‌فرض اگر کاربر ورودی نداد
                if [ -z "$dns_servers_input" ]; then
                    dns_servers=("8.8.8.8" "1.1.1.1" "9.9.9.9")
                else
                    IFS=',' read -ra dns_servers <<< "$dns_servers_input"
                fi

                # پاک کردن فایل لاگ قبلی
                log_file="/tmp/dns_performance.txt"
                > "$log_file"

                # نوشتن عناوین ستون‌ها
                echo -e "| DNS Server   | Response Time (ms) |\n--------------------------------------" > "$log_file"

                # تست کردن هر سرور DNS
                for server in "${dns_servers[@]}"; do
                    time=$(dig google.com @$server | grep 'Query time' | awk '{print $4}')
                    if [ -z "$time" ]; then
                        time="N/A"
                    fi
                    printf "| %-12s | %-18s |\n" "$server" "$time" >> "$log_file"
                done

                # نمایش فایل لاگ با استفاده از dialog
                dialog --colors --textbox "$log_file" "$dialog_height" "$dialog_width"
                ;;

            3)
                # پاک کردن کش DNS با تایید کاربر
                dialog --colors --yesno "\Zb\Z2Are you sure you want to clear the DNS cache?\Zn" 10 40
                if [ $? -eq 0 ]; then
                    sudo systemctl restart systemd-resolved
                    dialog --colors --msgbox "\Zb\Z2DNS Cache Cleared!\Zn" 10 40
                else
                    dialog --colors --msgbox "\Zb\Z2Action canceled.\Zn" 10 40
                fi
                ;;

            4)
                # نمایش کش DNS
                dialog --infobox "Viewing DNS Cache..." 3 50
                resolvectl dns > /tmp/dns_cache.txt
                dialog --colors --textbox /tmp/dns_cache.txt "$dialog_height" "$dialog_width"
                ;;

            5)
                # نمایش لاگ‌های ذخیره‌شده
                saved_logs=$(ls "$backup_dir"/*.txt 2>/dev/null)
                if [ -z "$saved_logs" ]; then
                    dialog --colors --msgbox "\Zb\Z2No saved DNS logs found.\Zn" 10 40
                else
                    log_list=()
                    for file in $saved_logs; do
                        log_list+=("$(basename "$file")" "")
                    done
                    selected_log=$(dialog --colors --menu "\Zb\Z2Select a DNS log to view\Zn" "$dialog_height" "$dialog_width" 10 "${log_list[@]}" 3>&1 1>&2 2>&3)
                    if [ -n "$selected_log" ]; then
                        dialog --colors --textbox "$backup_dir/$selected_log" "$dialog_height" "$dialog_width"
                    fi
                fi
                ;;

            6)
                break
                ;;

            *)
                dialog --colors --msgbox "\Zb\Z1Invalid option selected!\Zn" 10 40
                ;;
        esac
    done
}


#################################################################

function view_port_table() {
    get_terminal_size  # تنظیم ابعاد ترمینال

    # انتخاب پروتکل با استفاده از منو و رنگ‌بندی
    protocol=$(dialog --colors --menu "\Zb\Z2Choose protocol type\Zn" "$dialog_height" "$dialog_width" 2 \
        1 "\Zb\Z2TCP\Zn" \
        2 "\Zb\Z2UDP\Zn" 3>&1 1>&2 2>&3)
    
    # اگر کاربر کنسل کند یا ورودی نامعتبر باشد
    if [[ -z "$protocol" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No valid protocol selected.\Zn" 5 40
        port_traffic_monitoring_submenu
        return
    fi

    # تبدیل انتخاب به رشته (tcp یا udp)
    if [[ "$protocol" == "1" ]]; then
        protocol="tcp"
    elif [[ "$protocol" == "2" ]]; then
        protocol="udp"
    fi

    # سوال از کاربر برای نمایش فقط پورت‌های Listening
    dialog --colors --yesno "\Zb\Z2Do you want only listening ports?\Zn" 7 40
    response=$?

    # تنظیم فلگ listening بر اساس انتخاب کاربر
    if [[ $response -eq 0 ]]; then
        listening_flag="-l"
    else
        listening_flag=""
    fi

    # نمایش پیام قبل از نشان دادن نتیجه
    dialog --infobox "Displaying open ports for protocol $protocol..." 5 50
    sleep 2

    # دریافت جدول پورت‌ها با استفاده از ss
    result=$(sudo ss -tuln | grep "$protocol" | awk '{print $1, $4, $5, $6}')

    # اگر نتیجه خالی بود، نمایش پیام خطا
    if [[ -z "$result" ]]; then
        dialog --colors --msgbox "\Zb\Z1No open ports found for protocol $protocol.\Zn" 5 50
        port_traffic_monitoring_submenu
    else
        # نمایش نتیجه در یک باکس اسکرولی
        dialog --colors --msgbox "\Zb\Z2Open Ports for $protocol:\n\Zn$result" "$dialog_height" "$dialog_width"
        port_traffic_monitoring_submenu
    fi
}


function check_specific_port() {
    get_terminal_size  # تنظیم ابعاد ترمینال

    # دریافت شماره پورت از کاربر با استفاده از dialog
    port=$(dialog --colors --inputbox "\Zb\Z2Enter the port number to check:\Zn" 8 40 3>&1 1>&2 2>&3)

    # بررسی معتبر بودن شماره پورت (فقط اعداد)
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: Please enter a valid numeric port number.\Zn" 5 40
        port_traffic_monitoring_submenu
        return
    fi

    # انتخاب پروتکل با استفاده از dialog و رنگ‌بندی
    protocol=$(dialog --colors --menu "\Zb\Z2Choose protocol type\Zn" "$dialog_height" "$dialog_width" 2 \
        1 "\Zb\Z2TCP\Zn" \
        2 "\Zb\Z2UDP\Zn" 3>&1 1>&2 2>&3)
    
    # اگر کاربر کنسل کند یا ورودی نامعتبر باشد
    if [[ -z "$protocol" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No valid protocol selected.\Zn" 5 40
        port_traffic_monitoring_submenu
        return
    fi

    # تبدیل انتخاب به رشته (tcp یا udp)
    if [[ "$protocol" == "1" ]]; then
        protocol="tcp"
    elif [[ "$protocol" == "2" ]]; then
        protocol="udp"
    fi

    # نمایش پیام قبل از بررسی پورت
    dialog --infobox "Checking if port $port is in use for protocol $protocol..." 5 50
    sleep 2

    # بررسی استفاده از پورت با استفاده از ss
    result=$(sudo ss -tuln | grep ":$port " | grep "$protocol")

    # اگر نتیجه خالی بود، پورت در استفاده نیست
    if [[ -z "$result" ]]; then
        dialog --colors --msgbox "\Zb\Z1Port $port is not in use for protocol $protocol.\Zn" 5 50
        port_traffic_monitoring_submenu
    else
        # نمایش جزئیات پورت مورد استفاده
        dialog --colors --msgbox "\Zb\Z2Port $port is in use:\Zn\n\n$result" "$dialog_height" "$dialog_width"

        # بررسی برای سرویس یا فرآیند با استفاده از lsof
        service_info=$(sudo lsof -i :$port)

        if [[ -z "$service_info" ]]; then
            dialog --colors --msgbox "\Zb\Z1No specific service found using port $port.\Zn" 5 50
            port_traffic_monitoring_submenu
        else
            # نمایش اطلاعات سرویس
            dialog --colors --msgbox "\Zb\Z2Service information for port $port:\Zn\n\n$service_info" "$dialog_height" "$dialog_width"
            port_traffic_monitoring_submenu
        fi
    fi
}


function monitor_ports_and_traffic() {
    get_terminal_size  # تنظیم ابعاد ترمینال
    log_dir="$PWD/backup_Log/Network_Monitoring/Monitor_Ports_And_Traffic"

    # ایجاد دایرکتوری اگر وجود نداشته باشد
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi

    declare -A file_map  # تعریف آرایه‌ی انجمنی برای نگهداری نام فایل و مسیر آن

    while true; do
        # نمایش منو با گزینه‌های مختلف برای مانیتورینگ
        choice=$(dialog --colors --menu "\Zb\Z2Network Monitor Menu\Zn" "$dialog_height" "$dialog_width" 4 \
            1 "\Zb\Z2Monitor Ports and Traffic\Zn" \
            2 "\Zb\Z2Display Logs\Zn" \
            3 "\Zb\Z2Delete Logs\Zn" \
            4 "\Zb\Z1Exit\Zn" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                # مانیتورینگ پورت‌ها و ترافیک
                mode=$(dialog --colors --menu "\Zb\Z2Choose monitoring mode\Zn" "$dialog_height" "$dialog_width" 2 \
                    1 "\Zb\Z2Monitor all traffic\Zn" \
                    2 "\Zb\Z2Monitor specific port\Zn" 3>&1 1>&2 2>&3)

                if [[ -z "$mode" ]]; then
                    dialog --colors --msgbox "\Zb\Z1Error: No valid option selected.\Zn" 5 40
                    continue
                fi

                tcpdump_cmd="sudo tcpdump -n -q"

                if [[ "$mode" == "2" ]]; then
                    port=$(dialog --colors --inputbox "\Zb\Z2Enter the port number to monitor:\Zn" 8 40 3>&1 1>&2 2>&3)

                    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
                        dialog --colors --msgbox "\Zb\Z1Error: Please enter a valid numeric port number.\Zn" 5 40
                        continue
                    fi

                    tcpdump_cmd="$tcpdump_cmd port $port"
                fi

                dialog --yesno "Do you want to save the output to a log file?" 7 40
                save_log=$?

                if [[ $save_log -eq 0 ]]; then
                    log_file=$(dialog --colors --inputbox "\Zb\Z2Enter the log file name (without extension):\Zn" 8 40 3>&1 1>&2 2>&3)

                    if [[ -z "$log_file" ]]; then
                        dialog --colors --msgbox "\Zb\Z1Error: Log file name cannot be empty.\Zn" 5 40
                        continue
                    fi

                    # ذخیره لاگ به عنوان یک فایل متنی
                    log_file="$log_dir/$log_file.txt"
                    tcpdump_cmd="$tcpdump_cmd -nn -q -tttt | tee $log_file"
                    dialog --colors --msgbox "\Zb\Z2Monitoring traffic and saving to $log_file. Press Ctrl+C to stop.\Zn" 7 50
                else
                    dialog --colors --msgbox "\Zb\Z2Monitoring traffic in real-time. Press Ctrl+C to stop.\Zn" 7 50
                fi

                clear
                eval $tcpdump_cmd
                ;;

            2)
                # نمایش لاگ‌ها
                log_files=$(ls -1 "$log_dir"/*.txt 2>/dev/null)

                if [[ -z "$log_files" ]]; then
                    dialog --colors --msgbox "\Zb\Z1No logs found.\Zn" 5 40
                    continue
                fi

                # ساخت لیست فایل‌ها برای نمایش در منو
                file_list=()
                index=1

                for log_file_path in "$log_dir"/*.txt; do
                    file_name=$(basename "$log_file_path")
                    file_map["$file_name"]="$log_file_path"  # مپ کردن نام فایل به مسیر کامل
                    file_list+=("$index" "$file_name")
                    index=$((index + 1))
                done

                # نمایش منوی لاگ‌ها برای انتخاب
                log_choice=$(dialog --colors --menu "\Zb\Z2Choose a log to display\Zn" 15 60 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

                if [[ -n "$log_choice" ]]; then
                    selected_file_name="${file_list[$((log_choice * 2 - 1))]}"  # دریافت نام فایل انتخابی
                    selected_file_path="${file_map[$selected_file_name]}"  # دریافت مسیر کامل فایل
                    dialog --textbox "$selected_file_path" 20 80
                fi
                ;;

            3)
                # حذف لاگ‌ها
                log_files=$(ls -1 "$log_dir"/*.txt 2>/dev/null)

                if [[ -z "$log_files" ]]; then
                    dialog --colors --msgbox "\Zb\Z1No logs found.\Zn" 5 40
                    continue
                fi

                # ساخت لیست فایل‌ها برای حذف
                file_list=()
                index=1

                for log_file_path in "$log_dir"/*.txt; do
                    file_name=$(basename "$log_file_path")
                    file_map["$file_name"]="$log_file_path"  # مپ کردن نام فایل به مسیر کامل
                    file_list+=("$index" "$file_name")
                    index=$((index + 1))
                done

                # نمایش لیست لاگ‌ها برای حذف
                log_choice=$(dialog --colors --menu "\Zb\Z2Choose a log to delete\Zn" 15 60 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

                if [[ -n "$log_choice" ]]; then
                    selected_file_name="${file_list[$((log_choice * 2 - 1))]}"  # دریافت نام فایل انتخابی
                    selected_file_path="${file_map[$selected_file_name]}"  # دریافت مسیر کامل فایل

                    dialog --yesno "Are you sure you want to delete $selected_file_name?" 7 40
                    delete_confirmation=$?

                    if [[ $delete_confirmation -eq 0 ]]; then
                        rm -f "$selected_file_path"
                        dialog --colors --msgbox "\Zb\Z2Log $selected_file_name has been deleted.\Zn" 5 40
                    fi
                fi
                ;;

            4)
                break
                ;;

            *)
                dialog --colors --msgbox "\Zb\Z1Invalid option. Please try again.\Zn" 5 40
                ;;
        esac
    done

    # پاک کردن صفحه هنگام خروج
    clear
}


#################################################################
function monitor_bandwidth() {
    get_terminal_size  # دریافت ابعاد ترمینال برای تنظیم بهتر نمایش

    # گرفتن لیست اینترفیس‌های شبکه (بدون loopback 'lo')
    interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)

    # بررسی اینکه آیا اینترفیس موجود است
    if [[ -z "$interfaces" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No network interfaces found.\Zn" 5 40
        bandwidth_reports_submenu  # بازگشت به منوی گزارش پهنای باند
        return
    fi

    # آماده‌سازی لیست اینترفیس‌ها برای نمایش در منو
    interface_list=()
    index=1
    for interface in $interfaces; do
        interface_list+=("$index" "$interface")
        index=$((index + 1))
    done

    # نمایش منوی انتخاب اینترفیس شبکه برای مانیتورینگ
    selected_index=$(dialog --colors --menu "\Zb\Z2Choose a network interface to monitor:\Zn" "$dialog_height" "$dialog_width" 10 "${interface_list[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$selected_index" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No interface selected.\Zn" 5 40
        bandwidth_reports_submenu  # بازگشت به منوی گزارش پهنای باند
        return
    fi

    # دریافت اینترفیس انتخاب شده
    selected_interface="${interface_list[$((selected_index * 2 - 1))]}"

    # انتخاب ابزار مانیتورینگ بین ifstat و nload
    monitor_tool=$(dialog --colors --menu "\Zb\Z2Choose a monitoring tool:\Zn" "$dialog_height" "$dialog_width" 2 \
        1 "\Zb\Z2ifstat\Zn" \
        2 "\Zb\Z2nload\Zn" 3>&1 1>&2 2>&3)

    if [[ -z "$monitor_tool" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No tool selected.\Zn" 5 40
        bandwidth_reports_submenu  # بازگشت به منوی گزارش پهنای باند
        return
    fi

    if [[ "$monitor_tool" == "1" ]]; then
        # سوال از کاربر برای ذخیره لاگ ifstat
        dialog --yesno "Do you want to save the output of ifstat to a log file?" 7 40
        save_log=$?

        if [[ $save_log -eq 0 ]]; then
            log_dir="$PWD/backup_Log/Network_Monitoring/Bandwidth"
            if [ ! -d "$log_dir" ]; then
                mkdir -p "$log_dir"
                if [[ $? -ne 0 ]]; then
                    dialog --colors --msgbox "\Zb\Z1Error: Could not create log directory.\Zn" 5 40
                    bandwidth_reports_submenu  # بازگشت به منوی گزارش پهنای باند
                    return
                fi
            fi

            log_file="$log_dir/bandwidth_$(date +%Y-%m-%d_%H-%M-%S).txt"
        else
            # ساخت فایل موقت برای نمایش
            log_file=$(mktemp /tmp/ifstat_log.XXXXXX)
        fi

        # مانیتورینگ پهنای باند با ifstat
        dialog --colors --msgbox "\Zb\Z2Monitoring bandwidth on interface $selected_interface with ifstat. Press Ctrl+C to stop.\Zn" 6 50

        # ذخیره لاگ در فایل یا فایل موقت
        ifstat -i "$selected_interface" 1 > "$log_file" &
        
        # ذخیره شناسه پردازش ifstat
        ifstat_pid=$!
        
        # استفاده از dialog برای نمایش لاگ زنده
        dialog --colors --title "\Zb\Z2Monitoring Bandwidth on $selected_interface (ifstat)\Zn" --tailbox "$log_file" 20 70

        # خاتمه پردازش ifstat هنگام بسته شدن dialog
        kill $ifstat_pid 2>/dev/null
        if [[ $? -ne 0 ]]; then
            dialog --colors --msgbox "\Zb\Z1Warning: Failed to stop ifstat process. Please check manually.\Zn" 5 40
            bandwidth_reports_submenu  # بازگشت به منوی گزارش پهنای باند
            return
        fi

        # حذف فایل موقت در صورت عدم ذخیره دائمی لاگ
        if [[ $save_log -ne 0 ]]; then
            rm -f "$log_file"
        fi

    elif [[ "$monitor_tool" == "2" ]]; then
        # مانیتورینگ پهنای باند با nload بدون ذخیره لاگ
        dialog --colors --msgbox "\Zb\Z2Launching nload to monitor interface $selected_interface. Press Ctrl+C to stop.\Zn" 6 50

        clear  # پاکسازی صفحه برای نمایش nload
        sudo nload "$selected_interface"
    else
        dialog --colors --msgbox "\Zb\Z1Error: Invalid tool selection.\Zn" 5 40
        bandwidth_reports_submenu  # بازگشت به منوی گزارش پهنای باند
        return
    fi

    bandwidth_reports_submenu  # بازگشت به منوی گزارش پهنای باند بعد از عملیات موفق
}



generate_bandwidth_graph() {
    get_terminal_size  # فراخوانی تابع برای دریافت اندازه ترمینال
    log_dir="$PWD/backup_Log/Network_Monitoring/Bandwidth"
    
    # بررسی وجود دایرکتوری لاگ‌ها
    if [ ! -d "$log_dir" ]; then
        dialog --colors --msgbox "\Zb\Z1Error: Log directory does not exist.\Zn" 5 40
        return 1
    fi

    # دریافت لیست فایل‌های لاگ (فقط فایل‌های .txt)
    log_files=($(ls "$log_dir"/*.txt 2>/dev/null))
    
    if [[ ${#log_files[@]} -eq 0 ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No log files found in the directory.\Zn" 5 40
        return 1
    fi

    # آماده‌سازی لیست فایل‌های لاگ برای نمایش در منو
    file_list=()
    index=1
    for file in "${log_files[@]}"; do
        file_list+=("$index" "$(basename "$file")")
        index=$((index + 1))
    done

    # نمایش منوی انتخاب فایل لاگ
    selected_index=$(dialog --colors --menu "\Zb\Z2Choose a log file to proceed:\Zn" "$dialog_height" "$dialog_width" 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$selected_index" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No log file selected.\Zn" 5 40
        return 1
    fi

    # دریافت فایل لاگ انتخاب‌شده
    log_file="${log_files[$((selected_index - 1))]}"

    # انتخاب عملیات: نمایش لاگ یا تولید نمودار
    action=$(dialog --colors --menu "\Zb\Z2Choose an action:\Zn" "$dialog_height" "$dialog_width" 3 \
        1 "\Zb\Z2Display Log (No Graph)\Zn" \
        2 "\Zb\Z2Generate Graph\Zn" \
        3 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

    if [[ -z "$action" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No action selected.\Zn" 5 40
        return 1
    fi

    if [[ "$action" == "1" ]]; then
        # نمایش لاگ در کادر متن
        dialog --textbox "$log_file" "$dialog_height" "$dialog_width"
        return 0

    elif [[ "$action" == "2" ]]; then
        # انتخاب نوع نمودار: RX، TX، یا هر دو
        graph_type=$(dialog --colors --menu "\Zb\Z2Choose graph type:\Zn" "$dialog_height" "$dialog_width" 3 \
            1 "\Zb\Z2RX (Received Data)\Zn" \
            2 "\Zb\Z2TX (Transmitted Data)\Zn" \
            3 "\Zb\Z2Both RX and TX\Zn" 3>&1 1>&2 2>&3)

        if [[ -z "$graph_type" ]]; then
            dialog --colors --msgbox "\Zb\Z1Error: No graph type selected.\Zn" 5 40
            return 1
        fi

        # تولید نمودار با استفاده از پایتون
        python3 << EOF
import matplotlib.pyplot as plt

try:
    # خواندن فایل لاگ و پردازش داده‌ها
    rx_data, tx_data = [], []
    with open('$log_file') as f:
        lines = f.readlines()[2:]  # حذف دو خط ابتدایی (عناوین ستون‌ها)
        for line in lines:
            parts = line.split()
            if len(parts) == 2:
                rx_data.append(float(parts[0]))
                tx_data.append(float(parts[1]))

    # تولید بازه زمانی بر اساس تعداد نقاط داده
    times = range(1, len(rx_data) + 1)

    # رسم نمودار بر اساس انتخاب کاربر
    plt.figure(figsize=(10, 6))

    if '$graph_type' == '1':  # فقط RX
        plt.plot(times, rx_data, label='RX (Received)', color='blue')
    elif '$graph_type' == '2':  # فقط TX
        plt.plot(times, tx_data, label='TX (Transmitted)', color='green')
    else:  # RX و TX
        plt.plot(times, rx_data, label='RX (Received)', color='blue')
        plt.plot(times, tx_data, label='TX (Transmitted)', color='green')

    plt.xlabel('Time')
    plt.ylabel('KB/s')
    plt.title('Network Bandwidth Usage Over Time')
    plt.legend()
    plt.xticks(rotation=45)
    plt.tight_layout()

    # ذخیره نمودار به عنوان فایل تصویر
    graph_file = "$log_file".replace('.txt', '.png')
    plt.savefig(graph_file)
    print(f'Graph saved to {graph_file}')

except Exception as e:
    print(f"Error: {e}")
EOF

        # بررسی موفقیت‌آمیز بودن تولید نمودار
        graph_file="${log_file%.txt}.png"
        if [[ -f "$graph_file" ]]; then
            dialog --colors --msgbox "\Zb\Z2Graph has been generated and saved as $graph_file.\Zn" 15 50
            
            # سوال از کاربر برای مشاهده نمودار
            dialog --yesno "Do you want to view the graph?" 5 40
            if [[ $? -eq 0 ]]; then
                xdg-open "$graph_file" 2>/dev/null || dialog --colors --msgbox "\Zb\Z1Could not open the graph image automatically. Check the log directory.\Zn" 5 40
            fi
        else
            dialog --colors --msgbox "\Zb\Z1Error: Failed to generate the graph.\Zn" 5 40
            return 1
        fi
    else
        return 0  # بازگشت به منوی قبلی
    fi

    return 0
}






generate_pdf_report() {
    get_terminal_size  # فراخوانی تابع برای تنظیم ابعاد دیالوگ
    log_dir="$PWD/backup_Log/Network_Monitoring/Bandwidth"
    
    # بررسی وجود دایرکتوری لاگ‌ها
    if [ ! -d "$log_dir" ]; then
        dialog --colors --msgbox "\Zb\Z1Error: Log directory does not exist.\Zn" 5 40
        return 1
    fi

    # دریافت لیست فایل‌های لاگ (فقط فایل‌های .txt)
    log_files=($(ls "$log_dir"/*.txt 2>/dev/null))
    
    if [[ ${#log_files[@]} -eq 0 ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No log files found in the directory.\Zn" 5 40
        return 1
    fi

    # آماده‌سازی لیست فایل‌های لاگ برای منو
    file_list=()
    index=1
    for file in "${log_files[@]}"; do
        file_list+=("$index" "$(basename "$file")")
        index=$((index + 1))
    done

    # نمایش لیست فایل‌های لاگ برای انتخاب
    selected_index=$(dialog --colors --menu "\Zb\Z2Choose a log file to generate the PDF report:\Zn" "$dialog_height" "$dialog_width" 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$selected_index" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No log file selected.\Zn" 5 40
        return 1
    fi

    # دریافت فایل لاگ انتخاب‌شده
    log_file="${log_files[$((selected_index - 1))]}"
    png_file="${log_file%.txt}.png"

    # استفاده از مسیر کامل برای فایل تصویر
    abs_png_file="$log_dir/$(basename "$png_file")"
    
    # بررسی وجود فایل تصویر PNG
    if [[ ! -f "$abs_png_file" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: The graph image file $abs_png_file does not exist.\Zn" 5 40
        return 1
    fi

    # ایجاد گزارش HTML
    html_file="${log_file%.txt}.html"

    echo "<html><head><title>Network Bandwidth Report</title></head><body>" > "$html_file"
    echo "<h1>Network Bandwidth Report</h1>" >> "$html_file"
    echo "<h2>Data from: $log_file</h2>" >> "$html_file"
    echo "<pre>" >> "$html_file"
    cat "$log_file" >> "$html_file"  # اضافه کردن محتوای لاگ به گزارش
    echo "</pre>" >> "$html_file"
    echo "<h3>Bandwidth Graph</h3>" >> "$html_file"
    echo "<img src='file://$abs_png_file' alt='Bandwidth Graph' style='max-width: 100%; height: auto;'>" >> "$html_file"
    echo "</body></html>" >> "$html_file"

    # تبدیل HTML به PDF با استفاده از WeasyPrint
    pdf_file="${log_file%.txt}.pdf"
    python3 -c "
from weasyprint import HTML
HTML(filename='$html_file').write_pdf('$pdf_file')
"
    
    # بررسی موفقیت‌آمیز بودن تولید فایل PDF
    if [[ -f "$pdf_file" ]]; then
        dialog --colors --msgbox "\Zb\Z2PDF Report has been generated and saved as $pdf_file.\Zn" 5 50
    else
        dialog --colors --msgbox "\Zb\Z1Error: Failed to generate PDF report.\Zn" 5 40
    fi
}



save_and_send_report_via_telegram() {
    get_terminal_size  # استفاده از تابع برای کنترل اندازه
    config_file="$PWD/telegram_config.txt"

    # بررسی وجود فایل تنظیمات
    if [ ! -f "$config_file" ]; then
        # درخواست API Token و User ID از کاربر
        bot_api_token=$(dialog --colors --stdout --inputbox "\Zb\Z2Enter your Telegram Bot API Token:\Zn" 8 40)
        user_id=$(dialog --colors --stdout --inputbox "\Zb\Z2Enter the recipient's Telegram User ID:\Zn" 8 40)

        if [[ -z "$bot_api_token" || -z "$user_id" ]]; then
            dialog --colors --msgbox "\Zb\Z1Error: API Token or User ID cannot be empty.\Zn" 5 40
            return
        fi

        # ذخیره API Token و User ID در فایل تنظیمات
        echo "BOT_API_TOKEN=$bot_api_token" > "$config_file"
        echo "USER_ID=$user_id" >> "$config_file"

        dialog --colors --msgbox "\Zb\Z2Configuration saved. You won't need to input the API Token and User ID again.\Zn" 5 40
    else
        # بارگذاری API Token و User ID از فایل تنظیمات
        source "$config_file"
    fi

    # فیلتر کردن فایل‌های PDF از دایرکتوری
    pdf_files=($(find "$PWD/backup_Log/Network_Monitoring/Bandwidth/" -type f -name "*.pdf"))

    if [[ ${#pdf_files[@]} -eq 0 ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No PDF files found in the directory.\Zn" 5 40
        return
    fi

    # آماده‌سازی لیست فایل‌ها برای نمایش در منوی دیالوگ
    file_list=()
    index=1
    for file in "${pdf_files[@]}"; do
        file_list+=("$index" "$(basename "$file")")
        index=$((index + 1))
    done

    # نمایش منوی انتخاب فایل PDF برای ارسال
    selected_index=$(dialog --colors --menu "\Zb\Z2Choose a PDF file to send via Telegram:\Zn" "$dialog_height" "$dialog_width" 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$selected_index" ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No PDF file selected.\Zn" 5 40
        return
    fi

    # دریافت فایل PDF انتخاب‌شده
    pdf_file="${pdf_files[$((selected_index - 1))]}"

    # استفاده از اسکریپت Python برای ارسال فایل از طریق Telegram Bot API
    python3 << EOF
import requests

# Telegram Bot API token و User ID
bot_api_token = '$BOT_API_TOKEN'
user_id = '$USER_ID'

# فایل PDF برای ارسال
pdf_file = '$pdf_file'
pdf_filename = pdf_file.split('/')[-1]

# ارسال فایل به تلگرام
with open(pdf_file, 'rb') as f:
    response = requests.post(
        f'https://api.telegram.org/bot{bot_api_token}/sendDocument',
        data={'chat_id': user_id, 'caption': 'Here is your Network Bandwidth Report.'},
        files={'document': (pdf_filename, f)}
    )

print(response.status_code)
print(response.json())
EOF

    # بررسی موفقیت‌آمیز بودن ارسال
    if [[ $? -eq 0 ]]; then
        dialog --colors --msgbox "\Zb\Z2Report has been successfully sent via Telegram.\Zn" 5 40
    else
        dialog --colors --msgbox "\Zb\Z1Error: Failed to send the report via Telegram.\Zn" 6 40
    fi
}



#################################################################



monitor_resources() {
    get_terminal_size  # استفاده از تابع برای تعیین ابعاد دیالوگ
    log_dir="$PWD/backup_Log/Network_Monitoring/Monitor_Resources"
    
    # بررسی و ایجاد دایرکتوری لاگ‌ها
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi

    # نمایش منوی اصلی
    choice=$(dialog --colors --menu "\Zb\Z2Monitor Resources\Zn" "$dialog_height" "$dialog_width" 5 \
        1 "\Zb\Z2CPU Usage\Zn" \
        2 "\Zb\Z2Memory Usage\Zn" \
        3 "\Zb\Z2Disk Usage\Zn" \
        4 "\Zb\Z2Network Usage (Nload in terminal, no log)\Zn" \
        5 "\Zb\Z1Back to Main Menu\Zn" 3>&1 1>&2 2>&3)

    # مدیریت انتخاب نامعتبر یا لغو
    if [[ -z "$choice" ]]; then
        logs_resources_submenu
        return
    fi

    # اگر کاربر گزینه Network Usage را انتخاب کند
    if [[ "$choice" == "4" ]]; then
        dialog --colors --msgbox "\Zb\Z2Launching nload in terminal. Press Ctrl+C to stop.\Zn" 5 40
        sudo nload  # اجرای nload مستقیم در ترمینال بدون ذخیره لاگ
        logs_resources_submenu  # بازگشت به منوی فرعی پس از پایان
        return
    fi

    # اگر گزینه 5 انتخاب شود بدون سوال درباره ذخیره لاگ به منوی قبلی برمی‌گردد
    if [[ "$choice" == "5" ]]; then
        network_monitoring  # بازگشت به منوی اصلی
        return
    fi

    # سوال برای ذخیره لاگ اگر گزینه 5 انتخاب نشده باشد
    dialog --yesno "Do you want to save the resource monitoring log?" 7 40
    save_log=$?

    if [[ $save_log -eq 1 ]]; then
        dialog --colors --msgbox "\Zb\Z1No log will be saved.\Zn" 5 40
    fi

    # ایجاد timestamp برای فایل لاگ
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    
    # اگر لاگ ذخیره شود، فایل لاگ تعریف می‌شود
    if [[ $save_log -eq 0 ]]; then
        log_file="$log_dir/resource_monitor_$timestamp.txt"
        touch "$log_file"
    fi

    case $choice in
        1)
            dialog --colors --msgbox "\Zb\Z2Monitoring CPU usage. Press Ctrl+C to stop.\Zn" 5 40
            if [[ $save_log -eq 0 ]]; then
                mpstat 1 | tee "$log_file" | dialog --programbox "Monitoring CPU usage" "$dialog_height" "$dialog_width"
            else
                mpstat 1 | dialog --programbox "Monitoring CPU usage" "$dialog_height" "$dialog_width"
            fi
            ;;
        2)
            dialog --colors --msgbox "\Zb\Z2Monitoring Memory usage. Press Ctrl+C to stop.\Zn" 5 40
            if [[ $save_log -eq 0 ]]; then
                vmstat 1 | tee "$log_file" | dialog --programbox "Monitoring Memory usage" "$dialog_height" "$dialog_width"
            else
                vmstat 1 | dialog --programbox "Monitoring Memory usage" "$dialog_height" "$dialog_width"
            fi
            ;;
        3)
            # ایجاد فایل موقت برای ذخیره خروجی
            temp_file=$(mktemp)

            # به‌روزرسانی وضعیت دیسک هر ۵ ثانیه در پس‌زمینه
            (
                while true; do
                    df -h > "$temp_file"
                    sleep 5  # تنظیم بازه به‌روزرسانی
                done
            ) &

            # گرفتن PID فرآیند پس‌زمینه
            pid=$!

            # نمایش خروجی با استفاده از tailbox
            dialog --tailbox "$temp_file" "$dialog_height" "$dialog_width"

            # توقف فرآیند پس‌زمینه و حذف فایل موقت پس از بستن دیالوگ
            kill $pid
            rm -f "$temp_file"
            logs_resources_submenu  # بازگشت به منوی فرعی
            return
            ;;
        *)
            dialog --colors --msgbox "\Zb\Z1Invalid option. Please try again.\Zn" 5 40
            logs_resources_submenu  
            ;;
    esac

    # اطلاع به کاربر پس از مانیتورینگ
    if [[ $save_log -eq 0 ]]; then
        dialog --colors --msgbox "\Zb\Z2Log has been saved at $log_file\Zn" 5 40
    fi
}

view_logs() {
    get_terminal_size  # استفاده از تابع برای تعیین ابعاد دیالوگ
    log_dir="$PWD/backup_Log/Network_Monitoring/Monitor_Resources"

    # بررسی وجود دایرکتوری لاگ‌ها
    if [ ! -d "$log_dir" ]; then
        dialog --colors --msgbox "\Zb\Z1Error: Log directory does not exist.\Zn" 5 40
        logs_resources_submenu
        return
    fi

    # گرفتن لیست فایل‌های لاگ (فقط فایل‌های .txt)
    log_files=($(find "$log_dir" -type f -name "*.txt"))

    if [[ ${#log_files[@]} -eq 0 ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No log files found.\Zn" 5 40
        logs_resources_submenu
        return
    fi

    # نمایش منوی انتخاب برای مشاهده یا حذف لاگ‌ها
    choice=$(dialog --colors --menu "\Zb\Z2Choose an action:\Zn" "$dialog_height" "$dialog_width" 3 \
        1 "\Zb\Z2View Logs\Zn" \
        2 "\Zb\Z2Delete Logs\Zn" \
        3 "\Zb\Z1Back\Zn" 3>&1 1>&2 2>&3)

    if [[ -z "$choice" ]]; then
        logs_resources_submenu
        return
    fi

    case $choice in
        1)  # نمایش لاگ‌ها
            # ساخت لیست فایل‌های لاگ برای نمایش در منو
            file_list=()
            index=1
            for file in "${log_files[@]}"; do
                file_list+=("$index" "$(basename "$file")")
                index=$((index + 1))
            done

            # نمایش فایل‌های لاگ در منوی دیالوگ برای انتخاب
            selected_index=$(dialog --colors --menu "\Zb\Z2Choose a log file to view:\Zn" "$dialog_height" "$dialog_width" 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

            if [[ -z "$selected_index" ]]; then
                logs_resources_submenu
                return
            fi

            # دریافت فایل لاگ انتخاب‌شده بر اساس ایندکس
            log_file="${log_files[$((selected_index - 1))]}"

            # نمایش فایل لاگ در یک textbox دیالوگ
            dialog --textbox "$log_file" "$dialog_height" "$dialog_width"
            logs_resources_submenu
            return
            ;;
        2)  # حذف لاگ‌ها
            # اجازه به کاربر برای انتخاب چندین فایل لاگ برای حذف
            file_list=()
            index=1
            for file in "${log_files[@]}"; do
                file_list+=("$index" "$(basename "$file")" "OFF")
                index=$((index + 1))
            done

            selected_files=$(dialog --stdout --checklist "\Zb\Z2Choose log files to delete:\Zn" "$dialog_height" "$dialog_width" 10 "${file_list[@]}")

            if [[ -z "$selected_files" ]]; then
                logs_resources_submenu
                return
            fi

            # تبدیل ایندکس‌های انتخابی به نام فایل‌ها و حذف آن‌ها
            for i in $selected_files; do
                log_file="${log_files[$((i - 1))]}"
                rm -f "$log_file"
            done

            dialog --colors --msgbox "\Zb\Z2Selected log files have been deleted.\Zn" 5 40
            logs_resources_submenu
            return
            ;;
        3)  # بازگشت به منوی قبلی
            logs_resources_submenu
            return
            ;;
        *)
            dialog --colors --msgbox "\Zb\Z1Invalid option.\Zn" 5 40
            logs_resources_submenu
            return
            ;;
    esac
}


#################################################################
# تابع تعیین ابعاد ترمینال
function get_terminal_size() {
    term_height=$(tput lines)
    term_width=$(tput cols)
    dialog_height=$((term_height - 5))
    dialog_width=$((term_width - 10))
    if [ "$dialog_height" -lt 15 ]; then dialog_height=15; fi
    if [ "$dialog_width" -lt 50 ]; then dialog_width=50; fi
}

# منوی اصلی
function network_monitoring() {
    get_terminal_size
    while true; do
        choice=$(dialog --colors --backtitle "\Zb\Z4Network Monitoring Tool\Zn" --title "\Zb\Z3Main Menu\Zn" \
            --menu "\nChoose an option:" "$dialog_height" "$dialog_width" 10 \
            1 "\Zb\Z2Monitoring Devices\Zn" \
            2 "\Zb\Z2Port and Traffic Monitoring\Zn" \
            3 "\Zb\Z2Bandwidth Monitoring and Reports\Zn" \
            4 "\Zb\Z2Logs and Resources\Zn" \
            5 "\Zb\Z1Exit\Zn" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            break  # خروج در صورت فشردن کلید کنسل
        fi

        case $choice in
            1) device_monitoring_submenu ;;
            2) port_traffic_monitoring_submenu ;;
            3) bandwidth_reports_submenu ;;
            4) logs_resources_submenu ;;
            5) $BASE_DIR/.././net-tool.sh; exit 0 ;;
            *) break ;;
        esac
    done
}

# زیرمنو برای مانیتورینگ دستگاه‌ها
function device_monitoring_submenu() {
    get_terminal_size
    while true; do
        choice=$(dialog --colors --backtitle "\Zb\Z4Device and Network Monitoring\Zn" --title "\Zb\Z3Device Monitoring\Zn" \
            --menu "\nChoose an option:" "$dialog_height" "$dialog_width" 10 \
            1 "\Zb\Z2Ping Devices\Zn" \
            2 "\Zb\Z2View Connections\Zn" \
            3 "\Zb\Z2Monitor DNS\Zn" \
            4 "\Zb\Z1Back to Main Menu\Zn" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            break  # خروج در صورت فشردن کلید کنسل
        fi

        case $choice in
            1) ping_devices ;;
            2) view_connections ;;
            3) monitor_dns ;;
            4) break ;;  # بازگشت به منوی اصلی
        esac
    done
}

# زیرمنو برای مانیتورینگ پورت‌ها و ترافیک
function port_traffic_monitoring_submenu() {
    get_terminal_size
    while true; do
        choice=$(dialog --colors --backtitle "\Zb\Z4Port and Traffic Monitoring\Zn" --title "\Zb\Z3Port Monitoring\Zn" \
            --menu "\nChoose an option:" "$dialog_height" "$dialog_width" 10 \
            1 "\Zb\Z2View Port Table\Zn" \
            2 "\Zb\Z2Check Specific Port\Zn" \
            3 "\Zb\Z2Monitor Ports and Traffic\Zn" \
            4 "\Zb\Z1Back to Main Menu\Zn" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            break  # خروج در صورت فشردن کلید کنسل
        fi

        case $choice in
            1) view_port_table ;;
            2) check_specific_port ;;
            3) monitor_ports_and_traffic ;;
            4) break ;;  # بازگشت به منوی اصلی
        esac
    done
}

function bandwidth_reports_submenu() {
    get_terminal_size
    while true; do
        choice=$(dialog --colors --backtitle "\Zb\Z4Bandwidth Monitoring and Reports\Zn" --title "\Zb\Z3Bandwidth Reports\Zn" \
            --menu "\nChoose an option:" "$dialog_height" "$dialog_width" 10 \
            1 "\Zb\Z2Monitor Bandwidth\Zn" \
            2 "\Zb\Z2Generate Bandwidth Graph\Zn" \
            3 "\Zb\Z2Generate PDF Report\Zn" \
            4 "\Zb\Z2Save and Send Report\Zn" \
            5 "\Zb\Z1Back to Main Menu\Zn" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            break 
        fi

        case $choice in
            1) monitor_bandwidth ;;
            2) generate_bandwidth_graph ;;
            3) generate_pdf_report ;;
            4) save_and_send_report_via_telegram ;;
            5) break ;;  
        esac
    done
}

# زیرمنو برای نمایش لاگ‌ها و مانیتورینگ منابع
function logs_resources_submenu() {
    get_terminal_size
    while true; do
        choice=$(dialog --colors --backtitle "\Zb\Z4Logs and Resources\Zn" --title "\Zb\Z3Logs and Resources\Zn" \
            --menu "\nChoose an option:" "$dialog_height" "$dialog_width" 10 \
            1 "\Zb\Z2Monitor Resources\Zn" \
            2 "\Zb\Z2View Logs\Zn" \
            3 "\Zb\Z1Back to Main Menu\Zn" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            break  
        fi

        case $choice in
            1) monitor_resources;;
            2) view_logs ;;
            3) break ;;  
        esac
    done
}

network_monitoring
