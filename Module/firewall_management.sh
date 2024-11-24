#!/bin/bash
trap "clear; echo 'Exiting Network Tool Management...'; exit" SIGINT
BASE_DIR=$(dirname "$(readlink -f "$0")")
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

    # Step 1: Get the table name from the user
    table=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Enter Table Name\Zn" \
        --inputbox "\n\Zb\Z3Enter table name (leave empty for default 'filter'):\Zn" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

    # Check if user canceled or input is empty, set default table to 'inet filter'
    if [ $? -ne 0 ] || [ -z "$table" ]; then
        table="filter"
    fi

    # Check if the table exists; if not, create it
    if ! sudo nft list tables | grep -q "^table inet $table"; then
        sudo nft add table inet $table
        sudo nft add chain inet $table input { type filter hook input priority 0 \; }
        sudo nft add chain inet $table output { type filter hook output priority 0 \; }
    fi

    # Step 2: Choose Chain (Input or Output)
    chain=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Choose Chain\Zn" \
        --menu "\n\Zb\Z3Select chain to apply the rule:\Zn" "$dialog_height" "$dialog_width" 2 \
        1 "Input (Incoming traffic)" \
        2 "Output (Outgoing traffic)" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then return; fi

    case $chain in
        1) chain_cmd="input" ;;
        2) chain_cmd="output" ;;
        *) return ;;  
    esac

    # Step 3: Choose Protocol
    proto=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Choose Protocol\Zn" \
        --menu "\n\Zb\Z3Select protocol:\Zn" "$dialog_height" "$dialog_width" 4 \
        1 "TCP (Transmission Control Protocol)" \
        2 "UDP (User Datagram Protocol)" \
        4 "Any (Applies to all protocols)" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then return; fi

    case $proto in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        4) protocol="ip" ;;
        *) return ;;  
    esac

    # Step 4: Get Source and Destination IP addresses
    src_ip=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Enter Source IP\Zn" \
        --inputbox "\n\Zb\Z3Enter Source IP (leave empty for any):\Zn" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return; fi
    if [ -z "$src_ip" ]; then
        src_ip=""
    else
        src_ip="ip saddr $src_ip"
    fi

    dest_ip=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Enter Destination IP\Zn" \
        --inputbox "\n\Zb\Z3Enter Destination IP (leave empty for any):\Zn" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then return; fi
    if [ -z "$dest_ip" ]; then
        dest_ip=""
    else
        dest_ip="ip daddr $dest_ip"
    fi

    # Step 5: Get the destination port (skip for Any)
    if [[ "$protocol" != "ip" ]]; then
        port=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Enter Destination Port\Zn" \
            --inputbox "\n\Zb\Z3Enter destination port (e.g., 80 for HTTP, 1000-2000 for range):\Zn" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then return; fi
        if [ -n "$port" ]; then
            port="$protocol dport $port"
        else
            port=""
        fi
    else
        port=""
    fi

    # Step 6: Choose Action (Accept, Drop, Reject)
    action=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Choose Action\Zn" \
        --menu "\n\Zb\Z3Select action for this rule:\Zn" "$dialog_height" "$dialog_width" 3 \
        1 "Accept (Allow traffic)" \
        2 "Drop (Silently discard traffic)" \
        3 "Reject (Discard traffic and send a response)" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then return; fi

    case $action in
        1) action_cmd="accept" ;;
        2) action_cmd="drop" ;;
        3) action_cmd="reject" ;;
        *) return ;;  
    esac

    # Step 7: Choose Stateful or Stateless (skip stateful for ICMP)
    if [[ "$protocol" != "ip" ]]; then
        stateless=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Stateful or Stateless\Zn" \
            --menu "\n\Zb\Z3Do you want this rule to be stateful or stateless?\Zn" "$dialog_height" "$dialog_width" 2 \
            1 "Stateful (Track connections and only allow valid ones)" \
            2 "Stateless (No connection tracking)" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then return; fi

        if [ "$stateless" -eq 1 ]; then
            # Step 8: Choose specific states for Stateful
            state_options=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Choose Connection States\Zn" \
                --checklist "\n\Zb\Z3Select states to track for this rule (use space to select):\Zn" "$dialog_height" "$dialog_width" 4 \
                1 "new" on \
                2 "established" on \
                3 "related" on \
                4 "invalid" off 3>&1 1>&2 2>&3)

            state=$(echo "$state_options" | tr -d '\"' | sed 's/1/new/g; s/2/established/g; s/3/related/g; s/4/invalid/g' | sed 's/ /,/g')

            if [ -z "$state" ]; then
                state="ct state new"
            else
                state="ct state { $state }"
            fi
        else
            state=""  # Stateless rule
        fi
    else
        state=""  # Stateless for ICMP and IP
    fi

    # Step 9: Build and Apply the Rule
    rule_components=()
    [ -n "$src_ip" ] && rule_components+=("$src_ip")
    [ -n "$dest_ip" ] && rule_components+=("$dest_ip")
    [ -n "$port" ] && rule_components+=("$port")
    [ -n "$state" ] && rule_components+=("$state")

    rule_command="sudo nft add rule inet $table $chain_cmd ${rule_components[*]} $action_cmd"
    eval $rule_command

    # Show confirmation
    show_msg "\Zb\Z3Rule added successfully:\Zn\n\nTable: $table\nChain: $chain_cmd\nConditions: ${rule_components[*]}\nAction: $action_cmd"
}



