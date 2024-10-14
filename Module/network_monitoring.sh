TITLE="Network Monitoring"

# Function to ping devices and display live results
function ping_devices() {
    # گرفتن IPها و تنظیمات از کاربر
    devices=$(dialog --inputbox "Enter IP addresses to ping (comma-separated):" 10 50 3>&1 1>&2 2>&3)
    if [ -z "$devices" ]; then
        dialog --msgbox "No IP addresses entered." 10 30
        return
    fi

    ping_count=$(dialog --inputbox "Enter the number of pings to send:" 10 50 3 3>&1 1>&2 2>&3)
    if [ -z "$ping_count" ]; then ping_count=3; fi  

    timeout=$(dialog --inputbox "Enter timeout for each ping (in seconds):" 10 50 1 3>&1 1>&2 2>&3)
    if [ -z "$timeout" ]; then timeout=1; fi  

    # تبدیل IPها به آرایه
    IFS=',' read -ra ip_array <<< "$devices"

    # ایجاد فایل موقت برای ذخیره نتایج
    tmpfile=$(mktemp)

    # خروجی جدول پینگ
    echo -e "| IP Address     | Status     | Time (ms) | Packet Loss |" > $tmpfile
    echo -e "---------------------------------------------------------" >> $tmpfile

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

            printf "| %-14s | %-10s | %-9s | %-11s |\n" "$ip" "$status" "$time" "$loss%" >> $tmpfile

            echo "---"
            tail -n 10 $tmpfile  
            echo "---"
            sleep 0.5  
        done
    done

    echo "----"
    echo -e "\nPing operation completed. Press OK to return." >> $tmpfile
    echo "---"
    ) | dialog --title "Ping Results (Live)" --progressbox 20 60

    dialog --textbox $tmpfile 20 60
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
    # مسیر برای ذخیره‌سازی خروجی‌ها
    backup_dir="$PWD/backup_Log/Network_Monitoring/View_Connection/"

    # ایجاد دایرکتوری‌ها اگر وجود ندارند
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi

    while true; do
        # انتخاب فیلتر
        filter=$(dialog --menu "Choose Filter for Viewing Connections" 15 60 5 \
            1 "View All Active Connections" \
            2 "View Listening Ports" \
            3 "Filter by Port or Protocol" \
            4 "View Saved Outputs" \
            5 "Exit" 3>&1 1>&2 2>&3)

        case $filter in
            1)
                # نمایش تمام اتصالات فعال با جداول زیبا و رنگ‌بندی
                ss -tunap | awk 'BEGIN {print "| Protocol | Source IP:Port         | Destination IP:Port    | Status          | Process"; print "----------------------------------------------------------------------------------------------"} \
                {split($5, src, ":"); split($6, dst, ":"); printf "| %-8s | %-21s | %-21s | %-15s | %s\n", $1, src[1] ":" src[2], dst[1] ":" dst[2], $4, $7}' > /tmp/connections.txt
                dialog --backtitle "Active Connections" --textbox /tmp/connections.txt 30 100

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
                dialog --backtitle "Listening Ports" --textbox /tmp/listening_ports.txt 30 100

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
                    protocol=$(dialog --menu "Choose Protocol (default TCP)" 15 60 3 \
                        1 "TCP" \
                        2 "UDP" \
                        3 "Back" 3>&1 1>&2 2>&3)

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
                        dialog --backtitle "TCP Connections" --textbox /tmp/tcp_connections.txt 30 100
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
                        dialog --backtitle "UDP Connections" --textbox /tmp/udp_connections.txt 30 100
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
                backup_dir="$PWD/backup_Log/Network_Monitoring/View_Connection"

                # بررسی اینکه آیا فایل بکاپی در فولدر وجود دارد
                backup_files=$(ls "$backup_dir"/*.txt 2>/dev/null)
                if [ -z "$backup_files" ]; then
                    dialog --msgbox "No backup files found in $backup_dir!" 7 40
                    return
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
                selected_backup=$(dialog --menu "Select a file to view" 15 50 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

                # بررسی اینکه کاربر فایلی انتخاب کرده یا خیر
                if [ $? -ne 0 ] || [ -z "$selected_backup" ]; then
                    dialog --msgbox "No file selected!" 7 40
                    return
                fi

                # دریافت مسیر کامل فایل انتخاب‌شده از file_map
                selected_backup_full_path="${file_map[$selected_backup]}"

                # نمایش محتوای فایل انتخاب‌شده
                if [ -f "$selected_backup_full_path" ]; then
                    dialog --textbox "$selected_backup_full_path" 30 100
                else
                    dialog --msgbox "Error: File not found or cannot be opened." 7 40
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
    # مسیر جدید برای ذخیره لاگ‌ها
    backup_dir="$PWD/backup_Log/Network_Monitoring/Monitor_DNS"
    mkdir -p "$backup_dir"  # ایجاد دایرکتوری اگر وجود ندارد

    while true; do
        # نمایش منوی اصلی مانیتورینگ DNS
        action=$(dialog --menu "DNS Monitoring Options" 15 60 6 \
            1 "Live DNS Query Monitoring" \
            2 "Test DNS Performance" \
            3 "Clear DNS Cache" \
            4 "View DNS Cache" \
            5 "View Saved DNS Logs" \
            6 "Back to Main Menu" 3>&1 1>&2 2>&3)

        case $action in
            1)
                # نمایش لیست اینترفیس‌های شبکه و انتخاب اینترفیس
                interfaces=$(ip -o link show | awk -F': ' '{print $2}')
                interface_list=()
                for iface in $interfaces; do
                    interface_list+=("$iface" "")
                done

                interface=$(dialog --menu "Select a network interface for monitoring" 15 50 6 "${interface_list[@]}" 3>&1 1>&2 2>&3)

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
                dns_servers_input=$(dialog --inputbox "Enter DNS servers (comma-separated) or leave empty for default:" 10 50 3>&1 1>&2 2>&3)
                
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
                dialog --textbox "$log_file" 20 50
                ;;


            3)
                # پاک کردن کش DNS با تایید کاربر
                dialog --yesno "Are you sure you want to clear the DNS cache?" 10 40
                if [ $? -eq 0 ]; then
                    sudo systemctl restart systemd-resolved
                    dialog --msgbox "DNS Cache Cleared!" 10 40
                else
                    dialog --msgbox "Action canceled." 10 40
                fi
                ;;

            4)
                # نمایش کش DNS
                dialog --infobox "Viewing DNS Cache..." 3 50
                resolvectl dns > /tmp/dns_cache.txt
                dialog --textbox /tmp/dns_cache.txt 20 50
                ;;

            5)
                # نمایش لاگ‌های ذخیره‌شده
                saved_logs=$(ls "$backup_dir"/*.txt 2>/dev/null)
                if [ -z "$saved_logs" ]; then
                    dialog --msgbox "No saved DNS logs found." 10 40
                else
                    log_list=()
                    for file in $saved_logs; do
                        log_list+=("$(basename "$file")" "")
                    done
                    selected_log=$(dialog --menu "Select a DNS log to view" 15 50 10 "${log_list[@]}" 3>&1 1>&2 2>&3)
                    if [ -n "$selected_log" ]; then
                        dialog --textbox "$backup_dir/$selected_log" 20 80
                    fi
                fi
                ;;

            6)
                break
                ;;

            *)
                dialog --msgbox "Invalid option selected!" 10 40
                ;;
        esac
    done
}


#################################################################

view_port_table() {
    # Select protocol using dialog
    protocol=$(dialog --stdout --menu "Choose protocol type" 10 30 2 \
        1 "tcp" \
        2 "udp")
    
    # If user cancels or input is invalid
    if [[ -z "$protocol" ]]; then
        dialog --msgbox "Error: No valid protocol selected." 5 40
        return
    fi

    # Convert selection to string (tcp or udp)
    if [[ "$protocol" == "1" ]]; then
        protocol="tcp"
    elif [[ "$protocol" == "2" ]]; then
        protocol="udp"
    fi

    # Ask user if they want only listening ports
    dialog --yesno "Do you want only listening ports?" 7 40
    response=$?

    # Set listening flag based on user's choice
    if [[ $response -eq 0 ]]; then
        listening_flag="-l"
    else
        listening_flag=""
    fi

    # Display a message before showing the result
    dialog --infobox "Displaying open ports for protocol $protocol..." 5 50
    sleep 2

    # Get port table
    result=$(sudo ss -tuln | grep $protocol | awk '{print $1, $4, $5, $6}')

    # If result is empty, show an error message
    if [[ -z "$result" ]]; then
        dialog --msgbox "No open ports found for protocol $protocol." 5 50
        port_traffic_monitoring_submenu
    else
        # Display result in a scrollable dialog box
        dialog --msgbox "$result" 20 60
        port_traffic_monitoring_submenu
    fi
}


check_specific_port() {
    # Get port number from user using dialog
    port=$(dialog --stdout --inputbox "Enter the port number to check:" 8 40)

    # Validate port input (only numbers)
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        dialog --msgbox "Error: Please enter a valid numeric port number." 5 40
        return
    fi

    # Select protocol using dialog
    protocol=$(dialog --stdout --menu "Choose protocol type" 10 30 2 \
        1 "tcp" \
        2 "udp")
    
    # If user cancels or input is invalid
    if [[ -z "$protocol" ]]; then
        dialog --msgbox "Error: No valid protocol selected." 5 40
        return
    fi

    # Convert selection to string (tcp or udp)
    if [[ "$protocol" == "1" ]]; then
        protocol="tcp"
    elif [[ "$protocol" == "2" ]]; then
        protocol="udp"
    fi

    # Display a message before checking the port
    dialog --infobox "Checking if port $port is in use for protocol $protocol..." 5 50
    sleep 2

    # Check if the port is in use using ss
    result=$(sudo ss -tuln | grep ":$port " | grep $protocol)

    # If result is empty, the port is not in use
    if [[ -z "$result" ]]; then
        dialog --msgbox "Port $port is not in use for protocol $protocol." 5 50
        port_traffic_monitoring_submenu
    else
        # Display the details of the port in use
        dialog --msgbox "Port $port is in use:\n\n$result" 20 60

        
        # Check for the process/service using lsof
        service_info=$(sudo lsof -i :$port)

        if [[ -z "$service_info" ]]; then
            dialog --msgbox "No specific service found using port $port." 5 50
            port_traffic_monitoring_submenu
        else
            # Display the service info
            dialog --msgbox "Service information for port $port:\n\n$service_info" 20 60
            port_traffic_monitoring_submenu
        fi
    fi
}

monitor_ports_and_traffic() {
    log_dir="$PWD/backup_Log/Network_Monitoring/Monitor_Ports_And_Traffic"
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi

    declare -A file_map  # Define an associative array to map file names to their full paths

    while true; do
        # Show menu with options for monitoring, displaying logs, and deleting logs
        dialog --menu "Network Monitor Menu" 15 50 4 \
            1 "Monitor Ports and Traffic" \
            2 "Display Logs" \
            3 "Delete Logs" \
            4 "Exit" 2> menu_choice.txt

        choice=$(<menu_choice.txt)

        case $choice in
            1)
                # Monitoring Ports and Traffic
                mode=$(dialog --stdout --menu "Choose monitoring mode" 10 40 2 \
                    1 "Monitor all traffic" \
                    2 "Monitor specific port")

                if [[ -z "$mode" ]]; then
                    dialog --msgbox "Error: No valid option selected." 5 40
                    continue
                fi

                tcpdump_cmd="sudo tcpdump -n -q"

                if [[ "$mode" == "2" ]]; then
                    port=$(dialog --stdout --inputbox "Enter the port number to monitor:" 8 40)

                    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
                        dialog --msgbox "Error: Please enter a valid numeric port number." 5 40
                        continue
                    fi

                    tcpdump_cmd="$tcpdump_cmd port $port"
                fi

                dialog --yesno "Do you want to save the output to a log file?" 7 40
                save_log=$?

                if [[ $save_log -eq 0 ]]; then
                    log_file=$(dialog --stdout --inputbox "Enter the log file name (without extension):" 8 40)

                    if [[ -z "$log_file" ]]; then
                        dialog --msgbox "Error: Log file name cannot be empty." 5 40
                        continue
                    fi

                    # Save the log as a text file
                    log_file="$log_dir/$log_file.txt"
                    tcpdump_cmd="$tcpdump_cmd -nn -q -tttt | tee $log_file"
                    dialog --msgbox "Monitoring traffic and saving to $log_file. Press Ctrl+C to stop." 7 50
                else
                    dialog --msgbox "Monitoring traffic in real-time. Press Ctrl+C to stop." 7 50
                fi

                clear
                eval $tcpdump_cmd
                ;;

            2)
                # Display Logs
                log_files=$(ls -1 "$log_dir"/*.txt 2>/dev/null)

                if [[ -z "$log_files" ]]; then
                    dialog --msgbox "No logs found." 5 40
                    continue
                fi

                # Build the file_map and file_list
                file_list=()
                index=1

                for log_file_path in "$log_dir"/*.txt; do
                    file_name=$(basename "$log_file_path")
                    file_map["$file_name"]="$log_file_path"  # Map file name to its full path
                    file_list+=("$index" "$file_name")
                    index=$((index + 1))
                done

                # Show the list of log files in a menu
                log_choice=$(dialog --stdout --menu "Choose a log to display" 15 60 10 "${file_list[@]}")

                if [[ -n "$log_choice" ]]; then
                    selected_file_name="${file_list[$((log_choice * 2 - 1))]}"  # Get the selected file name
                    selected_file_path="${file_map[$selected_file_name]}"  # Get the full file path
                    dialog --textbox "$selected_file_path" 20 80
                fi
                ;;

            3)
                # Delete Logs
                log_files=$(ls -1 "$log_dir"/*.txt 2>/dev/null)

                if [[ -z "$log_files" ]]; then
                    dialog --msgbox "No logs found." 5 40
                    continue
                fi

                # Build the file_map and file_list for deletion
                file_list=()
                index=1

                for log_file_path in "$log_dir"/*.txt; do
                    file_name=$(basename "$log_file_path")
                    file_map["$file_name"]="$log_file_path"  # Map file name to its full path
                    file_list+=("$index" "$file_name")
                    index=$((index + 1))
                done

                # Show the list of log files to delete
                log_choice=$(dialog --stdout --menu "Choose a log to delete" 15 60 10 "${file_list[@]}")

                if [[ -n "$log_choice" ]]; then
                    selected_file_name="${file_list[$((log_choice * 2 - 1))]}"  # Get the selected file name
                    selected_file_path="${file_map[$selected_file_name]}"  # Get the full file path

                    dialog --yesno "Are you sure you want to delete $selected_file_name?" 7 40
                    delete_confirmation=$?

                    if [[ $delete_confirmation -eq 0 ]]; then
                        rm -f "$selected_file_path"
                        dialog --msgbox "Log $selected_file_name has been deleted." 5 40
                    fi
                fi
                ;;

            4)
                break
                ;;

            *)
                dialog --msgbox "Invalid option. Please try again." 5 40
                ;;
        esac
    done

    # Clear the screen when exiting
    clear
}


#################################################################
monitor_bandwidth() {
    # Get the list of network interfaces (skip the loopback 'lo')
    interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)

    # Check if there are available interfaces
    if [[ -z "$interfaces" ]]; then
        dialog --msgbox "Error: No network interfaces found." 5 40
        bandwidth_reports_submenu  # Exit with error code
    fi

    # Prepare the list for dialog menu (numbered list)
    interface_list=()
    index=1
    for interface in $interfaces; do
        interface_list+=("$index" "$interface")
        index=$((index + 1))
    done

    # Show the interfaces in a dialog menu for user selection
    selected_index=$(dialog --stdout --menu "Choose a network interface to monitor:" 15 50 10 "${interface_list[@]}")

    if [[ -z "$selected_index" ]]; then
        dialog --msgbox "Error: No interface selected." 5 40
        bandwidth_reports_submenu  # Exit with error code
    fi

    # Get the selected interface based on the index
    selected_interface="${interface_list[$((selected_index * 2 - 1))]}"

    # Ask the user to choose between ifstat and nload
    monitor_tool=$(dialog --stdout --menu "Choose a monitoring tool:" 15 50 2 \
        1 "ifstat" \
        2 "nload")

    if [[ -z "$monitor_tool" ]]; then
        dialog --msgbox "Error: No tool selected." 5 40
        bandwidth_reports_submenu  # Exit with error code
    fi

    if [[ "$monitor_tool" == "1" ]]; then
        # Ask the user if they want to save the log for ifstat
        dialog --yesno "Do you want to save the output of ifstat to a log file?" 7 40
        save_log=$?

        if [[ $save_log -eq 0 ]]; then
            log_dir="$PWD/backup_Log/Network_Monitoring/Bandwidth"
            if [ ! -d "$log_dir" ]; then
                mkdir -p "$log_dir"
                if [[ $? -ne 0 ]]; then
                    dialog --msgbox "Error: Could not create log directory." 5 40
                    bandwidth_reports_submenu  # Exit with error code
                fi
            fi

            log_file="$log_dir/bandwidth_$(date +%Y-%m-%d_%H-%M-%S).txt"
        else
            # Create a temporary file for showing the output in dialog
            log_file=$(mktemp /tmp/ifstat_log.XXXXXX)
        fi

        # Monitor bandwidth using ifstat
        dialog --msgbox "Monitoring bandwidth on interface $selected_interface with ifstat. Press Ctrl+C to stop." 6 50

        # Save the log to a file (temporary if not saving permanently)
        ifstat -i "$selected_interface" 1 > "$log_file" &
        
        # Store the process ID of ifstat
        ifstat_pid=$!
        
        # Use dialog to display the live log in a tailbox
        dialog --title "Monitoring Bandwidth on $selected_interface (ifstat)" --tailbox "$log_file" 20 70

        # Kill ifstat process when dialog is closed
        kill $ifstat_pid 2>/dev/null
        if [[ $? -ne 0 ]]; then
            dialog --msgbox "Warning: Failed to stop ifstat process. Please check manually." 5 40
            bandwidth_reports_submenu  # Exit with error code
        fi

        # Remove the temporary file if log is not saved permanently
        if [[ $save_log -ne 0 ]]; then
            rm -f "$log_file"
        fi

    elif [[ "$monitor_tool" == "2" ]]; then
        # Monitor bandwidth using nload without log saving option
        dialog --msgbox "Launching nload to monitor interface $selected_interface. Press Ctrl+C to stop." 6 50

        clear  # Clear the screen to show nload
        sudo nload "$selected_interface"
    else
        dialog --msgbox "Error: Invalid tool selection." 5 40
        bandwidth_reports_submenu  # Exit with error code
    fi

    bandwidth_reports_submenu  # Success
}



generate_bandwidth_graph() {
    log_dir="$PWD/backup_Log/Network_Monitoring/Bandwidth"
    
    # Check if log directory exists
    if [ ! -d "$log_dir" ]; then
        dialog --msgbox "Error: Log directory does not exist." 5 40
        return 1
    fi

    # Get the list of log files (.txt files only)
    log_files=($(ls "$log_dir"/*.txt 2>/dev/null))
    
    if [[ ${#log_files[@]} -eq 0 ]]; then
        dialog --msgbox "Error: No log files found in the directory." 5 40
        return 1
    fi

    # Prepare the list of log files for the menu
    file_list=()
    index=1
    for file in "${log_files[@]}"; do
        file_list+=("$index" "$(basename "$file")")
        index=$((index + 1))
    done

    # Show the log files in a dialog menu for user selection
    selected_index=$(dialog --stdout --menu "Choose a log file to proceed:" 15 50 10 "${file_list[@]}")

    if [[ -z "$selected_index" ]]; then
        dialog --msgbox "Error: No log file selected." 5 40
        return 1
    fi

    # Get the selected log file based on the index
    log_file="${log_files[$((selected_index - 1))]}"

    # Ask user what they want to do: Display log, generate graph, or return to the previous menu
    action=$(dialog --stdout --menu "Choose an action:" 15 50 3 \
        1 "Display Log (No Graph)" \
        2 "Generate Graph" \
        3 "Return to Previous Menu")

    if [[ -z "$action" ]]; then
        dialog --msgbox "Error: No action selected." 5 40
        return 1
    fi

    if [[ "$action" == "1" ]]; then
        # Display the log in a dialog textbox
        dialog --textbox "$log_file" 20 70
        return 0

    elif [[ "$action" == "2" ]]; then
        # Ask user to select graph type: RX, TX, or both
        graph_type=$(dialog --stdout --menu "Choose graph type:" 15 50 3 \
            1 "RX (Received Data)" \
            2 "TX (Transmitted Data)" \
            3 "Both RX and TX")

        if [[ -z "$graph_type" ]]; then
            dialog --msgbox "Error: No graph type selected." 5 40
            return 1
        fi

        # Read the log file and generate the graph using Python
        python3 << EOF
import matplotlib.pyplot as plt

try:
    # Reading log file and processing the data
    times = []
    rx_data = []
    tx_data = []

    with open('$log_file') as f:
        lines = f.readlines()
        for line in lines[2:]:  # Skipping the first two lines (interface and column headers)
            parts = line.split()
            if len(parts) == 2:  # Expecting exactly two columns: RX and TX
                rx_data.append(float(parts[0]))
                tx_data.append(float(parts[1]))

    # Create a range of timestamps based on the number of data points
    times = list(range(1, len(rx_data) + 1))

    # Plotting the data based on user's selection
    plt.figure(figsize=(10, 6))

    if '$graph_type' == '1':  # RX only
        plt.plot(times, rx_data, label='RX (Received)', color='blue')
    elif '$graph_type' == '2':  # TX only
        plt.plot(times, tx_data, label='TX (Transmitted)', color='green')
    else:  # Both RX and TX
        plt.plot(times, rx_data, label='RX (Received)', color='blue')
        plt.plot(times, tx_data, label='TX (Transmitted)', color='green')

    plt.xlabel('Time')
    plt.ylabel('KB/s')
    plt.title('Network Bandwidth Usage Over Time')
    plt.legend()
    plt.xticks(rotation=45)
    plt.tight_layout()

    # Save the graph as an image
    graph_file = "$log_file".replace('.txt', '.png')
    plt.savefig(graph_file)
    print(f'Graph saved to {graph_file}')

except Exception as e:
    print(f"Error: {e}")
EOF

        # Check if the graph file was created successfully
        graph_file="${log_file%.txt}.png"
        if [[ -f "$graph_file" ]]; then
            dialog --msgbox "Graph has been generated and saved as $graph_file." 15 50
            
            # Ask the user if they want to view the graph
            dialog --yesno "Do you want to view the graph?" 5 40
            if [[ $? -eq 0 ]]; then
                xdg-open "$graph_file" 2>/dev/null || dialog --msgbox "Could not open the graph image automatically. Check the log directory." 5 40
            fi
        else
            dialog --msgbox "Error: Failed to generate the graph." 5 40
            return 1
        fi
    else
        return 0  # Return to the previous menu
    fi

    return 0
}





generate_pdf_report() {
    log_dir="$PWD/backup_Log/Network_Monitoring/Bandwidth"
    
    # Check if log directory exists
    if [ ! -d "$log_dir" ]; then
        dialog --msgbox "Error: Log directory does not exist." 5 40
        return 1
    fi

    # Get the list of log files (.txt files only)
    log_files=($(ls "$log_dir"/*.txt 2>/dev/null))
    
    if [[ ${#log_files[@]} -eq 0 ]]; then
        dialog --msgbox "Error: No log files found in the directory." 5 40
        return 1
    fi

    # Prepare the list of log files for the menu
    file_list=()
    index=1
    for file in "${log_files[@]}"; do
        file_list+=("$index" "$(basename "$file")")
        index=$((index + 1))
    done

    # Show the log files in a dialog menu for user selection
    selected_index=$(dialog --stdout --menu "Choose a log file to generate the PDF report:" 15 50 10 "${file_list[@]}")

    if [[ -z "$selected_index" ]]; then
        dialog --msgbox "Error: No log file selected." 5 40
        return 1
    fi

    # Get the selected log file based on the index
    log_file="${log_files[$((selected_index - 1))]}"
    png_file="${log_file%.txt}.png"

    # Use absolute path for the image
    abs_png_file="$log_dir/$(basename "$png_file")"
    
    # Check if the PNG file exists
    if [[ ! -f "$abs_png_file" ]]; then
        dialog --msgbox "Error: The graph image file $abs_png_file does not exist." 5 40
        return 1
    fi

    # Create HTML report
    html_file="${log_file%.txt}.html"

    echo "<html><head><title>Network Bandwidth Report</title></head><body>" > "$html_file"
    echo "<h1>Network Bandwidth Report</h1>" >> "$html_file"
    echo "<h2>Data from: $log_file</h2>" >> "$html_file"
    echo "<pre>" >> "$html_file"
    cat "$log_file" >> "$html_file"  # Add the log content to the report
    echo "</pre>" >> "$html_file"
    echo "<h3>Bandwidth Graph</h3>" >> "$html_file"
    echo "<img src='file://$abs_png_file' alt='Bandwidth Graph' style='max-width: 100%; height: auto;'>" >> "$html_file"
    echo "</body></html>" >> "$html_file"

    # Convert HTML to PDF using WeasyPrint
    pdf_file="${log_file%.txt}.pdf"
    python3 -c "
from weasyprint import HTML
HTML(filename='$html_file').write_pdf('$pdf_file')
"
    
    if [[ -f "$pdf_file" ]]; then
        dialog --msgbox "PDF Report has been generated and saved as $pdf_file." 5 50
    else
        dialog --msgbox "Error: Failed to generate PDF report." 5 40
    fi
}


save_and_send_report_via_telegram() {
    config_file="$PWD/telegram_config.txt"

    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        # Ask for Telegram Bot API token and User ID
        bot_api_token=$(dialog --stdout --inputbox "Enter your Telegram Bot API Token:" 8 40)
        user_id=$(dialog --stdout --inputbox "Enter the recipient's Telegram User ID:" 8 40)

        if [[ -z "$bot_api_token" || -z "$user_id" ]]; then
            dialog --msgbox "Error: API Token or User ID cannot be empty." 5 40
            return
        fi

        # Save the API token and User ID to a config file
        echo "BOT_API_TOKEN=$bot_api_token" > "$config_file"
        echo "USER_ID=$user_id" >> "$config_file"

        dialog --msgbox "Configuration saved. You won't need to input the API Token and User ID again." 5 40
    else
        # Load the API token and User ID from the config file
        source "$config_file"
    fi

    # Filter to show only PDF files from the directory
    pdf_files=($(find "$PWD/backup_Log/Network_Monitoring/Bandwidth/" -type f -name "*.pdf"))

    if [[ ${#pdf_files[@]} -eq 0 ]]; then
        dialog --msgbox "Error: No PDF files found in the directory." 5 40
        return
    fi

    # Prepare the list for dialog to let the user choose a PDF file
    file_list=()
    index=1
    for file in "${pdf_files[@]}"; do
        file_list+=("$index" "$(basename "$file")")
        index=$((index + 1))
    done

    # Show the PDF files in a dialog menu for user selection
    selected_index=$(dialog --stdout --menu "Choose a PDF file to send via Telegram:" 15 50 10 "${file_list[@]}")

    if [[ -z "$selected_index" ]]; then
        dialog --msgbox "Error: No PDF file selected." 5 40
        return
    fi

    # Get the selected PDF file based on the index
    pdf_file="${pdf_files[$((selected_index - 1))]}"

    # Use Python script to send the file via Telegram Bot API
    python3 << EOF
import requests

# Telegram Bot API token and User ID
bot_api_token = '$BOT_API_TOKEN'
user_id = '$USER_ID'

# PDF file to send
pdf_file = '$pdf_file'
pdf_filename = pdf_file.split('/')[-1]

# Send the file to Telegram
with open(pdf_file, 'rb') as f:
    response = requests.post(
        f'https://api.telegram.org/bot{bot_api_token}/sendDocument',
        data={'chat_id': user_id, 'caption': 'Here is your Network Bandwidth Report.'},
        files={'document': (pdf_filename, f)}
    )

print(response.status_code)
print(response.json())
EOF

    if [[ $? -eq 0 ]]; then
        dialog --msgbox "Report has been successfully sent via Telegram." 5 40
    else
        dialog --msgbox "Error: Failed to send the report via Telegram." 6 40
    fi
}


#################################################################
view_logs() {
    log_dir="$PWD/backup_Log/Network_Monitoring/Monitor_Resources"

    # Check if log directory exists
    if [ ! -d "$log_dir" ]; then
        dialog --msgbox "Error: Log directory does not exist." 5 40
        logs_resources_submenu
        return
    fi

    # Get the list of log files (.txt files only)
    log_files=($(find "$log_dir" -type f -name "*.txt"))

    if [[ ${#log_files[@]} -eq 0 ]]; then
        dialog --msgbox "Error: No log files found." 5 40
        logs_resources_submenu
        return
    fi

    # Ask the user what they want to do: View logs or Delete logs
    choice=$(dialog --stdout --menu "Choose an action:" 15 50 3 \
        1 "View Logs" \
        2 "Delete Logs" \
        3 "Back")

    if [[ -z "$choice" ]]; then
        logs_resources_submenu
        return
    fi

    case $choice in
        1)  # View Logs
            # Prepare the list of log files for the menu
            file_list=()
            index=1
            for file in "${log_files[@]}"; do
                file_list+=("$index" "$(basename "$file")")
                index=$((index + 1))
            done

            # Show the log files in a dialog menu for user selection
            selected_index=$(dialog --stdout --menu "Choose a log file to view:" 15 50 10 "${file_list[@]}")

            if [[ -z "$selected_index" ]]; then
                logs_resources_submenu
                return
            fi

            # Get the selected log file based on the index
            log_file="${log_files[$((selected_index - 1))]}"

            # Display the log file in a dialog textbox
            dialog --textbox "$log_file" 20 70
            logs_resources_submenu
            return
            ;;
        2)  # Delete Logs
            # Allow the user to select multiple log files for deletion
            file_list=()
            index=1
            for file in "${log_files[@]}"; do
                file_list+=("$index" "$(basename "$file")" "OFF")
                index=$((index + 1))
            done

            selected_files=$(dialog --stdout --checklist "Choose log files to delete:" 20 60 10 "${file_list[@]}")

            if [[ -z "$selected_files" ]]; then
                logs_resources_submenu
                return
            fi

            # Convert the selected file indices into log file names
            for i in $selected_files; do
                log_file="${log_files[$((i - 1))]}"
                rm -f "$log_file"
            done

            dialog --msgbox "Selected log files have been deleted." 5 40
            logs_resources_submenu
            return
            ;;
        3)  # Back to previous menu
            logs_resources_submenu
            return
            ;;
        *)
            dialog --msgbox "Invalid option." 5 40
            logs_resources_submenu
            return
            ;;
    esac
}


monitor_resources() {
    log_dir="$PWD/backup_Log/Network_Monitoring/Monitor_Resources"
    
    # Ensure the log directory exists
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi

    # Ask the user if they want to save the log for other resources (except nload)
    choice=$(dialog --stdout --menu "Monitor Resources" 15 50 5 \
        1 "CPU Usage" \
        2 "Memory Usage" \
        3 "Disk Usage" \
        4 "Network Usage (Nload in terminal, no log)" \
        5 "Exit")

    # Handle cancel and invalid choices
    if [[ -z "$choice" ]]; then
        logs_resources_submenu
        return
    fi

    # If the user selects Network Usage (nload), no log option will be given
    if [[ "$choice" == "4" ]]; then
        dialog --msgbox "Launching nload in terminal. Press Ctrl+C to stop." 5 40
        sudo nload  # Launch nload directly in the terminal without logging
        logs_resources_submenu  # Return to submenu after nload ends
        return
    fi

    # Ask the user if they want to save the log for other resources
    dialog --yesno "Do you want to save the resource monitoring log?" 7 40
    save_log=$?

    if [[ $save_log -eq 1 ]]; then
        dialog --msgbox "No log will be saved." 5 40
    fi

    # Create a timestamp for the log file
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    
    # Define the log file path if saving log is selected
    if [[ $save_log -eq 0 ]]; then
        log_file="$log_dir/resource_monitor_$timestamp.txt"
        touch "$log_file"
    fi

    case $choice in
        1)
            dialog --msgbox "Monitoring CPU usage. Press Ctrl+C to stop." 5 40
            if [[ $save_log -eq 0 ]]; then
                mpstat 1 | tee "$log_file" | dialog --programbox "Monitoring CPU usage" 20 70
            else
                mpstat 1 | dialog --programbox "Monitoring CPU usage" 20 70
            fi
            ;;
        2)
            dialog --msgbox "Monitoring Memory usage. Press Ctrl+C to stop." 5 40
            if [[ $save_log -eq 0 ]]; then
                vmstat 1 | tee "$log_file" | dialog --programbox "Monitoring Memory usage" 20 70
            else
                vmstat 1 | dialog --programbox "Monitoring Memory usage" 20 70
            fi
            ;;
        3)
            # Create a temporary file to store the disk usage output
            temp_file=$(mktemp)

            # Update disk usage every 5 seconds in the background
            (
                while true; do
                    df -h > "$temp_file"
                    sleep 5  # Adjust the refresh interval to 5 seconds
                done
            ) &

            # Capture the process ID of the background process
            pid=$!

            # Show the output using tailbox, which updates dynamically without EXIT button
            dialog --tailbox "$temp_file" 20 70

            # Kill the background process when dialog is closed
            kill $pid
            rm -f "$temp_file"
            logs_resources_submenu  # Return directly to the submenu
            return
            ;;
        5)
            logs_resources_submenu  # Return to submenu
            return
            ;;
        *)
            dialog --msgbox "Invalid option. Please try again." 5 40
            logs_resources_submenu  # Return to submenu if invalid choice
            ;;
    esac

    # After monitoring, inform the user if the log was saved and return to submenu
    if [[ $save_log -eq 0 ]]; then
        dialog --msgbox "Log has been saved at $log_file" 5 40
    fi

    logs_resources_submenu  # Return to submenu when done
}


#################################################################
function network_monitoring() {
    choice=$(dialog --menu "Network Monitoring Tool" 20 60 10 \
        1 "Monitoring Devices" \
        2 "Port and Traffic Monitoring" \
        3 "Bandwidth Monitoring and Reports" \
        4 "Logs and Resources" \
        5 "Exit" 3>&1 1>&2 2>&3)

    case $choice in
        1)
            device_monitoring_submenu ;;
        2)
            port_traffic_monitoring_submenu ;;
        3)
            bandwidth_reports_submenu ;;
        4)
            logs_resources_submenu ;;
        5)
        ./main_menu.sh
        exit 0 ;;
    esac
}

function device_monitoring_submenu() {
    choice=$(dialog --menu "Device and Network Monitoring" 20 60 10 \
        1 "Ping Devices" \
        2 "View Connections" \
        3 "Monitor DNS" \
        4 "Back to Main Menu" 3>&1 1>&2 2>&3)

    case $choice in
        1) ping_devices ;;
        2) view_connections ;;
        3) monitor_dns ;;
        4) show_menu ;;
    esac
}

function port_traffic_monitoring_submenu() {
    choice=$(dialog --menu "Port and Traffic Monitoring" 20 60 10 \
        1 "View Port Table" \
        2 "Check Specific Port" \
        3 "Monitor Ports and Traffic" \
        4 "Back to Main Menu" 3>&1 1>&2 2>&3)

    case $choice in
        1) view_port_table ;;
        2) check_specific_port ;;
        3) monitor_ports_and_traffic ;;
        4) show_menu ;;
    esac
}

function bandwidth_reports_submenu() {
    choice=$(dialog --menu "Bandwidth and Reports" 20 60 10 \
        1 "Monitor Bandwidth" \
        2 "Generate Bandwidth Graph" \
        3 "Generate PDF Report" \
        4 "Save and Send Report" \
        5 "Back to Main Menu" 3>&1 1>&2 2>&3)

    case $choice in
        1) monitor_bandwidth ;;
        2) generate_bandwidth_graph ;;
        3) generate_pdf_report ;;
        4) save_and_send_report_via_telegram ;;
        5) show_menu ;;
    esac
}

function logs_resources_submenu() {
    choice=$(dialog --menu "Logs and Resources" 20 60 10 \
        1 "View Logs" \
        2 "Monitor Resources" \
        3 "Back to Main Menu" 3>&1 1>&2 2>&3)

    case $choice in
        1) view_logs ;;
        2) monitor_resources ;;
        3) show_menu ;;
    esac
}
network_monitoring
