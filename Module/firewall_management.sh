#!/bin/bash
TITLE="NFTables Firewall Management"
# Function to dynamically get terminal size
get_terminal_size() {
    term_height=$(tput lines)
    term_width=$(tput cols)
    dialog_height=$((term_height - 5))
    dialog_width=$((term_width - 10))
    if [ "$dialog_height" -lt 15 ]; then dialog_height=15; fi
    if [ "$dialog_width" -lt 50 ]; then dialog_width=50; fi
}
# Function to display a message with colors
show_msg() {
        get_terminal_size
    dialog --colors --backtitle "$TITLE" --msgbox "$1" "$dialog_height" "$dialog_width"
}

# 1. Function to show current firewall rules
show_firewall_rules() {
    get_terminal_size
    temp_file=$(mktemp)  # Create a temporary file
    sudo nft list ruleset > "$temp_file"  # Save the output of nft list ruleset to the temp file  
    # Display the content of the temp file in a dialog box
    dialog --backtitle "$TITLE" --title "Current Firewall Rules" --textbox "$temp_file" "$dialog_height" "$dialog_width"

    # Remove the temporary file after use
    rm -f "$temp_file"
}

# 2. Function to add a stateful or stateless firewall rule with chain selection
add_stateful_or_stateless_rule() {
    get_terminal_size
    # Step 1: Choose Chain (Input or Output)
    chain=$(dialog --title "Choose Chain" --menu "Select chain to apply the rule:" "$dialog_height" "$dialog_width" 2 \
        1 "Input (Incoming traffic)" \
        2 "Output (Outgoing traffic)" 3>&1 1>&2 2>&3)

    case $chain in
        1) chain_cmd="input" ;;
        2) chain_cmd="output" ;;
        *) return ;;  
    esac

    # Step 2: Choose Protocol
    proto=$(dialog --title "Choose Protocol" --menu "Select protocol:" "$dialog_height" "$dialog_width" 4 \
        1 "TCP (Transmission Control Protocol)" \
        2 "UDP (User Datagram Protocol)" \
        3 "ICMP (Internet Control Message Protocol)" \
        4 "Any (Applies to all protocols)" 3>&1 1>&2 2>&3)

    case $proto in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="icmp" ;;
        4) protocol="ip" ;;
        *) return ;;  
    esac

    # Step 3: Get the destination port (skip for ICMP and Any)
    if [[ "$protocol" != "icmp" && "$protocol" != "ip" ]]; then
        port=$(dialog --inputbox "Enter destination port (e.g., 80 for HTTP, 1000-2000 for range):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
        if [ -z "$port" ]; then return; fi  # Cancel if no input
    else
        port=""
    fi

    # Step 4: Choose Action (Accept, Drop, Reject)
    action=$(dialog --title "Choose Action" --menu "Select action for this rule:" "$dialog_height" "$dialog_width" 3 \
        1 "Accept (Allow traffic)" \
        2 "Drop (Silently discard traffic)" \
        3 "Reject (Discard traffic and send a response)" 3>&1 1>&2 2>&3)

    case $action in
        1) action_cmd="accept" ;;
        2) action_cmd="drop" ;;
        3) action_cmd="reject" ;;
        *) return ;;  # Exit if canceled
    esac

    # Step 5: Choose Stateful or Stateless
    stateless=$(dialog --title "Stateful or Stateless" --menu "Do you want this rule to be stateful or stateless?" "$dialog_height" "$dialog_width" 2 \
        1 "Stateful (Track connections and only allow valid ones)" \
        2 "Stateless (No connection tracking)" 3>&1 1>&2 2>&3)

    if [ "$stateless" -eq 1 ]; then
        # Step 6: Choose specific states for Stateful
        state_options=$(dialog --checklist "Select states to track for this rule (use space to select):" "$dialog_height" "$dialog_width" 4 \
            1 "new" on \
            2 "established" on \
            3 "related" on \
            4 "invalid" off 3>&1 1>&2 2>&3)

        # Convert the numeric output of the checklist to their corresponding state names
        state=$(echo "$state_options" | tr -d '\"' | sed 's/1/new/g; s/2/established/g; s/3/related/g; s/4/invalid/g' | sed 's/ /,/g')

        # If no states were selected, default to 'new'
        if [ -z "$state" ]; then
            state="ct state new"
        else
            state="ct state $state"
        fi
    else
        state=""  # Stateless rule
    fi

    # Step 7: Build and Apply the Rule
    if [[ -n "$port" ]]; then
        # Handling multiple ports or port range
        if [[ "$port" == *","* || "$port" == *"-"* ]]; then
            # Multi-port or range
            sudo nft add rule inet filter $chain_cmd $protocol dport { $port } $state $action_cmd
        else
            # Single port
            sudo nft add rule inet filter $chain_cmd $protocol dport $port $state $action_cmd
        fi

        show_msg "\Zb\Z3Rule added:\Zn\nChain: $chain_cmd\nProtocol: $protocol\nPort(s): $port\nAction: $action_cmd\nState: $([ -z "$state" ] && echo 'Stateless' || echo "$state")"
    else
        # No port (for ICMP/Any)
        sudo nft add rule inet filter $chain_cmd $protocol $state $action_cmd
        show_msg "\Zb\Z3Rule added:\Zn\nChain: $chain_cmd\nProtocol: $protocol\nAction: $action_cmd\nState: $([ -z "$state" ] && echo 'Stateless' || echo "$state")"
    fi
}
manage_nat_rules() {
    get_terminal_size 
    default_table="nat"

    nat_option=$(dialog --colors --menu  "Manage NAT Rules" "$dialog_height" "$dialog_width" 4 \
        1 "\Zb\Z2Add DNAT Rule\Zn" \
        2 "\Zb\Z2Add SNAT Rule\Zn" \
        3 "\Zb\Z2Delete NAT Rule\Zn" \
        4 "\ZbView NAT Rules\Zn" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return
    fi

    case $nat_option in
        1)
            # Adding DNAT Rule
            table_name=$(dialog --inputbox "Enter table name for DNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ -z "$table_name" ]; then
                table_name=$default_table
            fi

            src_ip=$(dialog --inputbox "Enter source IP for DNAT (or leave empty for any):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ -z "$src_ip" ];then src_ip="0.0.0.0/0"; fi

            dest_ip=$(dialog --inputbox "Enter destination IP for DNAT:" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ -z "$dest_ip" ];then
                dialog --msgbox "Destination IP cannot be empty!" "$dialog_height" "$dialog_width"
                return
            fi

            dest_port=$(dialog --inputbox "Enter destination port for DNAT:" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ -z "$dest_port" ];then
                dialog --msgbox "Destination port cannot be empty!" "$dialog_height" "$dialog_width"
                return
            fi

            if ! sudo nft list tables | grep -q "$table_name"; then
                sudo nft add table ip $table_name
            fi

            sudo nft add chain ip $table_name prerouting { type nat hook prerouting priority 0 \; }

            # Apply the DNAT rule
            sudo nft add rule ip $table_name prerouting ip saddr $src_ip tcp dport $dest_port dnat to $dest_ip:$dest_port
            if [ $? -eq 0 ];then
                sudo nft list table ip $table_name > /etc/nftables_$table_name.conf  # Saving the rule
                dialog --msgbox "DNAT rule added:\nTable: $table_name\nSource: $src_ip\nPort: $dest_port -> Destination: $dest_ip" "$dialog_height" "$dialog_width"
            else
                dialog --msgbox "Failed to add DNAT rule!" "$dialog_height" "$dialog_width"
            fi
            ;;

        2)
            # Adding SNAT Rule
            table_name=$(dialog --inputbox "Enter table name for SNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ -z "$table_name" ]; then
                table_name=$default_table
            fi

            src_ip=$(dialog --inputbox "Enter source IP for SNAT (or leave empty for any):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ -z "$src_ip" ];then src_ip="0.0.0.0/0"; fi

            snat_ip=$(dialog --inputbox "Enter IP for SNAT replacement:" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ -z "$snat_ip" ];then
                dialog --msgbox "Replacement IP cannot be empty!" "$dialog_height" "$dialog_width"
                return
            fi

            if ! sudo nft list tables | grep -q "$table_name"; then
                sudo nft add table ip $table_name
            fi

            sudo nft add chain ip $table_name postrouting { type nat hook postrouting priority 100 \; }

            sudo nft add rule ip $table_name postrouting ip saddr $src_ip snat to $snat_ip
            if [ $? -eq 0 ];then
                sudo nft list table ip $table_name > /etc/nftables_$table_name.conf  # Saving the rule
                dialog --msgbox "SNAT rule added:\nTable: $table_name\nSource: $src_ip -> Replacement: $snat_ip" "$dialog_height" "$dialog_width"
            else
                dialog --msgbox "Failed to add SNAT rule!" "$dialog_height" "$dialog_width"
            fi
            ;;
    3)
    # Deleting NAT Rule by Table Type (DNAT or SNAT)
    nat_delete_type=$(dialog --menu "Select NAT rule type to delete:" "$dialog_height" "$dialog_width" 2 \
        1 "Delete DNAT Rules" \
        2 "Delete SNAT Rules" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return
    fi

    if [ "$nat_delete_type" -eq 1 ]; then
        # Delete DNAT Rules
        table_name=$(dialog --inputbox "Enter table name for DNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
        if [ -z "$table_name" ]; then
            table_name=$default_table  # Use 'nat' as default table if empty
        fi

        # Get DNAT rules with their handles from the table
        rules=$(sudo nft -a list chain ip $table_name prerouting 2>/dev/null | awk '/dnat/ && /handle/')
        if [ -z "$rules" ]; then
            dialog --msgbox "No DNAT rules found in table $table_name!" "$dialog_height" "$dialog_width"
            return
        fi

        # Build the list of rules to display in dialog with reduced spacing
        rule_list=()
        while IFS= read -r line; do
            rule_handle=$(echo "$line" | awk '{print $NF}')  # Extract the handle of the rule
            rule_desc=$(echo "$line" | awk '{$NF=""; print $0}' | tr -s ' ')  # Remove handle and extra spaces
            rule_list+=("$rule_handle" "$rule_desc")  # Add description with reduced spacing
        done <<< "$rules"

        get_terminal_size
        rule_choice=$(dialog --menu "Select DNAT rule to delete" "$dialog_height" "$dialog_width" 8 "${rule_list[@]}" 3>&1 1>&2 2>&3)

        if [ -z "$rule_choice" ]; then
            dialog --msgbox "No rule selected!" "$dialog_height" "$dialog_width"
            return
        fi

        # Correctly delete the selected rule by its handle from prerouting chain
        sudo nft delete rule ip $table_name prerouting handle "$rule_choice"
        if [ $? -eq 0 ]; then
            dialog --msgbox "DNAT rule with handle $rule_choice deleted from $table_name!" "$dialog_height" "$dialog_width"
        else
            dialog --msgbox "Failed to delete DNAT rule with handle $rule_choice!" "$dialog_height" "$dialog_width"
        fi

    elif [ "$nat_delete_type" -eq 2 ]; then
        # Delete SNAT Rules
        table_name=$(dialog --inputbox "Enter table name for SNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
        if [ -z "$table_name" ]; then
            table_name=$default_table  # Use 'nat' as default table if empty
        fi

        # Get SNAT rules with their handles from the table
        rules=$(sudo nft -a list chain ip $table_name postrouting 2>/dev/null | awk '/snat/ && /handle/')
        if [ -z "$rules" ]; then
            dialog --msgbox "No SNAT rules found in table $table_name!" "$dialog_height" "$dialog_width"
            return
        fi

        # Build the list of rules to display in dialog with reduced spacing
        rule_list=()
        while IFS= read -r line; do
            rule_handle=$(echo "$line" | awk '{print $NF}')  # Extract the handle of the rule
            rule_desc=$(echo "$line" | awk '{$NF=""; print $0}' | tr -s ' ')  # Remove handle and extra spaces
            rule_list+=("$rule_handle" "$rule_desc")  # Add description with reduced spacing
        done <<< "$rules"



        rule_choice=$(dialog --menu "Select SNAT rule to delete" "$dialog_height" "$dialog_width" 8 "${rule_list[@]}" 3>&1 1>&2 2>&3)

        if [ -z "$rule_choice" ]; then
            dialog --msgbox "No rule selected!" "$dialog_height" "$dialog_width"
            return
        fi

        # Correctly delete the selected rule by its handle from postrouting chain
        sudo nft delete rule ip $table_name postrouting handle "$rule_choice"
        if [ $? -eq 0 ]; then
            dialog --msgbox "SNAT rule with handle $rule_choice deleted from $table_name!" "$dialog_height" "$dialog_width"
        else
            dialog --msgbox "Failed to delete SNAT rule with handle $rule_choice!" "$dialog_height" "$dialog_width"
        fi
    fi
    ;;


        4)
            nat_view_type=$(dialog --menu "Select NAT rule type to view:" "$dialog_height" "$dialog_width" 2 \
                1 "View DNAT Rules" \
                2 "View SNAT Rules" 3>&1 1>&2 2>&3)

            if [ $? -ne 0 ]; then
                return
            fi

            if [ "$nat_view_type" -eq 1 ]; then
                # View DNAT Rules (prerouting) based on table
                table_name=$(dialog --inputbox "Enter table name for DNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

                if [ -z "$table_name" ];then
                    table_name=$default_table  # Use 'nat' as default table
                fi

                sudo nft list chain ip "$table_name" prerouting 2>/dev/null | grep -A 5 "dnat" | sed '/{/d' | sed '/}/d' > /tmp/dnat_rules_$table_name.txt
                if [ ! -s /tmp/dnat_rules_$table_name.txt ];then
                    dialog --msgbox "No DNAT rules found in table '$table_name'!" "$dialog_height" "$dialog_width"
                else
                    dialog --backtitle "NAT Rules" --title "DNAT Rules in $table_name (prerouting)" --textbox /tmp/dnat_rules_$table_name.txt "$dialog_height" "$dialog_width"
                fi
                rm /tmp/dnat_rules_$table_name.txt

            elif [ "$nat_view_type" -eq 2 ]; then
                # View SNAT Rules (postrouting) based on table
                table_name=$(dialog --inputbox "Enter table name for SNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

                if [ -z "$table_name" ]; then
                    table_name=$default_table  # Use 'nat' as default table
                fi

                sudo nft list chain ip "$table_name" postrouting 2>/dev/null | grep -A 5 "snat" | sed '/{/d' | sed '/}/d' > /tmp/snat_rules_$table_name.txt
                if [ ! -s /tmp/snat_rules_$table_name.txt ];then
                    dialog --msgbox "No SNAT rules found in table '$table_name'!" "$dialog_height" "$dialog_width"
                else
                    dialog --backtitle "NAT Rules" --title "SNAT Rules in $table_name (postrouting)" --textbox /tmp/snat_rules_$table_name.txt "$dialog_height" "$dialog_width"
                fi
                rm /tmp/snat_rules_$table_name.txt
            fi
            ;;
    esac
}

# 4. Function to manage ICMP rules
manage_icmp_rules() {
    get_terminal_size
    icmp_action=$(dialog --menu "Manage ICMP Rules" "$dialog_height" "$dialog_width" 3 \
        1 "Allow Ping" \
        2 "Block Ping" \
        3 "View ICMP Rules" 3>&1 1>&2 2>&3)

    case $icmp_action in
        1)
            sudo nft add rule inet filter input icmp type echo-request accept
            show_msg "\Zb\Z3ICMP echo-request (ping) allowed.\Zn"
            ;;
        2)
            sudo nft add rule inet filter input icmp type echo-request drop
            show_msg "\Zb\Z3ICMP echo-request (ping) blocked.\Zn"
            ;;
        3)
            sudo nft list ruleset | grep icmp > /tmp/icmp_rules.txt
            dialog --backtitle "$TITLE" --title "ICMP Rules" --textbox /tmp/icmp_rules.txt "$dialog_height" "$dialog_width"
            ;;
    esac
}

# 5. Function to show firewall status and enable/disable it
show_firewall_status() {
    get_terminal_size
    status=$(sudo systemctl is-active nftables)
    
    if [ "$status" == "active" ]; then
        action=$(dialog --colors --backtitle "$TITLE" --title "Firewall Status" \
            --menu "\n\Zb\Z3Firewall is currently: \Z1\Zb\Z3Active\Zn\nChoose an action:" "$dialog_height" "$dialog_width" 2 \
            1 "\Zb\Z1Stop Firewall (Disable)\Zn" \
            2 "\Zb\Z2Back to Menu\Zn" 3>&1 1>&2 2>&3)
    else
        action=$(dialog --colors --backtitle "$TITLE" --title "Firewall Status" \
            --menu "\n\Zb\Z3Firewall is currently: \Z1\Zb\Z1Inactive\Zn\nChoose an action:" "$dialog_height" "$dialog_width" 2 \
            1 "\Zb\Z1Start Firewall (Enable)\Zn" \
            2 "\Zb\Z2Back to Menu\Zn" 3>&1 1>&2 2>&3)
    fi

    case $action in
        1)
            if [ "$status" == "active" ]; then
                sudo systemctl stop nftables
                dialog --colors --backtitle "$TITLE" --msgbox "\n\Zb\Z1Firewall has been stopped (disabled).\Zn" "$dialog_height" "$dialog_width"
            else
                sudo systemctl start nftables
                dialog --colors --backtitle "$TITLE" --msgbox "\n\Zb\Z2Firewall has been started (enabled).\Zn" "$dialog_height" "$dialog_width"
            fi
            ;;
        2) return ;;
    esac
}

# 6. Function to configure Port Knocking
configure_port_knocking() {
    option=$(dialog --title "Port Knocking" --menu "Choose an action:" 15 50 3 \
        1 "Configure Port Knocking" \
        2 "Delete Port Knocking Rules" \
        3 "View Port Knocking Rules" \
        4 "Exit" 3>&1 1>&2 2>&3)

    case $option in
        1)
                # Get ports for knocking from the user
                ports=$(dialog --inputbox "Enter knocking ports (comma-separated):" 10 50 3>&1 1>&2 2>&3)
                if [ -z "$ports" ]; then return; fi

                # Get target port
                target_port=$(dialog --inputbox "Enter target port for final access:" 10 50 3>&1 1>&2 2>&3)
                if [ -z "$target_port" ]; then return; fi

                # Get timeout for each knocking stage
                timeout=$(dialog --inputbox "Enter timeout for knocking stages (in seconds):" 10 50 3>&1 1>&2 2>&3)
                if [ -z "$timeout" ]; then timeout=40; fi  # Default timeout is 40 seconds if not provided

                # Generate unique table name based on target port
                table_name="port_knocking_$target_port"

                # Create the port_knocking table and stages for the specific target port
                sudo nft add table inet $table_name
                sudo nft add set inet $table_name allowed_clients { type ipv4_addr\; timeout 10m\; }
                
                IFS=',' read -r -a port_array <<< "$ports"
                for i in "${!port_array[@]}"; do
                    sudo nft add set inet $table_name stage_$i { type ipv4_addr\; timeout ${timeout}s\; }
                done

                # Create the input chain with drop policy
                sudo nft add chain inet $table_name input { type filter hook input priority 0\; policy drop\; }

                # Add port knocking rules for each stage
                for i in "${!port_array[@]}"; do
                    if [ $i -eq 0 ]; then
                        sudo nft add rule inet $table_name input tcp dport ${port_array[$i]} ct state new add @stage_$i { ip saddr }
                    else
                        prev=$((i-1))
                        sudo nft add rule inet $table_name input ip saddr @stage_$prev tcp dport ${port_array[$i]} ct state new add @stage_$i { ip saddr }
                    fi
                done

                # Add final rule to allow access to the target port after all stages
                sudo nft add rule inet $table_name input ip saddr @stage_$((i)) tcp dport $target_port accept

                # Save the configuration
                sudo nft list table inet $table_name > /etc/nftables.conf

                show_msg "\Zb\Z3Port knocking configured for target port $target_port with knocking ports: $ports\Zn"
                ;;

        2)
    # لیست جداول port knocking
    tables=$(sudo nft list tables | grep 'port_knocking_' | awk '{print $3}')

    # اگر هیچ جدولی پیدا نشد
    if [ -z "$tables" ]; then
        dialog --msgbox "No port knocking rules found!" 10 40
        return
    fi

    # آماده‌سازی لیست برای dialog --menu
    menu_items=()
    for table in $tables; do
        menu_items+=("$table" "")
    done

    # نمایش منو برای انتخاب جدول
    table_to_delete=$(dialog --menu "Select Port Knocking Rule to Delete" 15 50 10 "${menu_items[@]}" 3>&1 1>&2 2>&3)

    # بررسی لغو عملیات توسط کاربر
    if [ $? -ne 0 ]; then
        dialog --msgbox "Operation cancelled by the user." 10 40
        return
    fi

    # تأیید حذف جدول
    dialog --yesno "Are you sure you want to delete the port knocking rule for table '$table_to_delete'?" 10 50
    if [ $? -ne 0 ]; then
        dialog --msgbox "Deletion process cancelled by the user." 10 40
        return
    fi

    # حذف جدول انتخاب شده و بررسی موفقیت عملیات
    if sudo nft delete table inet "$table_to_delete"; then
        dialog --msgbox "Port knocking rule for table '$table_to_delete' deleted successfully!" 10 50
    else
        dialog --msgbox "Failed to delete the port knocking rule for table '$table_to_delete'." 10 50
    fi
    ;;
        3)
            # بخش نمایش قوانین port knocking
            tables=$(sudo nft list tables | grep 'port_knocking_' | awk '{print $3}')

            # اگر هیچ جدولی پیدا نشد
            if [ -z "$tables" ]; then
                dialog --msgbox "No port knocking rules found!" 10 40
                return
            fi

            # ایجاد یک فایل موقت برای نمایش قوانین
            temp_file=$(mktemp)
            for table in $tables; do
                echo "Rules for $table:" >> $temp_file
                sudo nft list table inet "$table" >> $temp_file
                echo -e "\n" >> $temp_file
            done

            # نمایش قوانین در فایل موقت
            dialog --backtitle "Port Knocking Rules" --title "Current Port Knocking Rules" --textbox "$temp_file" 20 80

            # حذف فایل موقت بعد از نمایش
            rm -f "$temp_file"
            ;;

        4)
            clear
            exit 0
            ;;   
    esac
}


