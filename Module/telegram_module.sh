#!/bin/bash
BASE_DIR=$(dirname "$(readlink -f "$0")")
config_file="$HOME/net-tool/telegram_config.txt"
log_dir="$HOME/net-tool/backup_Log/Network_Monitoring/"
monitoring_service_file="/etc/systemd/system/resource_monitoring.service"

get_terminal_size() {
    term_height=$(tput lines)
    term_width=$(tput cols)
    dialog_height=$((term_height - 5))
    dialog_width=$((term_width - 10))
    if [ "$dialog_height" -lt 15 ]; then dialog_height=15; fi
    if [ "$dialog_width" -lt 50 ]; then dialog_width=50; fi
}

setup_telegram_config() {
    if [ ! -f "$config_file" ]; then
        bot_api_token=$(dialog --colors --stdout --inputbox "\Zb\Z2Enter your Telegram Bot API Token:\Zn" 8 40)
        user_id=$(dialog --colors --stdout --inputbox "\Zb\Z2Enter the recipient's Telegram User ID:\Zn" 8 40)

        if [[ -z "$bot_api_token" || -z "$user_id" ]]; then
            dialog --colors --msgbox "\Zb\Z1Error: API Token or User ID cannot be empty.\Zn" 5 40
            return 1
        fi

        # ذخیره API Token و User ID در فایل تنظیمات
        echo "BOT_API_TOKEN=$bot_api_token" > "$config_file"
        echo "USER_ID=$user_id" >> "$config_file"

        dialog --colors --msgbox "\Zb\Z2Configuration saved. You won't need to input the API Token and User ID again.\Zn" 5 40
    else
        source "$config_file"
    fi
}

send_file_to_telegram() {
    local file_path=$1
    local caption=$2

    if [ ! -f "$config_file" ]; then
        echo "Error: Telegram config not found."
        return 1
    fi
    source "$config_file"

    python3 << EOF
import requests
bot_api_token = '$BOT_API_TOKEN'
user_id = '$USER_ID'
file_path = "$file_path"
caption = "$caption"

with open(file_path, 'rb') as f:
    response = requests.post(
        f'https://api.telegram.org/bot{bot_api_token}/sendDocument',
        data={'chat_id': user_id, 'caption': caption},
        files={'document': (file_path.split('/')[-1], f)}
    )

print(response.status_code)
print(response.json())
EOF
}

