#!/bin/bash

# Function to show the Interface Brief in table format
show_interface_brief() {
    interfaces=$(ip -o link show | awk -F': ' '{print $2}')
    printf "%-10s %-20s %-8s %-8s %-15s %-15s\n" "Interface" "IP Address" "Type" "Status" "Gateway" "Assignment" > /tmp/interface_brief.txt
    echo "---------------------------------------------------------------------------------" >> /tmp/interface_brief.txt

    for iface in $interfaces; do
        ip_addr=$(ip -o -4 addr show $iface | awk '{print $4}' || echo "Unknown")
        [ -z "$ip_addr" ] && ip_addr=$(ip -o -6 addr show $iface | awk '{print $4}' || echo "Unknown")

        ip_type="Unknown"
        [[ $ip_addr == *":"* ]] && ip_type="IPv6" || ip_type="IPv4"

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

        # Adjust the column sizes to fit the text
        printf "%-10s %-20s %-8s %-8s %-15s %-15s\n" "$iface" "$ip_addr" "$ip_type" "$status" "$gateway" "$assignment" >> /tmp/interface_brief.txt
    done

    dialog --title "Interface Brief" --textbox /tmp/interface_brief.txt 20 80
}

# Function to show DNS Settings with colors and better formatting
show_dns_settings() {
    # Fetch DNS servers from /etc/resolv.conf
    dns_servers=$(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}')
    
    # Separate IPv4 and IPv6 addresses
    dns_ipv4=$(echo "$dns_servers" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
    dns_ipv6=$(echo "$dns_servers" | grep -Eo '([0-9a-fA-F:]+:+)+[0-9a-fA-F]+')

    # Prepare the output for IPv4 and IPv6 addresses
    output="\n\Zb\Z4Current DNS servers:\Zn\n\n"
    
    if [ -n "$dns_ipv4" ]; then
        output+="\Zb\Z3IPv4:\Zn\n"
        for ip in $dns_ipv4; do
            output+="    \Zb\Z2$ip\Zn\n"
        done
    else
        output+="\Zb\Z3IPv4:\Zn\n    \Z1No IPv4 DNS found.\Zn\n"
    fi
    
    if [ -n "$dns_ipv6" ]; then
        output+="\n\Zb\Z3IPv6:\Zn\n"
        for ip in $dns_ipv6; do
            output+="    \Zb\Z2$ip\Zn\n"
        done
    else
        output+="\n\Zb\Z3IPv6:\Zn\n    \Z1No IPv6 DNS found.\Zn\n"
    fi
    
    # Show the dialog box with the formatted DNS settings
    dialog --colors --backtitle "Network Management Tool" --title "DNS Settings" --msgbox "$output" 12 60
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

    if [ "$ip_type" -eq 1 ]; then
        ip_addr=$(dialog --title "Set Static IP" --inputbox "Enter IP Address:" 10 50 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi

        default_subnet_mask=$(guess_subnet_mask "$ip_addr")
        subnet_mask=$(dialog --title "Set Subnet Mask" --inputbox "Enter Subnet Mask (Default: $default_subnet_mask):" 10 50 "$default_subnet_mask" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi

        gateway=$(dialog --title "Set Gateway" --inputbox "Enter Gateway (Optional):" 10 50 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return  # Cancel pressed, return to previous menu
        fi

        # Only flush and set the new IP if the entire process is confirmed
        sudo ip addr flush dev "$selected_iface"
        sudo ip addr add "$ip_addr/$subnet_mask" dev "$selected_iface"
        sudo ip route add default via "$gateway"

        # Automatically save the static configuration for persistence
        echo -e "auto $selected_iface\niface $selected_iface inet static\n    address $ip_addr\n    netmask $subnet_mask\n    gateway $gateway" | sudo tee /etc/network/interfaces.d/$selected_iface > /dev/null

        dialog --msgbox "Static IP configuration applied and saved to /etc/network/interfaces." 10 50

    else
        # DHCP configuration
        sudo ip addr flush dev "$selected_iface"
        sudo dhclient "$selected_iface"

        # Automatically save the DHCP configuration for persistence
        echo -e "auto $selected_iface\niface $selected_iface inet dhcp" | sudo tee /etc/network/interfaces.d/$selected_iface > /dev/null

        dialog --msgbox "DHCP configuration applied and saved to /etc/network/interfaces." 10 50
    fi

    show_interface_brief
}

# Function to set DNS with colors and persistence option for both NetworkManager and Netplan
set_dns() {
    dns_choice=$(dialog --colors --backtitle "Network Management Tool" --title "Set DNS" --menu "Choose DNS provider:" 15 60 5 \
        1 "\Zb\Z3Google DNS (8.8.8.8 / 8.8.4.4, 2001:4860:4860::8888 / 2001:4860:4860::8844)\Zn" \
        2 "\Zb\Z3Cloudflare DNS (1.1.1.1 / 1.0.0.1, 2606:4700:4700::1111 / 2606:4700:4700::1001)\Zn" \
        3 "\Zb\Z3Quad9 DNS (9.9.9.9 / 149.112.112.112, 2620:fe::fe / 2620:fe::9)\Zn" \
        4 "\Zb\Z3OpenDNS (208.67.222.222 / 208.67.220.220, 2620:119:35::35 / 2620:119:53::53)\Zn" \
        5 "\Zb\Z1Custom DNS\Zn" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # Cancel pressed, return to the previous menu
    fi

    # Separate IPv4 and IPv6 addresses
    case $dns_choice in
        1) dns_servers_ipv4="8.8.8.8 8.8.4.4"; dns_servers_ipv6="2001:4860:4860::8888 2001:4860:4860::8844" ;;
        2) dns_servers_ipv4="1.1.1.1 1.0.0.1"; dns_servers_ipv6="2606:4700:4700::1111 2606:4700:4700::1001" ;;
        3) dns_servers_ipv4="9.9.9.9 149.112.112.112"; dns_servers_ipv6="2620:fe::fe 2620:fe::9" ;;
        4) dns_servers_ipv4="208.67.222.222 208.67.220.220"; dns_servers_ipv6="2620:119:35::35 2620:119:53::53" ;;
        5) 
            dns_servers=$(dialog --colors --title "Custom DNS" --inputbox "Enter custom DNS servers (comma-separated):" 10 50 3>&1 1>&2 2>&3) 
            dns_servers_ipv4=$(echo "$dns_servers" | tr ',' ' ' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
            dns_servers_ipv6=$(echo "$dns_servers" | tr ',' ' ' | grep -Eo '([0-9a-fA-F:]+:+)+[0-9a-fA-F]+')
            ;;
    esac

    # Remove previous DNS settings and apply the new ones to /etc/resolv.conf
    sudo bash -c "echo '' > /etc/resolv.conf"
    sudo bash -c "echo -e 'nameserver ${dns_servers_ipv4// /\\nnameserver }' >> /etc/resolv.conf"
    sudo bash -c "echo -e 'nameserver ${dns_servers_ipv6// /\\nnameserver }' >> /etc/resolv.conf"

    # Check if Netplan is being used
    if [ -d /etc/netplan ]; then
        # Apply DNS to Netplan configuration files
        netplan_files=$(grep -l 'dhcp4: true\|dhcp6: true' /etc/netplan/*.yaml)
        if [ -n "$netplan_files" ]; then
            for file in $netplan_files; do
                # Update or add DNS settings to Netplan YAML files
                sudo sed -i '/nameservers:/d' "$file"  # Remove any existing nameserver lines
                sudo sed -i '/addresses:/d' "$file"  # Remove old DNS addresses if any
                sudo sed -i '/dhcp4: true/a \        nameservers:\n          addresses: [ '"$dns_servers_ipv4, $dns_servers_ipv6"' ]' "$file"
            done
            sudo netplan apply
        fi
    fi

    # Check if NetworkManager is being used
    if command -v nmcli &> /dev/null; then
        for iface in $(nmcli device status | grep -i connected | awk '{print $1}'); do
            nmcli con mod "$iface" ipv4.dns "$dns_servers_ipv4"
            nmcli con mod "$iface" ipv6.dns "$dns_servers_ipv6"
            nmcli con up "$iface"
        done
    fi

    # Display success message
    dialog --colors --backtitle "Network Management Tool" --title "DNS Set" --msgbox "\n\Zb\Z3DNS set and saved successfully.\Zn" 10 50
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
            --menu "\nChoose an option:\n" 15 60 6 \
            1 "\Zb\Z2Interface Brief\Zn" \
            2 "\Zb\Z2DNS Settings\Zn" \
            3 "\Zb\Z2Set IP Address\Zn" \
            4 "\Zb\Z2Set DNS\Zn" \
            5 "\Zb\Z2Set Hostname\Zn" \
            6 "\Zb\Z1Return to Main Menu\Zn" 3>&1 1>&2 2>&3)

        case $option in
            1) show_interface_brief ;;
            2) show_dns_settings ;;
            3) set_ip_address ;;
            4) set_dns ;;
            5) set_hostname ;;
            6) ./main_menu.sh; exit 0 ;;  # Return to main menu and close this script
        esac
    done
}

# Run the main configuration menu
basic_linux_network_configuration