# Function to delete a rule or table using handle
delete_rule() {
    get_terminal_size
    
    # Step 1: Get the table name from the user
    table=$(dialog --inputbox "Enter table name (leave empty for default 'filter'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
    
    # Check if user canceled or input is empty, set default table to 'filter'
    if [ -z "$table" ]; then
        table="filter"
    fi

    # Check if the table exists
    if ! sudo nft list tables | grep -q "^table inet $table"; then
        dialog --msgbox "Table '$table' does not exist!" "$dialog_height" "$dialog_width"
        return
    fi

    # Step 2: Choose Chain (Input or Output)
    chain=$(dialog --title "Choose Chain" --menu "Select chain to delete the rule from:" "$dialog_height" "$dialog_width" 2 \
        1 "Input (Incoming traffic)" \
        2 "Output (Outgoing traffic)" 3>&1 1>&2 2>&3)
    
    # Check if user canceled the menu
    if [ $? -ne 0 ]; then return; fi

    case $chain in
        1) chain_cmd="input" ;;
        2) chain_cmd="output" ;;
        *) return ;;  
    esac

    # Step 3: Get the current rules with handles for the chosen table and chain
    rules=$(sudo nft -a list chain inet $table $chain_cmd 2>/dev/null | awk '/handle/')
    if [ -z "$rules" ]; then
        dialog --msgbox "No rules found in the chain '$chain_cmd' of table '$table'!" "$dialog_height" "$dialog_width"
        return
    fi

    # Step 4: Build the list of rules to display in dialog with reduced spacing
    rule_list=()
    first_handle=""
    first_rule=""

    # Process rules to get the first rule (handle of the table)
    while IFS= read -r line; do
        rule_handle=$(echo "$line" | awk '{print $NF}')  # Extract the handle of the rule
        rule_desc=$(echo "$line" | awk '{$NF=""; print $0}' | tr -s ' ')  # Remove handle and extra spaces

        if [ -z "$first_handle" ]; then
            # Store the first handle and rule description for the table itself
            first_handle="$rule_handle"
            first_rule="$rule_desc (This will delete the whole table)"
        fi

        rule_list+=("$rule_handle" "$rule_desc")  # Add description with reduced spacing
    done <<< "$rules"

    # Add the table deletion option with the first handle
    rule_list+=("$first_handle" "$first_rule")

    # Step 5: Show the rules to the user in a menu and allow them to select one for deletion
    if [ ${#rule_list[@]} -eq 0 ]; then
        dialog --msgbox "No rules available for deletion!" "$dialog_height" "$dialog_width"
        return
    fi

    rule_choice=$(dialog --menu "Select rule to delete (first option will delete the table)" "$dialog_height" "$dialog_width" 15 "${rule_list[@]}" 3>&1 1>&2 2>&3)

    # Check if user canceled
    if [ -z "$rule_choice" ]; then
        dialog --msgbox "No rule selected!" "$dialog_height" "$dialog_width"
        return
    fi

    # Step 6: Check if the first handle was selected (indicating table deletion)
    if [ "$rule_choice" == "$first_handle" ]; then
        # User chose to delete the entire table
        sudo nft delete table inet $table
        if [ $? -eq 0 ]; then
            dialog --msgbox "Table '$table' deleted successfully!" "$dialog_height" "$dialog_width"
        else
            dialog --msgbox "Failed to delete table '$table'!" "$dialog_height" "$dialog_width"
        fi
    else
        # Otherwise, delete the selected rule by its handle
        sudo nft delete rule inet $table $chain_cmd handle "$rule_choice"
        if [ $? -eq 0 ]; then
            dialog --msgbox "Rule with handle $rule_choice deleted successfully from chain '$chain_cmd' of table '$table'!" "$dialog_height" "$dialog_width"
        else
            dialog --msgbox "Failed to delete rule with handle $rule_choice!" "$dialog_height" "$dialog_width"
        fi
    fi
}



manage_nat_rules() {
    get_terminal_size 
    default_table="nat"

    while true; do
        # Main menu for managing NAT rules with colors
        nat_option=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Manage NAT Rules\Zn" \
            --menu "\n\Zb\Z3Choose an option:\Zn" "$dialog_height" "$dialog_width" 6 \
            1 "\Zb\Z2Add DNAT Rule\Zn" \
            2 "\Zb\Z2Add SNAT Rule\Zn" \
            3 "\Zb\Z2Add Masquerade Rule\Zn" \
            4 "\Zb\Z2Delete NAT Rule\Zn" \
            5 "\Zb\Z2View NAT Rules\Zn" \
            6 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then return; fi  # Return if user cancels

        case $nat_option in
            1)
                # Adding DNAT Rule
                table_name=$(dialog --inputbox "Enter table name for DNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ $? -ne 0 ]; then continue; fi  # Return to NAT menu if user cancels
                if [ -z "$table_name" ]; then
                    table_name=$default_table
                fi

                src_ip=$(dialog --inputbox "Enter source IP for DNAT (or leave empty for any):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ $? -ne 0 ]; then continue; fi  # Return to NAT menu if user cancels
                if [ -z "$src_ip" ]; then src_ip="0.0.0.0/0"; fi

                dest_ip=$(dialog --inputbox "Enter destination IP for DNAT:" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ $? -ne 0 ] || [ -z "$dest_ip" ]; then
                    dialog --colors --msgbox "\Zb\Z1Destination IP cannot be empty!\Zn" "$dialog_height" "$dialog_width"
                    continue  # Return to NAT menu if user cancels or input is empty
                fi

                dest_port=$(dialog --inputbox "Enter destination port for DNAT:" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ $? -ne 0 ] || [ -z "$dest_port" ]; then
                    dialog --colors --msgbox "\Zb\Z1Destination port cannot be empty!\Zn" "$dialog_height" "$dialog_width"
                    continue  # Return to NAT menu if user cancels or input is empty
                fi

                if ! sudo nft list tables | grep -q "$table_name"; then
                    sudo nft add table ip $table_name
                fi

                sudo nft add chain ip $table_name prerouting { type nat hook prerouting priority 0 \; }

                # Apply the DNAT rule
                sudo nft add rule ip $table_name prerouting ip saddr $src_ip tcp dport $dest_port dnat to $dest_ip:$dest_port
                if [ $? -eq 0 ]; then
                    sudo nft list table ip $table_name > /etc/nftables_$table_name.conf  # Saving the rule
                    dialog --colors --msgbox "\Zb\Z2DNAT rule added:\nTable: $table_name\nSource: $src_ip\nPort: $dest_port -> Destination: $dest_ip\Zn" "$dialog_height" "$dialog_width"
                else
                    dialog --colors --msgbox "\Zb\Z1Failed to add DNAT rule!\Zn" "$dialog_height" "$dialog_width"
                fi
                ;;
            2)
                # Adding SNAT Rule
                table_name=$(dialog --inputbox "Enter table name for SNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ $? -ne 0 ]; then continue; fi  # Return to NAT menu if user cancels
                if [ -z "$table_name" ]; then
                    table_name=$default_table
                fi

                src_ip=$(dialog --inputbox "Enter source IP for SNAT (or leave empty for any):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ $? -ne 0 ]; then continue; fi  # Return to NAT menu if user cancels
                if [ -z "$src_ip" ]; then src_ip="0.0.0.0/0"; fi

                snat_ip=$(dialog --inputbox "Enter IP for SNAT replacement:" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ $? -ne 0 ] || [ -z "$snat_ip" ]; then
                    dialog --colors --msgbox "\Zb\Z1Replacement IP cannot be empty!\Zn" "$dialog_height" "$dialog_width"
                    continue  # Return to NAT menu if user cancels or input is empty
                fi

                if ! sudo nft list tables | grep -q "$table_name"; then
                    sudo nft add table ip $table_name
                fi

                sudo nft add chain ip $table_name postrouting { type nat hook postrouting priority 100 \; }

                sudo nft add rule ip $table_name postrouting ip saddr $src_ip snat to $snat_ip
                if [ $? -eq 0 ]; then
                    sudo nft list table ip $table_name > /etc/nftables_$table_name.conf  # Saving the rule
                    dialog --colors --msgbox "\Zb\Z2SNAT rule added:\nTable: $table_name\nSource: $src_ip -> Replacement: $snat_ip\Zn" "$dialog_height" "$dialog_width"
                else
                    dialog --colors --msgbox "\Zb\Z1Failed to add SNAT rule!\Zn" "$dialog_height" "$dialog_width"
                fi
                ;;
            3)
                # Adding Masquerade Rule
                masq_type=$(dialog --menu "Select Masquerade Type" "$dialog_height" "$dialog_width" 2 \
                    1 "Normal Masquerade" \
                    2 "Masquerade with SOURCE and DESTINATION" 3>&1 1>&2 2>&3)

                if [ $? -ne 0 ]; then continue; fi  # Return to NAT menu if user cancels

                table_name=$(dialog --inputbox "Enter table name for Masquerade (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ $? -ne 0 ]; then continue; fi  # Return to NAT menu if user cancels
                if [ -z "$table_name" ]; then
                    table_name=$default_table
                fi

                # Checking if the table exists, if not create it
                if ! sudo nft list tables | grep -q "$table_name"; then
                    sudo nft add table ip $table_name
                fi

                sudo nft add chain ip $table_name postrouting { type nat hook postrouting priority 100 \; }

                if [ "$masq_type" -eq 1 ]; then
                    # Normal Masquerade Rule
                    sudo nft add rule ip $table_name postrouting masquerade
                    if [ $? -eq 0 ]; then
                        sudo nft list table ip $table_name > /etc/nftables_$table_name.conf  # Saving the rule
                        dialog --colors --msgbox "\Zb\Z2Normal Masquerade rule added to table '$table_name'.\Zn" "$dialog_height" "$dialog_width"
                    else
                        dialog --colors --msgbox "\Zb\Z1Failed to add Normal Masquerade rule!\Zn" "$dialog_height" "$dialog_width"
                    fi

                elif [ "$masq_type" -eq 2 ]; then
                    # Masquerade with Source and Destination
                    src_ip=$(dialog --inputbox "Enter Source IP (saddr) for Masquerade (leave empty for any):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                    if [ $? -ne 0 ]; then continue; fi  # Return to NAT menu if user cancels
                    if [ -z "$src_ip" ]; then
                        src_ip="0.0.0.0/0"  # Default to any source IP if empty
                    fi

                    dest_ip=$(dialog --inputbox "Enter Destination IP (daddr) for Masquerade (leave empty for any):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                    if [ $? -ne 0 ]; then continue; fi  # Return to NAT menu if user cancels
                    if [ -z "$dest_ip" ]; then
                        dest_ip="0.0.0.0/0"  # Default to any destination IP if empty
                    fi

                    sudo nft add rule ip $table_name postrouting ip saddr $src_ip ip daddr $dest_ip masquerade
                    if [ $? -eq 0 ]; then
                        sudo nft list table ip $table_name > /etc/nftables_$table_name.conf  # Saving the rule
                        dialog --colors --msgbox "\Zb\Z2Masquerade rule with SOURCE $src_ip and DESTINATION $dest_ip added to table '$table_name'.\Zn" "$dialog_height" "$dialog_width"
                    else
                        dialog --colors --msgbox "\Zb\Z1Failed to add Masquerade rule with SOURCE and DESTINATION!\Zn" "$dialog_height" "$dialog_width"
                    fi
                fi
                ;;
        4)
            # Deleting NAT Rule by Table Type (DNAT or SNAT)
            nat_delete_type=$(dialog --menu "Select NAT rule type to delete:" "$dialog_height" "$dialog_width" 3 \
                1 "Delete DNAT Rules" \
                2 "Delete SNAT Rules" \
                3 "Delete Masquerade Rule" 3>&1 1>&2 2>&3)

            if [ $? -ne 0 ]; then
                return
            fi

            if [ "$nat_delete_type" -eq 1 ]; then
                # Delete DNAT Rules (prerouting)
                table_name=$(dialog --inputbox "Enter table name for DNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ -z "$table_name" ]; then
                    table_name=$default_table
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
                # Delete SNAT Rules (postrouting)
                table_name=$(dialog --inputbox "Enter table name for SNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ -z "$table_name" ]; then
                    table_name=$default_table
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

            elif [ "$nat_delete_type" -eq 3 ]; then
                # Delete Masquerade Rule
                table_name=$(dialog --inputbox "Enter table name for Masquerade (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                if [ -z "$table_name" ]; then
                    table_name=$default_table
                fi

                rules=$(sudo nft -a list chain ip $table_name postrouting 2>/dev/null | awk '/masquerade/ && /handle/')
                if [ -z "$rules" ]; then
                    dialog --msgbox "No Masquerade rules found in table $table_name!" "$dialog_height" "$dialog_width"
                    return
                fi

                # Build the list of rules to display in dialog with reduced spacing
                rule_list=()
                while IFS= read -r line; do
                    rule_handle=$(echo "$line" | awk '{print $NF}')  # Extract the handle of the rule
                    rule_desc=$(echo "$line" | awk '{$NF=""; print $0}' | tr -s ' ')  # Remove handle and extra spaces
                    rule_list+=("$rule_handle" "$rule_desc")  # Add description with reduced spacing
                done <<< "$rules"

                rule_choice=$(dialog --menu "Select Masquerade rule to delete" "$dialog_height" "$dialog_width" 8 "${rule_list[@]}" 3>&1 1>&2 2>&3)

                if [ -z "$rule_choice" ]; then
                    dialog --msgbox "No rule selected!" "$dialog_height" "$dialog_width"
                    return
                fi

                sudo nft delete rule ip $table_name postrouting handle "$rule_choice"
                if [ $? -eq 0 ]; then
                    dialog --msgbox "Masquerade rule with handle $rule_choice deleted from $table_name!" "$dialog_height" "$dialog_width"
                else
                    dialog --msgbox "Failed to delete Masquerade rule with handle $rule_choice!" "$dialog_height" "$dialog_width"
                fi
            fi
            ;;

        5)
            # Viewing NAT Rules
            nat_view_type=$(dialog --menu "Select NAT rule type to view:" "$dialog_height" "$dialog_width" 3 \
                1 "View DNAT Rules" \
                2 "View SNAT Rules" \
                3 "View Masquerade Rules" 3>&1 1>&2 2>&3)

            if [ $? -ne 0 ]; then
                return
            fi

            if [ "$nat_view_type" -eq 1 ]; then
                # View DNAT Rules (prerouting)
                table_name=$(dialog --inputbox "Enter table name for DNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

                if [ -z "$table_name" ]; then
                    table_name=$default_table  # Use 'nat' as default table
                fi

                sudo nft list chain ip "$table_name" prerouting 2>/dev/null | grep -A 5 "dnat" | sed '/{/d' | sed '/}/d' > /tmp/dnat_rules_$table_name.txt
                if [ ! -s /tmp/dnat_rules_$table_name.txt ]; then
                    dialog --msgbox "No DNAT rules found in table '$table_name'!" "$dialog_height" "$dialog_width"
                else
                    dialog --backtitle "NAT Rules" --title "DNAT Rules in $table_name (prerouting)" --textbox /tmp/dnat_rules_$table_name.txt "$dialog_height" "$dialog_width"
                fi
                rm /tmp/dnat_rules_$table_name.txt

            elif [ "$nat_view_type" -eq 2 ]; then
                # View SNAT Rules (postrouting)
                table_name=$(dialog --inputbox "Enter table name for SNAT (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

                if [ -z "$table_name" ]; then
                    table_name=$default_table  # Use 'nat' as default table
                fi

                sudo nft list chain ip "$table_name" postrouting 2>/dev/null | grep -A 5 "snat" | sed '/{/d' | sed '/}/d' > /tmp/snat_rules_$table_name.txt
                if [ ! -s /tmp/snat_rules_$table_name.txt ]; then
                    dialog --msgbox "No SNAT rules found in table '$table_name'!" "$dialog_height" "$dialog_width"
                else
                    dialog --backtitle "NAT Rules" --title "SNAT Rules in $table_name (postrouting)" --textbox /tmp/snat_rules_$table_name.txt "$dialog_height" "$dialog_width"
                fi
                rm /tmp/snat_rules_$table_name.txt

            elif [ "$nat_view_type" -eq 3 ]; then
                # View Masquerade Rules (postrouting)
                table_name=$(dialog --inputbox "Enter table name for Masquerade (leave empty for default 'nat'):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

                if [ -z "$table_name" ]; then
                    table_name=$default_table  # Use 'nat' as default table
                fi

                sudo nft list chain ip "$table_name" postrouting 2>/dev/null | grep -A 5 "masquerade" | sed '/{/d' | sed '/}/d' > /tmp/masquerade_rules_$table_name.txt
                if [ ! -s /tmp/masquerade_rules_$table_name.txt ]; then
                    dialog --msgbox "No Masquerade rules found in table '$table_name'!" "$dialog_height" "$dialog_width"
                else
                    dialog --backtitle "NAT Rules" --title "Masquerade Rules in $table_name (postrouting)" --textbox /tmp/masquerade_rules_$table_name.txt "$dialog_height" "$dialog_width"
                fi
                rm /tmp/masquerade_rules_$table_name.txt
            fi
            ;;
        6) 
            return
            ;; 

    esac
    done
}


# 4. Function to manage ICMP rules
manage_icmp_rules() {
    get_terminal_size

    # Menu to manage ICMP rules
    icmp_action=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Manage ICMP Rules\Zn" \
        --menu "\n\Zb\Z3Choose an action:\Zn" "$dialog_height" "$dialog_width" 5 \
        1 "\Zb\Z2Add ICMP Rule\Zn" \
        2 "\Zb\Z2View ICMP Rules\Zn" \
        3 "\Zb\Z2Remove ICMP Rule\Zn" \
        4 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then return; fi

    case $icmp_action in
        1)  # Add ICMP Rule
            # Step 1: Get the source IP address
            src_ip=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Enter Source IP\Zn" \
                --inputbox "\n\Zb\Z3Enter Source IP (leave empty for any):\Zn" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then manage_icmp_rules; fi
            if [ -z "$src_ip" ]; then
                src_ip=""
            else
                src_ip="ip saddr $src_ip"
            fi

            # Step 2: Get the destination IP address
            dest_ip=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Enter Destination IP\Zn" \
                --inputbox "\n\Zb\Z3Enter Destination IP (leave empty for any):\Zn" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then manage_icmp_rules; fi
            if [ -z "$dest_ip" ]; then
                dest_ip=""
            else
                dest_ip="ip daddr $dest_ip"
            fi

            # Step 3: Choose ICMP type
            icmp_type=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Select ICMP Type\Zn" \
                --menu "\n\Zb\Z3Select ICMP Type:\Zn" "$dialog_height" "$dialog_width" 2 \
                1 "\Zb\Z2Echo Request (Ping)\Zn" \
                2 "\Zb\Z2Destination Unreachable\Zn" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then manage_icmp_rules; fi

            case $icmp_type in
                1) icmp_type_cmd="icmp type echo-request" ;;
                2) icmp_type_cmd="icmp type destination-unreachable" ;;
                *) manage_icmp_rules ;;
            esac

            # Step 4: Ask whether the rule is for input or output
            direction=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Select Direction\Zn" \
                --menu "\n\Zb\Z3Select Rule Direction (Input or Output):\Zn" "$dialog_height" "$dialog_width" 2 \
                1 "\Zb\Z2Input (Incoming Traffic)\Zn" \
                2 "\Zb\Z2Output (Outgoing Traffic)\Zn" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then manage_icmp_rules; fi

            case $direction in
                1) direction_cmd="input" ;;
                2) direction_cmd="output" ;;
                *) manage_icmp_rules ;;
            esac

            # Step 5: Choose Action (Accept or Drop)
            action=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Select Action\Zn" \
                --menu "\n\Zb\Z3Select Action for this ICMP Rule:\Zn" "$dialog_height" "$dialog_width" 2 \
                1 "\Zb\Z2Accept\Zn" \
                2 "\Zb\Z2Drop\Zn" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then manage_icmp_rules; fi

            case $action in
                1) action_cmd="accept" ;;
                2) action_cmd="drop" ;;
                *) manage_icmp_rules ;;
            esac

            # Step 6: Apply the rule
            rule_components=()
            [ -n "$src_ip" ] && rule_components+=("$src_ip")
            [ -n "$dest_ip" ] && rule_components+=("$dest_ip")
            rule_components+=("$icmp_type_cmd $action_cmd")

            # Create the nft command based on the selected direction (input or output)
            rule_command="sudo nft add rule inet filter $direction_cmd ${rule_components[*]}"
            eval $rule_command

            show_msg "\Zb\Z3ICMP rule added successfully:\Zn\n\nDirection: $direction_cmd\nConditions: ${rule_components[*]}\nAction: $action_cmd"
            manage_icmp_rules
            ;;


        2)  # View ICMP Rules
            sudo nft -a list ruleset | awk '/table/ {table=$2} /chain/ {chain=$2} /icmp/ {print table, chain, $0}' > /tmp/icmp_rules.txt
            dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4ICMP Rules\Zn" \
                --textbox /tmp/icmp_rules.txt "$dialog_height" "$dialog_width"
            manage_icmp_rules
            ;;