# 7. Backup and Restore firewall rules
backup_and_restore_rules() {
    get_terminal_size
    option=$(dialog --menu "Backup & Restore" "$dialog_height" "$dialog_width" 2 \
        1 "Backup Rules" \
        2 "Restore Rules" 3>&1 1>&2 2>&3)

    case $option in
        1)
            sudo nft list ruleset > /etc/nftables-backup.conf
            show_msg "\Zb\Z3Firewall rules backed up to /etc/nftables-backup.conf.\Zn"
            ;;
        2)
            sudo nft -f /etc/nftables-backup.conf
            show_msg "\Zb\Z3Firewall rules restored from /etc/nftables-backup.conf.\Zn"
            ;;
    esac
}

# 8. Save firewall rules across reboots
save_rules() {
    sudo nft list ruleset > /etc/nftables.conf
    sudo systemctl enable nftables
    show_msg "\Zb\Z3Firewall rules saved and will persist after reboot.\Zn"
}

# 9. Function to reset and clear firewall rules
reset_firewall() {
    get_terminal_size
    # Show confirmation dialog
    dialog --colors --backtitle "$TITLE" --title "Reset Firewall" \
        --yesno "\n\Zb\Z1WARNING:\Zn This will remove all current firewall rules and reset the firewall configuration.\n\nAre you sure you want to continue?" "$dialog_height" "$dialog_width"
    
    # Check user's response (yes = 0, no = 1, cancel = 255)
    response=$?
    if [ "$response" -eq 0 ]; then
        # User pressed Yes, proceed with the reset
        # Clear all nftables rules
        sudo nft flush ruleset

        # Optional: Remove custom tables (filter, nat, etc.)
        sudo nft delete table inet filter
        sudo nft delete table ip nat

        # Reset default tables and chains
        sudo nft add table inet filter
        sudo nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }
        sudo nft add chain inet filter forward { type filter hook forward priority 0 \; policy accept \; }
        sudo nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }

        # Optional: Reset NAT table if needed
        sudo nft add table ip nat
        sudo nft add chain ip nat prerouting { type nat hook prerouting priority 0 \; policy accept \; }
        sudo nft add chain ip nat postrouting { type nat hook postrouting priority 0 \; policy accept \; }

        # Show confirmation message
        dialog --colors --backtitle "$TITLE" --title "Firewall Reset" --msgbox "\n\Zb\Z3Firewall rules have been reset and cleared.\Zn" "$dialog_height" "$dialog_width"
    elif [ "$response" -eq 1 ]; then
        # User pressed No, do not reset and return to the main menu
        dialog --colors --backtitle "$TITLE" --title "Reset Cancelled" --msgbox "\n\Zb\Z3Firewall reset operation was cancelled.\Zn" "$dialog_height" "$dialog_width"
    fi
}

