#!/bin/bash

config_file="$HOME/net-tool/resource_monitoring_config.txt"
log_file="$HOME/net-tool/resource_monitoring.log"
interval=60  

send_message_to_telegram() {
    local message=$1
    local config_file="$HOME/net-tool/telegram_config.txt"

    if [ ! -f "$config_file" ]; then
        echo "Telegram configuration not found." >> "$log_file"
        exit 1
    fi

    source "$config_file"
    
    bot_api_token=$BOT_API_TOKEN
    user_id=$USER_ID

    local host_name=$(hostname)
    message="Hostname: $host_name\n\n$message"
    
    formatted_message=$(echo "$message" | sed 's/\\n/%0A/g')

    curl -s -X POST "https://api.telegram.org/bot$bot_api_token/sendMessage" \
        -d chat_id="$user_id" \
        -d text="$formatted_message" > /dev/null
}


if [ ! -f "$config_file" ]; then
    echo "Error: No resource monitoring config found." >> "$log_file"
    exit 1
fi
source "$config_file"

while true; do
    current_cpu_usage=$(mpstat 1 1 | awk '/Average/ {print 100 - $NF}')
    
    current_memory_usage=$(free | awk '/Mem:/ {print ($3/$2)*100}')
    
    current_disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    alert_msg=""

    if (( $(echo "$current_cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
        alert_msg+="CPU usage is at ${current_cpu_usage}%, higher than the threshold (${CPU_THRESHOLD}%).\n\n"
    fi

    if (( $(echo "$current_memory_usage > $MEMORY_THRESHOLD" | bc -l) )); then
        alert_msg+="Memory usage is at ${current_memory_usage}%, higher than the threshold (${MEMORY_THRESHOLD}%).\n\n"
    fi

    if (( $(echo "$current_disk_usage > $DISK_THRESHOLD" | bc -l) )); then
        alert_msg+="Disk usage is at ${current_disk_usage}%, higher than the threshold (${DISK_THRESHOLD}%).\n\n"
    fi

    if [[ ! -z "$alert_msg" ]]; then
        send_message_to_telegram "$alert_msg"
        echo "Alert sent: $alert_msg" >> "$log_file"
    fi

    sleep $interval
done