3)  # Remove ICMP Rule
    # Get ICMP rules with their handles from both input and output chains
    input_rules=$(sudo nft -a list chain inet filter input 2>/dev/null | awk '/icmp/ && /handle/')
    output_rules=$(sudo nft -a list chain inet filter output 2>/dev/null | awk '/icmp/ && /handle/')

    if [ -z "$input_rules" ] && [ -z "$output_rules" ]; then
        dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --msgbox "\n\Zb\Z1No ICMP rules found!\Zn" "$dialog_height" "$dialog_width"
        manage_icmp_rules
    fi

    # Build the list of rules to display in dialog (show handles and rule descriptions)
    rule_list=()

    # Add input rules to the list
    while IFS= read -r line; do
        rule_handle=$(echo "$line" | awk '{print $NF}')  # Extract the handle of the rule
        rule_desc=$(echo "$line" | awk '{$NF=""; print $0}' | tr -s ' ')  # Remove handle and extra spaces
        rule_list+=("$rule_handle" "$rule_handle - Input: $rule_desc")  # Display handle and rule for input chain
    done <<< "$input_rules"

    # Add output rules to the list
    while IFS= read -r line; do
        rule_handle=$(echo "$line" | awk '{print $NF}')  # Extract the handle of the rule
        rule_desc=$(echo "$line" | awk '{$NF=""; print $0}' | tr -s ' ')  # Remove handle and extra spaces
        rule_list+=("$rule_handle" "$rule_handle - Output: $rule_desc")  # Display handle and rule for output chain
    done <<< "$output_rules"

    # Check if there are rules to delete
    if [ ${#rule_list[@]} -eq 0 ]; then
        dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --msgbox "\n\Zb\Z1No ICMP rules found!\Zn" "$dialog_height" "$dialog_width"
        manage_icmp_rules
    fi

    # Display the rules for selection (handles and rules)
    rule_choice=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Delete ICMP Rule\Zn" \
        --menu "\n\Zb\Z3Select ICMP rule to delete:\Zn" "$dialog_height" "$dialog_width" 8 "${rule_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$rule_choice" ]; then
        dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --msgbox "\n\Zb\Z1No rule selected!\Zn" "$dialog_height" "$dialog_width"
        manage_icmp_rules
    fi

    # Determine if the selected rule is in input or output chain
    selected_rule=$(printf '%s\n' "${rule_list[@]}" | grep "$rule_choice")

    if [[ "$selected_rule" == *"Input"* ]]; then
        chain="input"
    elif [[ "$selected_rule" == *"Output"* ]]; then
        chain="output"
    else
        dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --msgbox "\n\Zb\Z1Failed to determine chain for selected rule!\Zn" "$dialog_height" "$dialog_width"
        manage_icmp_rules
    fi

    # Confirm rule deletion
    dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --yesno "Are you sure you want to delete ICMP rule with handle $rule_choice from $chain chain?" "$dialog_height" "$dialog_width"
    if [ $? -ne 0 ]; then
        manage_icmp_rules
    fi

    # Correctly delete the selected rule by its handle from the appropriate chain
    sudo nft delete rule inet filter "$chain" handle "$rule_choice"
    
    if [ $? -eq 0 ]; then
        dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --msgbox "\n\Zb\Z2ICMP rule with handle $rule_choice deleted from $chain chain!\Zn" "$dialog_height" "$dialog_width"
    else
        dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --msgbox "\n\Zb\Z1Failed to delete ICMP rule!\Zn" "$dialog_height" "$dialog_width"
    fi
    manage_icmp_rules
    ;;

        4)  # Return to previous menu
            firewall_menu
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
    get_terminal_size

    # Main menu for Port Knocking management
    option=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Port Knocking Management\Zn" \
        --menu "\n\Zb\Z3Choose an action:\Zn" 15 50 4 \
        1 "\Zb\Z2Configure Port Knocking\Zn" \
        2 "\Zb\Z2Delete Port Knocking Rules\Zn" \
        3 "\Zb\Z2View Port Knocking Rules\Zn" \
        4 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then return; fi

    case $option in
        1)
            # Get ports for knocking from the user
            ports=$(dialog --colors --backtitle "\Zb\Z4Port Knocking Setup\Zn" --title "\Zb\Z4Enter Knocking Ports\Zn" \
                --inputbox "\n\Zb\Z3Enter knocking ports (comma-separated):\Zn" 10 50 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ] || [ -z "$ports" ]; then configure_port_knocking; fi

            # Get target port
            target_port=$(dialog --colors --backtitle "\Zb\Z4Port Knocking Setup\Zn" --title "\Zb\Z4Enter Target Port\Zn" \
                --inputbox "\n\Zb\Z3Enter target port for final access:\Zn" 10 50 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ] || [ -z "$target_port" ]; then configure_port_knocking; fi

            # Get timeout for each knocking stage
            timeout=$(dialog --colors --backtitle "\Zb\Z4Port Knocking Setup\Zn" --title "\Zb\Z4Enter Timeout\Zn" \
                --inputbox "\n\Zb\Z3Enter timeout for knocking stages (in seconds):\Zn" 10 50 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then configure_port_knocking; fi
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
            configure_port_knocking
            ;;

        2)
            # لیست جداول port knocking
            tables=$(sudo nft list tables | grep 'port_knocking_' | awk '{print $3}')

            # اگر هیچ جدولی پیدا نشد
            if [ -z "$tables" ]; then
                dialog --colors --backtitle "\Zb\Z4Port Knocking Rules\Zn" --msgbox "\n\Zb\Z1No port knocking rules found!\Zn" 10 40
                configure_port_knocking
            fi

            # آماده‌سازی لیست برای dialog --menu
            menu_items=()
            for table in $tables; do
                menu_items+=("$table" "")
            done

            # نمایش منو برای انتخاب جدول
            table_to_delete=$(dialog --colors --backtitle "\Zb\Z4Delete Port Knocking Rule\Zn" --menu "\n\Zb\Z3Select Port Knocking Rule to Delete:\Zn" 15 50 10 "${menu_items[@]}" 3>&1 1>&2 2>&3)

            # بررسی لغو عملیات توسط کاربر
            if [ $? -ne 0 ]; then configure_port_knocking; fi

            # تأیید حذف جدول
            dialog --yesno "Are you sure you want to delete the port knocking rule for table '$table_to_delete'?" 10 50
            if [ $? -ne 0 ]; then
                dialog --msgbox "Deletion process cancelled by the user." 10 40
                configure_port_knocking
            fi

            # حذف جدول انتخاب شده و بررسی موفقیت عملیات
            if sudo nft delete table inet "$table_to_delete"; then
                dialog --colors --backtitle "\Zb\Z4Delete Port Knocking Rule\Zn" --msgbox "\n\Zb\Z2Port knocking rule for table '$table_to_delete' deleted successfully!\Zn" 10 50
            else
                dialog --colors --backtitle "\Zb\Z4Delete Port Knocking Rule\Zn" --msgbox "\n\Zb\Z1Failed to delete the port knocking rule for table '$table_to_delete'.\Zn" 10 50
            fi
            configure_port_knocking
            ;;

        3)
            # بخش نمایش قوانین port knocking
            tables=$(sudo nft list tables | grep 'port_knocking_' | awk '{print $3}')

            # اگر هیچ جدولی پیدا نشد
            if [ -z "$tables" ]; then
                dialog --colors --backtitle "\Zb\Z4Port Knocking Rules\Zn" --msgbox "\n\Zb\Z1No port knocking rules found!\Zn" 10 40
                configure_port_knocking
            fi

            # ایجاد یک فایل موقت برای نمایش قوانین
            temp_file=$(mktemp)
            for table in $tables; do
                echo "Rules for $table:" >> $temp_file
                sudo nft list table inet "$table" >> $temp_file
                echo -e "\n" >> $temp_file
            done

            # نمایش قوانین در فایل موقت
            dialog --colors --backtitle "\Zb\Z4Port Knocking Rules\Zn" --title "\Zb\Z4Current Port Knocking Rules\Zn" --textbox "$temp_file" 20 80

            # حذف فایل موقت بعد از نمایش
            rm -f "$temp_file"
            configure_port_knocking
            ;;

        4)
            clear
            break
            ;;   
    esac
}