send_selected_logs_via_telegram() {
    get_terminal_size  

    if [ ! -d "$log_dir" ]; then
        dialog --colors --msgbox "\Zb\Z1Error: Log directory does not exist.\Zn" 5 40
        return
    fi

    sub_dirs=($(find "$log_dir" -mindepth 1 -maxdepth 1 -type d))
    
    if [[ ${#sub_dirs[@]} -eq 0 ]]; then
        dialog --colors --msgbox "\Zb\Z1Error: No log directories found in $log_dir.\Zn" 5 40
        return
    fi

    file_list=()
    index=1
    for dir in "${sub_dirs[@]}"; do
        dir_name=$(basename "$dir")
        file_list+=("$index" "$dir_name" "OFF")  # "OFF" برای غیرفعال کردن چک‌باکس پیش‌فرض
        index=$((index + 1))
    done

    selected_dirs=$(dialog --stdout --checklist "Choose log directories to send via Telegram:" 15 60 10 "${file_list[@]}")

    if [[ -z "$selected_dirs" ]]; then
        dialog --colors --msgbox "No directories selected for sending." 5 40
        return
    fi

    selected_names=()
    for i in $selected_dirs; do
        dir_name="${file_list[$((i * 3 - 2))]}"
        selected_names+=("$dir_name")
        zip_file="$log_dir/${dir_name}.zip"

        # زیپ کردن محتویات پوشه
        zip -r "$zip_file" "$log_dir/$dir_name" > /dev/null 2>&1
        
        if [[ ! -f "$zip_file" ]]; then
            dialog --colors --msgbox "\Zb\Z1Error: Failed to create ZIP for $dir_name.\Zn" 5 40
            continue
        fi

        # ارسال فایل زیپ به تلگرام
        send_file_to_telegram "$zip_file" "Here is the log report for $dir_name."

        # حذف فایل زیپ پس از ارسال
        rm -f "$zip_file"
    done

    if [[ ${#selected_names[@]} -gt 0 ]]; then
        dialog --colors --msgbox "\Zb\Z2The following directories were successfully sent via Telegram\Zn" 7 50
    fi
}


############################################
# تابع ساخت و راه‌اندازی سرویس مانیتورینگ
create_monitoring_service() {
    service_file="/etc/systemd/system/resource_monitoring.service"
    
    sudo bash -c "cat <<EOF > $service_file
[Unit]
Description=Resource Monitoring and Telegram Notification Service
After=network.target

[Service]
ExecStart=/bin/bash $BASE_DIR/resource_monitoring.sh
Restart=always
User=$USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=$HOME/.Xauthority

[Install]
WantedBy=multi-user.target
EOF"

    # فعال‌سازی سرویس
    sudo systemctl daemon-reload
    sudo systemctl enable resource_monitoring.service
    sudo systemctl start resource_monitoring.service

    dialog --colors --msgbox "\Zb\Z2Resource Monitoring Service Created and Started.\Zn" 5 40
}


check_service_status() {
    service_status=$(systemctl is-active resource_monitoring.service)
    
    if [[ "$service_status" == "active" ]]; then
        dialog --colors --msgbox "\Zb\Z2The Resource Monitoring Service is \Zb\Z1ACTIVE\Zn" 5 40
    else
        dialog --colors --msgbox "\Zb\Z1The Resource Monitoring Service is NOT active.\Zn" 5 40
    fi
}

reset_monitoring_service() {
    service_name="resource_monitoring.service"

    # ریستارت سرویس
    sudo systemctl restart "$service_name"
    if [ $? -eq 0 ]; then
        dialog --colors --msgbox "\Zb\Z2Service $service_name restarted successfully.\Zn" 7 40
    else
        dialog --colors --msgbox "\Zb\Z1Failed to restart $service_name.\Zn" 7 40
        return 1
    fi
}



# تابع حذف سرویس مانیتورینگ
remove_monitoring_service() {
    sudo systemctl stop resource_monitoring.service
    sudo systemctl disable resource_monitoring.service
    sudo rm /etc/systemd/system/resource_monitoring.service
    sudo systemctl daemon-reload

    dialog --colors --msgbox "\Zb\Z2Resource Monitoring Service Removed.\Zn" 5 40
}


monitoring_service_menu() {
    get_terminal_size
    while true; do
        choice=$(dialog --colors --menu "\Zb\Z2Resource Monitoring Service Management\Zn" "$dialog_height" "$dialog_width" 4 \
            1 "\Zb\Z2Create Monitoring Service\Zn" \
            2 "\Zb\Z2Check Service Status\Zn" \
            3 "\Zb\Z2Remove Monitoring Service\Zn" \
            4 "\Zb\Z3Restart Monitoring Service\Zn" \
            5 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                create_monitoring_service
                ;;
            2)
                check_service_status
                ;;
            3)
                remove_monitoring_service
                ;;
            4)
                reset_monitoring_service
                ;;
            5)  break  
                ;;
            *)
                dialog --colors --msgbox "\Zb\Z1Invalid option. Please try again.\Zn" 5 40
                ;;
        esac
    done
}

################################################################

set_resource_thresholds() {
    config_file="$HOME/net-tool/resource_monitoring_config.txt"

    CPU_THRESHOLD=$(dialog --stdout --inputbox "Enter CPU usage threshold (in percentage):" 8 40)
    MEMORY_THRESHOLD=$(dialog --stdout --inputbox "Enter Memory usage threshold (in percentage):" 8 40)
    DISK_THRESHOLD=$(dialog --stdout --inputbox "Enter Disk usage threshold (in percentage):" 8 40)

    echo "CPU_THRESHOLD=$CPU_THRESHOLD" > "$config_file"
    echo "MEMORY_THRESHOLD=$MEMORY_THRESHOLD" >> "$config_file"
    echo "DISK_THRESHOLD=$DISK_THRESHOLD" >> "$config_file"
    
    sudo systemctl daemon-reload
    sudo systemctl restart resource_monitoring.service

    dialog --colors --msgbox "\Zb\Z2Resource Thresholds Saved.\Zn" 5 40
}




telegram_module_menu() {
    get_terminal_size
    setup_telegram_config  

    while true; do
        choice=$(dialog --colors --backtitle "\Zb\Z4Network Monitoring Management\Zn" --menu "\n\Zb\Z4 Telegram Module\Zn\n\n\Zb\Z3Choose an option below:\Zn" "$dialog_height" "$dialog_width" 10 \
            1 "\Zb\Z2Send Selected Logs to Telegram\Zn" \
            2 "\Zb\Z2Manage Resource Monitoring Service\Zn" \
            3 "\Zb\Z4Set Resource Monitoring Thresholds\Zn" \
            4 "\Zb\Z1Return to Main Menu\Zn" 3>&1 1>&2 2>&3)

        case $choice in
            1) send_selected_logs_via_telegram ;;
            2) monitoring_service_menu ;;  
            3) set_resource_thresholds ;; 
            4) clear;sudo bash network_monitoring.sh; exit 0 ;;  # بازگشت به منوی مانیتورینگ
            *) dialog --colors --msgbox "\n\Zb\Z1Invalid option! Please choose a valid option.\Zn" 6 40 ;;
        esac
    done
}
telegram_module_menu