# Main menu for firewall management
firewall_menu() {
    get_terminal_size
    while true; do
        option=$(dialog --colors --backtitle "$TITLE" --title "\Zb\Z4NFTables Firewall Management\Zn" \
            --menu "\nChoose an option:" "$dialog_height" "$dialog_width" 8 \
            1 "\Zb\Z2Show Current Rules\Zn" \
            2 "\Zb\Z2Add Stateful/Stateless Rule\Zn" \
            3 "\Zb\Z2Manage NAT Rules\Zn" \
            4 "\Zb\Z2Manage ICMP Rules\Zn" \
            5 "\Zb\Z2Show Firewall Status\Zn" \
            6 "\Zb\Z2Configure Port Knocking\Zn" \
            7 "\Zb\Z2Backup & Restore Rules\Zn" \
            8 "\Zb\Z2Save Rules Across Reboot\Zn" \
            9 "\Zb\Z2Reset & Clear Firewall\Zn" \
            10 "\Zb\Z1Return to Main Menu\Zn" 3>&1 1>&2 2>&3)

        case $option in
            1) show_firewall_rules ;;
            2) add_stateful_or_stateless_rule ;;
            3) manage_nat_rules ;;
            4) manage_icmp_rules ;;
            5) show_firewall_status ;;
            6) configure_port_knocking ;;
            7) backup_and_restore_rules ;;
            8) save_rules ;;
            9) reset_firewall ;;
            10) ./main_menu.sh; exit 0 ;;  # Return to main menu and close this script
        esac
    done
}

# Run the firewall menu
firewall_menu
