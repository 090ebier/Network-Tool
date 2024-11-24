#!/bin/bash

trap "clear; echo 'Exiting Network Tool Management...'; exit" SIGINT

BASE_DIR=$(dirname "$(readlink -f "$0")")
# Function to dynamically get terminal size
get_terminal_size() {
    term_height=$(tput lines)
    term_width=$(tput cols)
    dialog_height=$((term_height - 5))
    dialog_width=$((term_width - 10))
    if [ "$dialog_height" -lt 15 ]; then dialog_height=15; fi
    if [ "$dialog_width" -lt 50 ]; then dialog_width=50; fi
}


set_ip_address() {
    interfaces=$(ip -o link show | awk -F': ' '{print $2}')
    iface_choice=$(dialog --title "Select Interface" --menu "Choose an interface:" 15 40 4 $(echo "$interfaces" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # Cancel pressed, return to previous menu
    fi

    selected_iface=$(echo "$interfaces" | sed -n "${iface_choice}p")

    ip_type=$(dialog --title "IP Configuration" --menu "Do you want to set Static IP or use DHCP?" 15 40 2 \
        1 "Static" \
        2 "DHCP" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # Cancel pressed, return to previous menu
    fi

    # Function to check if Netplan is active
    is_netplan_active() {
        if command -v netplan >/dev/null 2>&1; then
            return 0 # Netplan is active
        else
            return 1  # Netplan is not active
        fi
    }

    # Function to clean up old configurations
    cleanup_previous_config() {
        if is_netplan_active; then
            sudo rm -f /etc/netplan/99-custom-"$selected_iface".yaml
        else
            sudo rm -f /etc/network/interfaces.d/"$selected_iface"
        fi

        sudo ip addr flush dev "$selected_iface"
        sudo ip route flush dev "$selected_iface"
    }


    if [ "$ip_type" -eq 1 ]; then
        # Static IP configuration
        ip_addr=$(dialog --title "Set Static IP" --inputbox "Enter IP Address:" 10 50 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi

        default_subnet_mask=$(guess_subnet_mask "$ip_addr")
        subnet_mask=$(dialog --title "Set Subnet Mask" --inputbox "Enter Subnet Mask (Default: $default_subnet_mask):" 10 50 "$default_subnet_mask" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi

        cidr_mask=$(subnet_mask_to_cidr "$subnet_mask")
        if [ $? -ne 0 ]; then
            dialog --msgbox "Invalid Subnet Mask entered. Please try again." 10 50
            return
        fi

        gateway=$(dialog --title "Set Gateway" --inputbox "Enter Gateway (Optional):" 10 50 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi
        
        # Apply Static Configuration
        cleanup_previous_config
        sudo ip addr add "$ip_addr/$cidr_mask" dev "$selected_iface"
        sudo ip route add default via "$gateway"

        if is_netplan_active; then
            sudo bash -c "cat << EOF > /etc/netplan/99-custom-$selected_iface.yaml
network:
    version: 2
    ethernets:
        $selected_iface:
            dhcp4: no
            addresses:
                - $ip_addr/$cidr_mask
            routes:
                - to: 0.0.0.0/0
                  via: $gateway
EOF"
            sudo chmod 600 /etc/netplan/*.yaml
            sudo netplan apply
            dialog --msgbox "Static IP configuration applied and saved in Netplan." 10 50
        else
            echo -e "auto $selected_iface\niface $selected_iface inet static\n    address $ip_addr\n    netmask $subnet_mask\n    gateway $gateway" | sudo tee /etc/network/interfaces.d/$selected_iface > /dev/null
            dialog --msgbox "Static IP configuration applied and saved to /etc/network/interfaces." 10 50
        fi
    else
        cleanup_previous_config
        # DHCP configuration
        if command -v dhclient > /dev/null 2>&1; then
            sudo dhclient -r "$selected_iface"
            sudo dhclient "$selected_iface"
            dhcp_method="dhclient"
        elif command -v dhcpcd > /dev/null 2>&1; then
            sudo dhcpcd -k "$selected_iface"
            sudo dhcpcd "$selected_iface"
            dhcp_method="dhcpcd"
        elif command -v udhcpc > /dev/null 2>&1 ; then
            sudo udhcpc -R -i "$selected_iface"
            dhcp_method="udhcpc"
        else
            dialog --msgbox "Neither dhclient nor dhcpcd found. Unable to configure DHCP." 10 50
            return
        fi

        if is_netplan_active; then
            sudo bash -c "cat << EOF > /etc/netplan/99-custom-$selected_iface.yaml
network:
    version: 2
    ethernets:
        $selected_iface:
            dhcp4: yes
EOF"
            sudo chmod 600 /etc/netplan/*.yaml
            sudo netplan apply
            dialog --msgbox "DHCP configuration applied using $dhcp_method and saved in Netplan." 10 50
        else
            echo -e "auto $selected_iface\niface $selected_iface inet dhcp" | sudo tee /etc/network/interfaces.d/$selected_iface > /dev/null
            dialog --msgbox "DHCP configuration applied using $dhcp_method and saved to /etc/network/interfaces." 10 50
        fi
    fi

    show_interface_brief
}

# Function to show the Interface Brief in table format
show_interface_brief() {
    interfaces=$(ip -o link show | awk -F': ' '{print $2}')
    printf "%-10s %-20s %-8s %-8s %-15s %-15s\n" "Interface" "IP Address" "Type" "Status" "Gateway" "Assignment" > /tmp/interface_brief.txt
    echo "---------------------------------------------------------------------------------" >> /tmp/interface_brief.txt

    for iface in $interfaces; do
        # Gather all IP addresses for the interface
        ip_addresses=$(ip -o addr show $iface | awk '{print $4}')

        # Determine status, gateway, and assignment only once per interface
        status=$(cat /sys/class/net/$iface/operstate)
        gateway=$(ip route | grep default | grep $iface | awk '{print $3}' || echo "Unknown")

        # Check if the interface is loopback, static, or using DHCP
        if [[ $iface == lo ]]; then
            assignment="Loopback"
        elif grep -q "dhcp" /etc/network/interfaces.d/$iface || grep -q "dhcp" /etc/netplan/*; then
            assignment="DHCP"
        else
            assignment="Static"
        fi

        # Loop through each IP address and print it in a separate row
        first_row=true
        for ip_addr in $ip_addresses; do
            # Determine IP type
            ip_type="Unknown"
            [[ $ip_addr == *":"* ]] && ip_type="IPv6" || ip_type="IPv4"

            if $first_row; then
                # Print the full row for the first IP address
                printf "%-10s %-20s %-8s %-8s %-15s %-15s\n" "$iface" "$ip_addr" "$ip_type" "$status" "$gateway" "$assignment" >> /tmp/interface_brief.txt
                first_row=false
            else
                # Print only IP address and leave other fields blank for additional IPs
                printf "%-10s %-20s %-8s %-8s %-15s %-15s\n" "" "$ip_addr" "$ip_type" "" "" "" >> /tmp/interface_brief.txt
            fi
        done
    done

    dialog --title "Interface Brief" --textbox /tmp/interface_brief.txt 20 80
}

# Function to show DNS Settings with colors and better formatting
show_dns_settings() {
    # Initialize variables for DNS servers
    dns_servers_resolv_conf=""
    dns_servers_systemd=""

    # Fetch DNS servers from /etc/resolv.conf
    if [ -f /etc/resolv.conf ]; then
        dns_servers_resolv_conf=$(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}')
    fi

    # Check if systemd-resolved is active and fetch DNS from it
    if systemctl is-active systemd-resolved > /dev/null 2>&1; then
        resolvectl_output=$(resolvectl status)

        # Extract all lines with DNS Servers and the corresponding link (interface)
        dns_lines=$(echo "$resolvectl_output" | grep -E "Link|DNS Servers")

        # Prepare the output for systemd-resolved DNS
        output="\n\Zb\Z4DNS Servers from systemd-resolved:\Zn\n\n"

        current_link=""
        while IFS= read -r line; do
            if [[ $line == *"Link"* ]]; then
                # Get the link (interface) name
                current_link=$(echo "$line" | awk '{print $4}')
                output+="\n\Zb\Z3Link (Interface): \Zn$current_link\n"
            elif [[ $line == *"DNS Servers"* ]]; then
                # Get all DNS Servers for the current link
                dns_servers=$(echo "$line" | awk '{for (i=3; i<=NF; i++) print $i}')
                output+="\Zb\Z2DNS Servers:\Zn\n"
                for dns in $dns_servers; do
                    output+="    $dns\n"
                done
            fi
        done <<< "$dns_lines"
    fi

    # Separate IPv4 and IPv6 addresses from /etc/resolv.conf
    dns_ipv4_resolv_conf=$(echo "$dns_servers_resolv_conf" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
    dns_ipv6_resolv_conf=$(echo "$dns_servers_resolv_conf" | grep -Eo '([0-9a-fA-F:]+:+)+[0-9a-fA-F]+')

    # Prepare the output for /etc/resolv.conf DNS
    output+="\n\Zb\Z4DNS Servers from /etc/resolv.conf:\Zn\n\n"
    
    if [ -n "$dns_ipv4_resolv_conf" ]; then
        output+="\Zb\Z3IPv4:\Zn\n"
        for ip in $dns_ipv4_resolv_conf; do
            output+="    \Zb\Z2$ip\Zn\n"
        done
    else
        output+="\Zb\Z3IPv4:\Zn\n    \Zb\Z1No IPv4 DNS found in /etc/resolv.conf.\Zn\n"
    fi
    
    if [ -n "$dns_ipv6_resolv_conf" ]; then
        output+="\n\Zb\Z3IPv6:\Zn\n"
        for ip in $dns_ipv6_resolv_conf; do
            output+="    \Zb\Z2$ip\Zn\n"
        done
    else
        output+="\n\Zb\Z3IPv6:\Zn\n    \Zb\Z1No IPv6 DNS found in /etc/resolv.conf.\Zn\n"
    fi

    # Show the dialog box with the formatted DNS settings
    dialog --colors --backtitle "Network Management Tool" --title "\Zb\Z4DNS Settings\Zn" --msgbox "$output" 20 70
}


# Function to guess Subnet Mask based on the first octet of the IP address
guess_subnet_mask() {
    local ip=$1
    local first_octet=$(echo $ip | cut -d. -f1)
    
    if ((first_octet >= 1 && first_octet <= 126)); then
        echo "255.0.0.0"  # Class A
    elif ((first_octet >= 128 && first_octet <= 191)); then
        echo "255.255.0.0"  # Class B
    elif ((first_octet >= 192 && first_octet <= 223)); then
        echo "255.255.255.0"  # Class C
    else
        echo "255.255.255.0"  # Default fallback
    fi
}

subnet_mask_to_cidr() {
    local mask=$1
    local cidr=0

    # Iterate over each octet in the subnet mask
    for octet in $(echo "$mask" | tr '.' ' '); do
        case $octet in
            255) cidr=$((cidr + 8)) ;;
            254) cidr=$((cidr + 7)) ;;
            252) cidr=$((cidr + 6)) ;;
            248) cidr=$((cidr + 5)) ;;
            240) cidr=$((cidr + 4)) ;;
            224) cidr=$((cidr + 3)) ;;
            192) cidr=$((cidr + 2)) ;;
            128) cidr=$((cidr + 1)) ;;
            0) ;; # No bits to add
            *) echo "Invalid subnet mask: $mask" >&2; return 1 ;;
        esac
    done

    echo "$cidr"
}

set_ip_address() {
    interfaces=$(ip -o link show | awk -F': ' '{print $2}')
    iface_choice=$(dialog --title "Select Interface" --menu "Choose an interface:" 15 40 4 $(echo "$interfaces" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # Cancel pressed, return to previous menu
    fi

    selected_iface=$(echo "$interfaces" | sed -n "${iface_choice}p")

    ip_type=$(dialog --title "IP Configuration" --menu "Do you want to set Static IP or use DHCP?" 15 40 2 \
        1 "Static" \
        2 "DHCP" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # Cancel pressed, return to previous menu
    fi

    # Function to check if Netplan is active
    is_netplan_active() {
        if command -v netplan >/dev/null 2>&1; then
            return 0 # Netplan is active
        else
            return 1  # Netplan is not active
        fi
    }

    # Function to clean up old configurations
    cleanup_previous_config() {
        if is_netplan_active; then
            sudo rm -f /etc/netplan/99-custom-"$selected_iface".yaml
        else
            sudo rm -f /etc/network/interfaces.d/"$selected_iface"
        fi

        sudo ip addr flush dev "$selected_iface"

        default_gateway=$(ip route show default | grep "$selected_iface" | awk '{print $3}')

        if [ -n "$default_gateway" ]; then
            sudo ip route del default via "$default_gateway" dev "$selected_iface" 2>/dev/null || true
        fi
    }



    if [ "$ip_type" -eq 1 ]; then
        # Static IP configuration
        ip_addr=$(dialog --title "Set Static IP" --inputbox "Enter IP Address:" 10 50 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi

        default_subnet_mask=$(guess_subnet_mask "$ip_addr")
        subnet_mask=$(dialog --title "Set Subnet Mask" --inputbox "Enter Subnet Mask (Default: $default_subnet_mask):" 10 50 "$default_subnet_mask" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi

        cidr_mask=$(subnet_mask_to_cidr "$subnet_mask")
        if [ $? -ne 0 ]; then
            dialog --msgbox "Invalid Subnet Mask entered. Please try again." 10 50
            return
        fi

        gateway=$(dialog --title "Set Gateway" --inputbox "Enter Gateway (Optional):" 10 50 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi

        # Apply Static Configuration
        cleanup_previous_config
        sudo ip addr add "$ip_addr/$cidr_mask" dev "$selected_iface"
        sudo ip route add default via "$gateway"

        if is_netplan_active; then
            sudo bash -c "cat << EOF > /etc/netplan/99-custom-$selected_iface.yaml
network:
    version: 2
    ethernets:
        $selected_iface:
            dhcp4: no
            addresses:
                - $ip_addr/$cidr_mask
            routes:
                - to: 0.0.0.0/0
                  via: $gateway
EOF"
            sudo chmod 600 /etc/netplan/*.yaml
            sudo netplan apply
            dialog --msgbox "Static IP configuration applied and saved in Netplan." 10 50
        else
            echo -e "auto $selected_iface\niface $selected_iface inet static\n    address $ip_addr\n    netmask $subnet_mask\n    gateway $gateway" | sudo tee /etc/network/interfaces.d/$selected_iface > /dev/null
            dialog --msgbox "Static IP configuration applied and saved to /etc/network/interfaces." 10 50
        fi
    else
        # DHCP configuration
        cleanup_previous_config
        if command -v dhclient > /dev/null 2>&1; then
            sudo dhclient -r "$selected_iface"
            sudo dhclient "$selected_iface"
            dhcp_method="dhclient"
        elif command -v dhcpcd > /dev/null 2>&1; then
            sudo dhcpcd -k "$selected_iface"
            sudo dhcpcd "$selected_iface"
            dhcp_method="dhcpcd"
        elif command -v udhcpc > /dev/null 2>&1 ; then
            sudo udhcpc -R -i "$selected_iface"
            dhcp_method="udhcpc"
        else
            dialog --msgbox "Neither dhclient nor dhcpcd found. Unable to configure DHCP." 10 50
            return
        fi

        if is_netplan_active; then
            sudo bash -c "cat << EOF > /etc/netplan/99-custom-$selected_iface.yaml
network:
    version: 2
    ethernets:
        $selected_iface:
            dhcp4: yes
EOF"
            sudo chmod 600 /etc/netplan/*.yaml
            sudo netplan apply
            dialog --msgbox "DHCP configuration applied using $dhcp_method and saved in Netplan." 10 50
        else
            echo -e "auto $selected_iface\niface $selected_iface inet dhcp" | sudo tee /etc/network/interfaces.d/$selected_iface > /dev/null
            dialog --msgbox "DHCP configuration applied using $dhcp_method and saved to /etc/network/interfaces." 10 50
        fi
    fi

    show_interface_brief
}





manage_routes() {
    get_terminal_size
    
    # تابع تشخیص نوع پیکربندی شبکه
    detect_network_config() {
        if [ -d /etc/netplan ] && [ "$(ls -A /etc/netplan)" ]; then
            echo "netplan"
        elif [ -f /etc/network/interfaces ]; then
            echo "interfaces"
        else
            echo "unsupported"
        fi
    }

    # منوی اصلی مدیریت روت‌ها
    while true; do
        action=$(dialog --colors --backtitle "\Zb\Z4Route Management\Zn" --title "\Zb\Z3Manage Routes\Zn" \
            --menu "\n\Zb\Z3Choose an action:\Zn" "$dialog_height" "$dialog_width" 5 \
            1 "\Zb\Z2Add Route\Zn" \
            2 "\Zb\Z2Delete Route\Zn" \
            3 "\Zb\Z2View Current Routes\Zn" \
            4 "\Zb\Z1Back to Main Menu\Zn" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then return; fi

        case $action in
        1)  # افزودن روت جدید
            destination=$(dialog --stdout --inputbox "Enter the destination network (e.g., 192.168.1.0/24):" "$dialog_height" "$dialog_width")
            if [[ -z "$destination" ]]; then
                dialog --colors --msgbox "\Zb\Z1No destination entered!\Zn" 5 40
                continue
            fi

            gateway=$(dialog --stdout --inputbox "Enter the gateway IP (e.g., 192.168.1.1):" "$dialog_height" "$dialog_width")
            if [[ -z "$gateway" ]]; then
                dialog --colors --msgbox "\Zb\Z1No gateway entered!\Zn" 5 40
                continue
            fi

            # دریافت متریک از کاربر با مقدار پیش‌فرض 100
            metric=$(dialog --stdout --inputbox "Enter the metric (default is 100):" "$dialog_height" "$dialog_width")
            if [[ -z "$metric" ]]; then
                metric=100  # مقدار پیش‌فرض برای متریک
            fi

            # دریافت لیست اینترفیس‌ها و نمایش به کاربر
            interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)  # دریافت لیست اینترفیس‌ها به جز lo

            # آماده‌سازی لیست برای منوی dialog
            interface_list=()
            index=1
            for iface in $interfaces; do
                interface_list+=("$index" "$iface")
                index=$((index + 1))
            done

            # نمایش منوی انتخاب اینترفیس به کاربر
            selected_index=$(dialog --stdout --menu "Choose a network interface:" "$dialog_height" "$dialog_width" "${#interface_list[@]}" "${interface_list[@]}")
            if [[ -z "$selected_index" ]]; then
                dialog --colors --msgbox "\Zb\Z1No interface selected!\Zn" 5 40
                continue
            fi

            # انتخاب اینترفیس بر اساس ورودی کاربر
            interface="${interface_list[$((selected_index * 2 - 1))]}"

            # اجرای دستور برای افزودن روت با متریک
            sudo ip route add "$destination" via "$gateway" dev "$interface" metric "$metric"
            if [[ $? -eq 0 ]]; then
                dialog --colors --msgbox "\Zb\Z2Route added successfully!\Zn" 5 40
            else
                dialog --colors --msgbox "\Zb\Z1Failed to add route!\Zn" 5 40
                continue
            fi

            # پرسش از کاربر برای ذخیره‌سازی دائمی
            dialog --yesno "Do you want to save this route persistently?" 10 50
            if [ $response -eq 0 ]; then
                # تشخیص نوع پیکربندی شبکه
                config_type=$(detect_network_config)

                if [ "$config_type" == "interfaces" ]; then
                    # بررسی وجود دایرکتوری /etc/network/interfaces.d/ و ایجاد آن در صورت عدم وجود
                    if [ ! -d /etc/network/interfaces.d ]; then
                        sudo mkdir -p /etc/network/interfaces.d
                    fi

                    # تنظیم مقدار پیش‌فرض برای metric در صورت عدم وارد کردن کاربر
                    metric=${metric:-100}

                    # افزودن روت به فایل مربوط به اینترفیس
                    echo -e "up ip route add $destination via $gateway dev $interface metric $metric" | sudo tee -a /etc/network/interfaces.d/$interface > /dev/null
                    dialog --colors --msgbox "\Zb\Z2Route saved permanently in /etc/network/interfaces.d/$interface.\Zn" 5 40
                elif [ "$config_type" == "netplan" ]; then
                    # تنظیم پیکربندی دائمی برای Netplan
                    sudo bash -c "cat << EOF >> /etc/netplan/99-custom-routes.yaml
            network:
                version: 2
                ethernets:
                    $interface:
                        routes:
                            - to: $destination
                            via: $gateway
                            metric: $metric
            EOF"
                    sudo chmod 600 /etc/netplan/*.yaml
                    sudo netplan apply
                    dialog --colors --msgbox "\Zb\Z2Route saved permanently in Netplan.\Zn" 5 40
                else
                    dialog --colors --msgbox "\Zb\Z1Unsupported network configuration. Route not saved permanently.\Zn" 5 40
                fi
            fi
            ;;


            2)  # حذف روت
                routes=$(ip route show)  # دریافت لیست روت‌های فعلی

                if [[ -z "$routes" ]]; then
                    dialog --colors --msgbox "\Zb\Z1No routes available to delete!\Zn" 5 40
                    continue
                fi

                # آماده‌سازی لیست روت‌ها برای نمایش در منوی dialog
                route_list=()
                index=1
                while IFS= read -r route; do
                    route_list+=("$index" "$route")
                    index=$((index + 1))
                done <<< "$routes"

                selected_route_index=$(dialog --stdout --menu "Choose a route to delete:" "$dialog_height" "$dialog_width" "${#route_list[@]}" "${route_list[@]}")
                if [[ -z "$selected_route_index" ]]; then
                    dialog --colors --msgbox "\Zb\Z1No route selected!\Zn" 5 40
                    continue
                fi

                selected_route="${route_list[$((selected_route_index * 2 - 1))]}"

                destination=$(echo "$selected_route" | awk '{print $1}')

                # حذف روت
                dialog --yesno "Are you sure you want to delete the Route: $destination?" "$dialog_height" "$dialog_width"
                response=$?
                if [ $response -eq 0 ]; then
                    sudo ip route del "$destination"
                    if [ $? -eq 0 ]; then
                        dialog --colors --msgbox "\Zb\Z2Route deleted successfully!\Zn" 5 40
                    else
                        dialog --colors --msgbox "\Zb\Z1Failed to delete route!\Zn" 5 40
                    fi
                else
                    dialog --msgbox "Route deletion canceled." 5 40
                fi
                ;;

            3)  # نمایش روت‌های فعلی
                routes=$(ip route show) 

                if [[ -z "$routes" ]]; then
                    dialog --colors --msgbox "\Zb\Z1No routes available!\Zn" 5 40
                    return
                fi

                # آماده‌سازی فایل موقت برای ذخیره روت‌ها
                temp_file=$(mktemp)

                # عنوان ستون‌ها
                echo -e "| Destination    | Gateway        | Metric | Interface |" > "$temp_file"
                echo -e "--------------------------------------------------------" >> "$temp_file"

            echo "$routes" | awk '
            {
                dest = ($1 == "default") ? "default" : $1;
                gw = ($2 == "via") ? $3 : "-";

                # مقداردهی پیش‌فرض برای metric و interface
                metric = "-";
                iface = "-";

                # یافتن metric و interface
                for (i = 1; i <= NF; i++) {
                    if ($i == "metric") {
                        metric = $(i + 1);  # مقدار بعد از metric را به عنوان عدد متریک در نظر بگیر
                    }
                    if ($i == "dev") {
                        iface = $(i + 1);  # مقدار بعد از dev را به عنوان interface در نظر بگیر
                    }
                }

                printf "| %-14s | %-13s | %-6s | %-9s |\n", dest, gw, metric, iface;
            }'>> "$temp_file"

                # نمایش روت‌ها در قالب جدول
                dialog --colors --title "\Zb\Z4Routing Table\Zn" --textbox "$temp_file" "$dialog_height" "$dialog_width"

                # حذف فایل موقت
                rm -f "$temp_file"
                ;;


            4)
                return
                ;;
        esac
    done
}


# Function to set DNS with colors and persistence option for both NetworkManager and Netplan
set_dns() {
    dns_choice=$(dialog --colors --backtitle "Network Management Tool" --title "\Zb\Z4Set DNS\Zn" --menu "\n\Zb\Z3Choose DNS provider:\Zn" 15 60 6 \
        1 "\Zb\Z3Google DNS (8.8.8.8 / 8.8.4.4, 2001:4860:4860::8888 / 2001:4860:4860::8844)\Zn" \
        2 "\Zb\Z3Cloudflare DNS (1.1.1.1 / 1.0.0.1, 2606:4700:4700::1111 / 2606:4700:4700::1001)\Zn" \
        3 "\Zb\Z3Quad9 DNS (9.9.9.9 / 149.112.112.112, 2620:fe::fe / 2620:fe::9)\Zn" \
        4 "\Zb\Z3OpenDNS (208.67.222.222 / 208.67.220.220, 2620:119:35::35 / 2620:119:53::53)\Zn" \
        5 "\Zb\Z3ShekanDNS (178.22.122.100 / 185.51.200.2)\Zn" \
        6 "\Zb\Z1Custom DNS\Zn" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # اگر کاربر Cancel را بزند، تابع خارج می‌شود
    fi

    # انتخاب DNS ها بر اساس انتخاب کاربر
    case $dns_choice in
        1) dns_servers_ipv4="8.8.8.8 8.8.4.4"; dns_servers_ipv6="2001:4860:4860::8888 2001:4860:4860::8844" ;;
        2) dns_servers_ipv4="1.1.1.1 1.0.0.1"; dns_servers_ipv6="2606:4700:4700::1111 2606:4700:4700::1001" ;;
        3) dns_servers_ipv4="9.9.9.9 149.112.112.112"; dns_servers_ipv6="2620:fe::fe 2620:fe::9" ;;
        4) dns_servers_ipv4="208.67.222.222 208.67.220.220"; dns_servers_ipv6="2620:119:35::35 2620:119:53::53" ;;
        5) dns_servers_ipv4="178.22.122.100  185.51.200.2";dns_servers_ipv6="";;
        6) 
            dns_servers=$(dialog --colors --title "\Zb\Z4Custom DNS\Zn" --inputbox "Enter custom DNS servers (comma-separated):" 10 50 3>&1 1>&2 2>&3) 
            dns_servers_ipv4=$(echo "$dns_servers" | tr ',' ' ' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
            dns_servers_ipv6=$(echo "$dns_servers" | tr ',' ' ' | grep -Eo '([0-9a-fA-F:]+:+)+[0-9a-fA-F]+')
            ;;
    esac

    # حذف تنظیمات قبلی و تنظیم DNS ها در /etc/resolv.conf
    sudo bash -c "echo '' > /etc/resolv.conf"
    sudo bash -c "echo -e 'nameserver ${dns_servers_ipv4// /\\nnameserver }' >> /etc/resolv.conf"
    sudo bash -c "echo -e 'nameserver ${dns_servers_ipv6// /\\nnameserver }' >> /etc/resolv.conf"

    # سوال از کاربر برای اعمال تغییرات به صورت دائمی
    dialog --colors --backtitle "Network Management Tool" --yesno "\n\Zb\Z3Do you want to make this DNS configuration persistent after reboot?\Zn" 10 50
    response=$?
    
    if [ $response -eq 0 ]; then
        # تنظیم DNS در /etc/systemd/resolved.conf
        all_dns_servers="${dns_servers_ipv4} ${dns_servers_ipv6}"

        # اگر خط DNS= وجود ندارد، آن را اضافه می‌کنیم
        if grep -q '^DNS=' /etc/systemd/resolved.conf; then
            sudo bash -c "sed -i 's/^DNS=.*/DNS=${all_dns_servers}/' /etc/systemd/resolved.conf"
        else
            sudo bash -c "echo 'DNS=${all_dns_servers}' >> /etc/systemd/resolved.conf"
        fi

        # Restart systemd-resolved to apply persistent changes
        sudo systemctl restart systemd-resolved

        dialog --colors --backtitle "Network Management Tool" --msgbox "\n\Zb\Z3DNS settings have been saved and will persist after reboot.\Zn" 10 50
    else
        dialog --colors --backtitle "Network Management Tool" --msgbox "\n\Zb\Z3DNS settings have been applied, but will not persist after reboot.\Zn" 10 50
    fi
}


# Function to set Hostname with colors
set_hostname() {
    new_hostname=$(dialog --colors --backtitle "Network Management Tool" --title "Set Hostname" --inputbox "Enter new hostname:" 10 50 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # Cancel pressed, return to the previous menu
    fi

    dialog --colors --backtitle "Network Management Tool" --title "Changing Hostname" --infobox "\nChanging the hostname, please wait..." 10 50
    sleep 2

    sudo hostnamectl set-hostname "$new_hostname"
    sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/g" /etc/hosts

    dialog --colors --backtitle "Network Management Tool" --title "Hostname Set" --msgbox "\n\Zb\Z3Hostname changed to $new_hostname.\Zn" 10 50
}

# Main function for Basic Linux Network Configuration
basic_linux_network_configuration() {
    while true; do
        option=$(dialog --colors --backtitle "Network Management Tool" --title "\Zb\Z4Basic Linux Network Configuration\Zn" \
            --menu "\n\Zb\Z3Choose an option:\Zn" 15 60 7 \
            1 "\Zb\Z2Interface Brief\Zn" \
            2 "\Zb\Z2DNS Settings\Zn" \
            3 "\Zb\Z2Set IP Address\Zn" \
            4 "\Zb\Z2Route Management\Zn" \
            5 "\Zb\Z2Set DNS\Zn" \
            6 "\Zb\Z2Set Hostname\Zn" \
            7 "\Zb\Z1Return to Main Menu\Zn" 3>&1 1>&2 2>&3)

        case $option in
            1) show_interface_brief ;;
            2) show_dns_settings ;;
            3) set_ip_address ;;
            4) manage_routes ;;
            5) set_dns ;;
            6) set_hostname ;;
            7) clear;bash $BASE_DIR/../net-tool.sh; exit 0 ;;  # Return to main menu and close this script
        esac
    done
}

# Run the main configuration menu
basic_linux_network_configuration