# 7. Backup and Restore firewall rules
backup_and_restore_rules() {
    get_terminal_size

    # Main menu for Backup and Restore
    option=$(dialog --colors --backtitle "\Zb\Z4NFTables Firewall Management\Zn" --title "\Zb\Z4Backup & Restore Rules\Zn" \
        --menu "\n\Zb\Z3Choose an action:\Zn" "$dialog_height" "$dialog_width" 3 \
        1 "\Zb\Z2Backup Rules\Zn" \
        2 "\Zb\Z2Restore Rules\Zn" \
        3 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then backup_and_restore_rules; fi  # If user cancels, return to the start

    case $option in
        1)  # Backup firewall rules
            sudo nft list ruleset > /etc/nftables-backup.conf
            if [ $? -eq 0 ]; then
                show_msg "\Zb\Z2Firewall rules successfully backed up to /etc/nftables-backup.conf.\Zn"
            else
                show_msg "\Zb\Z1Error: Failed to backup firewall rules.\Zn"
            fi
            backup_and_restore_rules  # Return to the menu after completion
            ;;
        2)  # Restore firewall rules
            if [ ! -f /etc/nftables-backup.conf ]; then
                show_msg "\Zb\Z1Error: Backup file /etc/nftables-backup.conf not found!\Zn"
            else
                sudo nft -f /etc/nftables-backup.conf
                if [ $? -eq 0 ]; then
                    show_msg "\Zb\Z2Firewall rules successfully restored from /etc/nftables-backup.conf.\Zn"
                else
                    show_msg "\Zb\Z1Error: Failed to restore firewall rules.\Zn"
                fi
            fi
            backup_and_restore_rules  # Return to the menu after completion
            ;;
        3)
            return  # Go back to the previous menu
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
            2 "\Zb\Z2Manage Stateful/Stateless Rules\Zn" \
            3 "\Zb\Z2Manage NAT Rules\Zn" \
            4 "\Zb\Z2Manage ICMP Rules\Zn" \
            5 "\Zb\Z2Configure Port Knocking\Zn" \
            6 "\Zb\Z3Show Firewall Status\Zn" \
            7 "\Zb\Z3Backup & Restore Rules\Zn" \
            8 "\Zb\Z3Save Rules Across Reboot\Zn" \
            9 "\Zb\Z3Reset & Clear Firewall\Zn" \
            10 "\Zb\Z1Return to Main Menu\Zn" 3>&1 1>&2 2>&3)

        case $option in
            1) show_firewall_rules ;;
            2)  # Submenu for Stateful/Stateless Rules
                while true; do
                    sub_option=$(dialog --colors --backtitle "$TITLE" --title "\Zb\Z4Stateful/Stateless Rule Management\Zn" \
                        --menu "\nChoose an option:" "$dialog_height" "$dialog_width" 6 \
                        1 "\Zb\Z2Add Stateful/Stateless Rule\Zn" \
                        2 "\Zb\Z2Delete Stateful/Stateless Rule\Zn" \
                        3 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

                    case $sub_option in
                        1) add_stateful_or_stateless_rule ;;
                        2) delete_rule ;;
                        3) break ;;  # Return to the main firewall menu
                    esac
                done
                ;;
            3) manage_nat_rules ;;
            4) manage_icmp_rules ;;
            5) configure_port_knocking ;;
            6) show_firewall_status ;;
            7) backup_and_restore_rules ;;
            8) save_rules ;;
            9) reset_firewall ;;
            10) clear;bash $BASE_DIR/../net-tool.sh; exit 0 ;;  # Return to main menu and close this script
        esac
    done
}


# Run the firewall menu
firewall_menu
