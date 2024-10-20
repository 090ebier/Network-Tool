#!/bin/bash
trap "clear; echo 'Exiting Network Tool Management...'; exit" SIGINT
BASE_DIR=$(dirname "$(readlink -f "$0")")
TITLE="Open vSwitch Management"

# Function to dynamically get terminal size
get_terminal_size() {
    term_height=$(tput lines)
    term_width=$(tput cols)
    dialog_height=$((term_height - 5))
    dialog_width=$((term_width - 10))
    if [ "$dialog_height" -lt 15 ]; then dialog_height=15; fi
    if [ "$dialog_width" -lt 50 ]; then dialog_width=50; fi
}

function show_msg() {
    dialog --msgbox "$1" 10 40
}



# 1. Add/Delete/View Bridges
manage_bridges() {
    get_terminal_size
    # منوی مدیریت بریج‌ها
    action=$(dialog --colors --backtitle "\Zb\Z4OVS Bridge Management\Zn" --title "\Zb\Z3Manage OVS Bridges\Zn" \
        --menu "\n\Zb\Z3Choose an action:\Zn" "$dialog_height" "$dialog_width" 5 \
        1 "\Zb\Z2Add Bridge\Zn" \
        2 "\Zb\Z2Delete Bridge\Zn" \
        3 "\Zb\Z2View Current Bridges\Zn" \
        4 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then return; fi  # Return if cancel or error

    case $action in
        1)
            # اضافه کردن بریج جدید
            bridge_name=$(dialog --inputbox "Enter bridge name to add (alphanumeric, hyphens or underscores, max 16 chars):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then return; fi  # Cancel pressed, return to menu

            if [[ ! "$bridge_name" =~ ^[a-zA-Z0-9_-]{1,16}$ ]]; then
                show_msg "Bridge name is invalid!\nUse only alphanumeric characters, hyphens, or underscores, and no more than 16 characters."
                return
            fi

            # بررسی موفقیت اجرای دستور اضافه کردن بریج
            if sudo ovs-vsctl add-br "$bridge_name"; then
                show_msg "Bridge $bridge_name added successfully."
            else
                show_msg "Failed to add bridge $bridge_name. Please check OVS configuration."
            fi
            ;;

        2)
            # نمایش لیست بریج‌ها برای حذف
            current_bridges=$(sudo ovs-vsctl list-br)
            if [ -z "$current_bridges" ]; then
                dialog --msgbox "No bridges currently exist." "$dialog_height" "$dialog_width"
                return
            fi

            # انتخاب بریج برای حذف
            bridge_to_delete=$(dialog --menu "Select a bridge to delete" "$dialog_height" "$dialog_width" 10 $(echo "$current_bridges" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then return; fi  # Cancel pressed, return to menu

            # اگر بریجی انتخاب شد، سوال برای تایید حذف
            if [ -n "$bridge_to_delete" ]; then
                selected_bridge=$(echo "$current_bridges" | sed -n "${bridge_to_delete}p")
                dialog --yesno "Are you sure you want to delete the bridge: $selected_bridge?" "$dialog_height" "$dialog_width"
                response=$?
                if [ $response -eq 0 ]; then
                    sudo ovs-vsctl del-br "$selected_bridge"
                    dialog --msgbox "Bridge $selected_bridge deleted successfully." "$dialog_height" "$dialog_width"
                else
                    dialog --msgbox "Bridge deletion canceled." "$dialog_height" "$dialog_width"
                fi
            else
                dialog --msgbox "No bridge selected for deletion." "$dialog_height" "$dialog_width"
            fi
            ;;

        3)
            # نمایش بریج‌های موجود
            current_bridges=$(sudo ovs-vsctl list-br)
            if [ -z "$current_bridges" ]; then
                dialog --msgbox "No bridges currently exist." "$dialog_height" "$dialog_width"
            else
                # نمایش بریج‌ها به صورت جدولی به همراه VLANها
                output="| Bridge Name   | Status   | Ports | VLANs   |\n"
                output+="|---------------|----------|-------|---------|\n"
                for bridge in $current_bridges; do
                    status=$(sudo ovs-vsctl br-exists "$bridge" && echo "Active" || echo "Inactive")
                    port_count=$(sudo ovs-vsctl list-ports "$bridge" | wc -l)

                    # دریافت اطلاعات VLAN برای هر بریج
                    vlans=$(sudo ovs-vsctl list port | grep -A 10 "Bridge \"$bridge\"" | grep "tag:" | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

                    if [ -z "$vlans" ]; then
                        vlans="None"  # اگر VLAN وجود نداشت
                    fi

                    output+="| $(printf '%-13s' $bridge) | $(printf '%-8s' $status) | $(printf '%-5s' $port_count) | $(printf '%-7s' $vlans) |\n"
                done
                echo -e "$output" > /tmp/bridge_info.txt
                dialog --textbox /tmp/bridge_info.txt "$dialog_height" "$dialog_width"
            fi
            ;;

        4)
            return  # بازگشت به منوی اصلی
            ;;
    esac

    # پس از انجام عملیات، به منوی مدیریت بریج بازگردید
    manage_bridges
}



# نمایش پیام‌ها به کاربر
function show_msg() {
    dialog --msgbox "$1" 10 40
}
 # 2. Add/Delete Ports and View Port Status with Selections
function manage_ports() {
    get_terminal_size  # به‌روزرسانی ابعاد ترمینال
    action=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Manage OVS Ports\Zn" \
        --menu "\nChoose an action:" "$dialog_height" "$dialog_width" 4 \
        1 "\Zb\Z2Add Port\Zn" \
        2 "\Zb\Z2Delete Port\Zn" \
        3 "\Zb\Z2View Ports Status\Zn" \
        4 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

    # بررسی لغو عملیات توسط کاربر
    if [ $? -ne 0 ]; then
        manage_ports  # بازگشت به منوی مدیریت پورت‌ها
        return
    fi

    case $action in
        1)
            # نمایش لیست بریج‌ها برای انتخاب
            bridges=$(sudo ovs-vsctl list-br)
            if [ -z "$bridges" ]; then
                show_msg "No bridges available to add a port."
                manage_ports
                return
            fi

            bridge=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Select Bridge\Zn" \
                --menu "\nSelect a Bridge to Add Port:" "$dialog_height" "$dialog_width" 10 $(echo "$bridges" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)
            
            if [ $? -ne 0 ]; then
                manage_ports  # بازگشت به منوی مدیریت پورت‌ها
                return
            fi

            selected_bridge=$(echo "$bridges" | sed -n "${bridge}p")

            # وارد کردن نام پورت
            port=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Add Port\Zn" \
                --inputbox "\nEnter port name to add:" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            
            if [ $? -ne 0 ] || [ -z "$port" ]; then
                show_msg "\Zb\Z1Port name cannot be empty!\Zn"
                manage_ports
                return
            fi

            # ایجاد پورت در سیستم (dummy interface)
            sudo ip link add "$port" type dummy
            sudo ip link set "$port" up

            # پرسش در مورد VLAN (اختیاری)
            vlan=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3VLAN Configuration\Zn" \
                --inputbox "\nEnter VLAN ID (optional, leave blank for none):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
            
            if [ $? -ne 0 ]; then
                manage_ports
                return
            fi

            # افزودن پورت به بریج و VLAN
            sudo ovs-vsctl add-port $selected_bridge $port
            if [ -n "$vlan" ]; then
                sudo ovs-vsctl set port $port tag=$vlan
                show_msg "\Zb\Z3Port $port added to bridge $selected_bridge with VLAN $vlan.\Zn"
            else
                show_msg "\Zb\Z3Port $port added to bridge $selected_bridge without VLAN.\Zn"
            fi
            manage_ports  # بازگشت به منوی مدیریت پورت‌ها
            ;;

        2)
            # نمایش لیست بریج‌ها برای انتخاب
            bridges=$(sudo ovs-vsctl list-br)
            if [ -z "$bridges" ]; then
                show_msg "No bridges available to delete a port from."
                manage_ports
                return
            fi

            bridge=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Select Bridge\Zn" \
                --menu "\nSelect a Bridge to Delete Port From:" "$dialog_height" "$dialog_width" 10 $(echo "$bridges" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)
            
            if [ $? -ne 0 ]; then
                manage_ports
                return
            fi

            selected_bridge=$(echo "$bridges" | sed -n "${bridge}p")

            # نمایش لیست پورت‌های بریج انتخاب شده
            ports=$(sudo ovs-vsctl list-ports $selected_bridge)
            if [ -z "$ports" ]; then
                show_msg "No ports available to delete in bridge $selected_bridge."
                manage_ports
                return
            fi

            port_to_delete=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Select Port\Zn" \
                --menu "\nSelect a Port to Delete:" "$dialog_height" "$dialog_width" 10 $(echo "$ports" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)
            
            if [ $? -ne 0 ]; then
                manage_ports
                return
            fi

            selected_port=$(echo "$ports" | sed -n "${port_to_delete}p")

            # تایید حذف
            dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z1Confirm Deletion\Zn" \
                --yesno "\nAre you sure you want to delete port $selected_port from bridge $selected_bridge?" "$dialog_height" "$dialog_width"

            if [ $? -eq 0 ]; then
                sudo ovs-vsctl del-port $selected_bridge $selected_port
                sudo ip link delete "$selected_port"  # حذف پورت از سیستم
                show_msg "\Zb\Z3Port $selected_port deleted from bridge $selected_bridge.\Zn"
            else
                show_msg "Deletion cancelled."
            fi
            manage_ports  # بازگشت به منوی مدیریت پورت‌ها
            ;;

        3)
            # نمایش وضعیت پورت‌ها
            bridge=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3View Port Status\Zn" \
                --inputbox "\nEnter bridge name to view port status (Leave empty to view all):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

            if [ $? -ne 0 ]; then
                manage_ports
                return
            fi

            output="| Bridge Name   | Port Name     | Admin State | Link State |\n"
            output+="----------------------------------------------------------\n"

            if [ -z "$bridge" ]; then
                # اگر بریج مشخص نشده باشد، همه بریج‌ها و پورت‌ها نمایش داده می‌شوند
                current_bridges=$(sudo ovs-vsctl list-br)
                if [ -z "$current_bridges" ]; then
                    show_msg "\Zb\Z1No bridges currently exist.\Zn"
                    manage_ports
                    return
                fi

                for current_bridge in $current_bridges; do
                    current_ports=$(sudo ovs-vsctl list-ports "$current_bridge")
                    if [ -z "$current_ports" ]; then
                        output+="$current_bridge          No Ports\n"
                    else
                        for port in $current_ports; do
                            admin_state=$(sudo ovs-vsctl get Interface "$port" admin_state)
                            link_state=$(sudo ovs-vsctl get Interface "$port" link_state)
                            output+="$current_bridge          $port        $admin_state     $link_state\n"
                        done
                    fi
                done
            else
                # اگر بریج مشخص شده باشد، بررسی وجود آن بریج
                if ! sudo ovs-vsctl br-exists "$bridge"; then
                    show_msg "Bridge $bridge does not exist"
                    manage_ports
                    return
                fi

                # نمایش وضعیت پورت‌های بریج مشخص شده
                current_ports=$(sudo ovs-vsctl list-ports "$bridge")
                if [ -z "$current_ports" ]; then
                    show_msg "No ports found on bridge $bridge."
                    manage_ports
                    return
                fi

                for port in $current_ports; do
                    admin_state=$(sudo ovs-vsctl get Interface "$port" admin_state)
                    link_state=$(sudo ovs-vsctl get Interface "$port" link_state)
                    output+="$bridge           $port      $admin_state  $link_state\n"
                done
            fi

            # نمایش خروجی در dialog --textbox
            echo -e "$output" > /tmp/port_status.txt
            dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Port Status\Zn" --textbox /tmp/port_status.txt "$dialog_height" "$dialog_width"
            rm /tmp/port_status.txt
            manage_ports 
            ;;

        4)
            return  
            ;;
    esac
}


# 3. Enable/Disable Ports with ip link
function toggle_port() {
    get_terminal_size  # به‌روزرسانی ابعاد ترمینال
    bridge=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Enter Bridge Name\Zn" \
        --inputbox "\nEnter bridge name to view ports (or leave empty to view all):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # اگر کاربر عملیات را لغو کرد
    fi

    if [ -z "$bridge" ]; then
        current_bridges=$(sudo ovs-vsctl list-br)
        if [ -z "$current_bridges" ]; then
            show_msg "No bridges found."
            toggle_port  # بازگشت به منوی مدیریت پورت‌ها
            return
        fi
        port_list=()
        for bridge in $current_bridges; do
            ports=$(sudo ovs-vsctl list-ports "$bridge")
            for port in $ports; do
                port_list+=("$port" "Bridge: $bridge")
            done
        done
    else
        current_ports=$(sudo ovs-vsctl list-ports "$bridge")
        if [ -z "$current_ports" ]; then
            show_msg "No ports found on bridge $bridge."
            toggle_port  # بازگشت به منوی مدیریت پورت‌ها
            return
        fi
        port_list=()
        for port in $current_ports; do
            port_list+=("$port" "Bridge: $bridge")
        done
    fi

    # نمایش لیست پورت‌ها برای انتخاب
    port_choice=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Select Port to Toggle\Zn" \
        --menu "\nSelect a port to toggle:" "$dialog_height" "$dialog_width" 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        toggle_port  # بازگشت به منوی مدیریت پورت‌ها
        return
    fi

    # بررسی وضعیت فعلی پورت
    port_status=$(sudo ovs-vsctl get Interface "$port_choice" admin_state)
    if [[ "$port_status" == "up" ]]; then
        # اگر پورت فعال باشد، نمایش گزینه غیرفعال کردن
        action=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Port Status\Zn" \
            --menu "\nPort \Zb$port_choice\Zn is currently \ZbENABLED\Zn. What do you want to do?" "$dialog_height" "$dialog_width" 2 \
            1 "\Zb\Z1Disable\Zn" \
            2 "\Zb\Z2Back to Menu\Zn" 3>&1 1>&2 2>&3)
    else
        # اگر پورت غیرفعال باشد، نمایش گزینه فعال کردن
        action=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Port Status\Zn" \
            --menu "\nPort \Zb$port_choice\Zn is currently \ZbDISABLED\Zn. What do you want to do?" "$dialog_height" "$dialog_width" 2 \
            1 "\Zb\Z2Enable\Zn" \
            2 "\Zb\Z2Back to Menu\Zn" 3>&1 1>&2 2>&3)
    fi

    if [ $? -ne 0 ]; then
        toggle_port  
        return
    fi

    case $action in
        1)
            if [[ "$port_status" == "up" ]]; then
                dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z1Confirm Action\Zn" \
                    --yesno "\nAre you sure you want to \ZbDISABLE\Zn port \Zb$port_choice\Zn?" "$dialog_height" "$dialog_width"
                if [ $? -eq 0 ]; then
                    sudo ovs-vsctl set Interface "$port_choice" admin_state=down
                    sudo ip link set "$port_choice" down
                    show_msg "\Zb\Z3Port $port_choice disabled.\Zn"
                else
                    show_msg "Action canceled."
                fi
            else
                dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z1Confirm Action\Zn" \
                    --yesno "\nAre you sure you want to \ZbENABLE\Zn port \Zb$port_choice\Zn?" "$dialog_height" "$dialog_width"
                if [ $? -eq 0 ]; then
                    sudo ip link set "$port_choice" up
                    sudo ovs-vsctl set Interface "$port_choice" admin_state=up
                    show_msg "Port $port_choice enabled."
                else
                    show_msg "Action canceled"
                fi
            fi
            toggle_port 
            ;;
        2)
            toggle_port  
            ;;
    esac
}


# 4. Set VLAN to Access/Trunk with View/Remove VLAN Status and Main Menu Option
function configure_vlan() {
    get_terminal_size  # دریافت ابعاد صفحه

    bridge=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Enter Bridge Name\Zn" \
        --inputbox "\nEnter bridge name to view ports:" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return  # لغو عملیات
    fi
    
    if [ -z "$bridge" ]; then
        # اگر بریج مشخص نشده باشد، نمایش لیست همه بریج‌ها و پورت‌ها
        current_bridges=$(sudo ovs-vsctl list-br)
        if [ -z "$current_bridges" ]; then
            show_msg "No bridges available."
            configure_vlan  # بازگشت به تابع تنظیم VLAN
            return
        fi
        port_list=()
        for bridge in $current_bridges; do
            ports=$(sudo ovs-vsctl list-ports "$bridge")
            for port in $ports; do
                port_list+=("$port" "Bridge: $bridge")
            done
        done
    else
        # اگر بریج مشخص شده باشد، نمایش پورت‌های آن بریج
        current_ports=$(sudo ovs-vsctl list-ports "$bridge")
        if [ -z "$current_ports" ]; then
            show_msg "No ports found on bridge $bridge."
            configure_vlan  # بازگشت به تابع تنظیم VLAN
            return
        fi
        port_list=()
        for port in $current_ports; do
            port_list+=("$port" "Bridge: $bridge")
        done
    fi

    # انتخاب پورت برای تنظیم VLAN
    port_choice=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Select Port\Zn" \
        --menu "\nSelect a port to configure VLAN:" "$dialog_height" "$dialog_width" 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        configure_vlan  
        return
    fi

    # منوی تنظیم VLAN: تنظیم، نمایش، یا حذف
    vlan_action=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3VLAN Configuration\Zn" \
        --menu "\nVLAN Configuration for Port $port_choice:" "$dialog_height" "$dialog_width" 4 \
        1 "\Zb\Z2Configure VLAN\Zn" \
        2 "\Zb\Z3View VLAN Status\Zn" \
        3 "\Zb\Z4Remove VLAN\Zn" \
        4 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        configure_vlan  
        return
    fi

    case $vlan_action in
        1)
            # انتخاب حالت VLAN: Access یا Trunk
            mode=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Select VLAN Mode\Zn" \
                --menu "\nSelect VLAN Mode for Port $port_choice:" "$dialog_height" "$dialog_width" 2 \
                1 "\Zb\Z2Access Mode\Zn" \
                2 "\Zb\Z2Trunk Mode\Zn" 3>&1 1>&2 2>&3)

            if [ $? -ne 0 ]; then
                configure_vlan  
                return
            fi

            dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Changing VLAN Mode\Zn" \
                --msgbox "\nChanging VLAN mode will remove the previous configuration (Access or Trunk) for port $port_choice." "$dialog_height" "$dialog_width"

            # پاک‌سازی تنظیمات قبلی
            sudo ovs-vsctl clear port "$port_choice" tag
            sudo ovs-vsctl clear port "$port_choice" trunks

            case $mode in
                1)
                    # حالت Access
                    while true; do
                        vlan_id=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Access Mode Configuration\Zn" \
                            --inputbox "\nEnter VLAN ID for access mode (e.g., 10):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                        
                        if [[ -z "$vlan_id" ]]; then
                            show_msg "VLAN ID cannot be empty! Please enter a valid VLAN ID."
                        elif ! [[ "$vlan_id" =~ ^[0-9]+$ ]]; then
                            show_msg "Invalid VLAN ID! You must enter a positive number."
                        else
                            break  # اگر مقدار درست بود، از حلقه خارج می‌شود
                        fi
                    done
                    sudo ovs-vsctl set port "$port_choice" tag="$vlan_id"
                    show_msg "Port $port_choice set to access mode with VLAN $vlan_id."
                    ;;
                2)
                    # حالت Trunk
                    while true; do
                        vlans=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Trunk Mode Configuration\Zn" \
                            --inputbox "\nEnter allowed VLANs (comma-separated, e.g., 10,20,30):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)
                        
                        if [[ -z "$vlans" ]]; then
                            show_msg "Allowed VLANs cannot be empty! Please enter a valid list of VLANs."
                        elif ! [[ "$vlans" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
                            show_msg "Invalid VLAN format! You must enter a comma-separated list of positive numbers (e.g., 10,20,30)."
                        else
                            break  # اگر مقدار درست بود، از حلقه خارج می‌شود
                        fi
                    done
                    sudo ovs-vsctl set port "$port_choice" trunks="[$vlans]"
                    show_msg "Port $port_choice set to trunk mode with allowed VLANs: $vlans."
                    ;;
            esac
            configure_vlan  
            ;;
        2)
            # نمایش وضعیت فعلی VLAN
            vlan_tag=$(sudo ovs-vsctl get port "$port_choice" tag)
            trunk_vlans=$(sudo ovs-vsctl get port "$port_choice" trunks)
            [ "$vlan_tag" == "[]" ] && vlan_tag="None"
            [ "$trunk_vlans" == "[]" ] && trunk_vlans="None"
            vlan_info="\Zb\Z3VLAN Status for Port: $port_choice\Zn\n"
            vlan_info+="------------------------------\n"
            vlan_info+="Access VLAN: $vlan_tag\n"
            vlan_info+="Trunk VLANs: $trunk_vlans\n"
            dialog --colors --msgbox "$vlan_info" "$dialog_height" "$dialog_width"
            configure_vlan  
            ;;
        3)
            # حذف VLANهای پورت
            vlan_tag=$(sudo ovs-vsctl get port "$port_choice" tag)
            trunk_vlans=$(sudo ovs-vsctl get port "$port_choice" trunks)
            [ "$vlan_tag" == "[]" ] && vlan_tag=""
            [ "$trunk_vlans" == "[]" ] && trunk_vlans=""

            if [ -z "$vlan_tag" ] && [ -z "$trunk_vlans" ]; then
                show_msg "No VLANs configured on port $port_choice to remove."
                configure_vlan  
                return
            fi

            # ساخت لیست VLANها برای حذف
            vlan_list=()
            [ -n "$vlan_tag" ] && vlan_list+=("$vlan_tag" "Access VLAN" "off")
            if [ -n "$trunk_vlans" ]; then
                IFS=',' read -ra vlans_array <<< "$trunk_vlans"
                for vlan in "${vlans_array[@]}"; do
                    clean_vlan=$(echo "$vlan" | tr -d '[]')
                    vlan_list+=("$clean_vlan" "Trunk VLAN" "off")
                done
            fi

            vlan_selection=$(dialog --colors --checklist "\nSelect VLAN(s) to remove from port $port_choice:" "$dialog_height" "$dialog_width" 10 "${vlan_list[@]}" 3>&1 1>&2 2>&3)

            if [ $? -ne 0 ]; then
                configure_vlan  # بازگشت به تابع تنظیم VLAN
                return
            fi

            # حذف VLANهای انتخاب شده
            dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --yesno "\nAre you sure you want to remove the selected VLAN(s) from port $port_choice?" "$dialog_height" "$dialog_width"
            if [ $? -eq 0 ]; then
                IFS=' ' read -ra selected_vlans <<< "$vlan_selection"
                removed_vlans=()
                for vlan in "${selected_vlans[@]}"; do
                    vlan=$(echo "$vlan" | tr -d '"')
                    if [ "$vlan" == "$vlan_tag" ]; then
                        sudo ovs-vsctl clear port "$port_choice" tag
                    else
                        sudo ovs-vsctl remove port "$port_choice" trunks "$vlan"
                    fi
                    removed_vlans+=("$vlan")
                done
                vlan_list_str=$(printf ", %s" "${removed_vlans[@]}")
                vlan_list_str=${vlan_list_str:2}
                show_msg "VLAN(s) $vlan_list_str removed from port $port_choice."
            else
                show_msg "Action canceled."
            fi
            configure_vlan  # بازگشت به تابع تنظیم VLAN
            ;;
        4)
            return  # بازگشت به منوی اصلی
            ;;
    esac
}


# 5. Set VLAN IP
function set_vlan_ip() {
    get_terminal_size
    # پیشنهاد تمام رابط‌های موجود (فیزیکی و مجازی) و حذف lo
    interfaces=$(ip link show | grep -o '^[0-9]*: [^:]*' | awk '{print $2}' | grep -v "^lo$" | sort | uniq)

    # بررسی اینکه آیا رابط‌ها وجود دارند یا خیر
    if [ -z "$interfaces" ]; then
        show_msg "No interfaces found!"
        return
    fi
    
    # آماده‌سازی لیست اینترفیس‌ها برای نمایش (بدون تکرار نام)
    interface_list=()
    for i in $interfaces; do
        if [[ "$i" == *@* ]]; then
            # اگر شامل '@' بود، فقط بخش قبل از '@' نمایش داده شود
            display_name=$(echo "$i" | cut -d'@' -f1)
        else
            display_name="$i"
        fi
        interface_list+=("$i" "")  # فقط نام اینترفیس را بدون مقدار اضافی اضافه می‌کنیم
    done

    # نمایش لیست رابط‌های موجود برای انتخاب
    interface=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Select Interface\Zn" \
        --menu "\nSelect interface for VLAN configuration:" "$dialog_height" "$dialog_width" 10 "${interface_list[@]}" 3>&1 1>&2 2>&3)

    # اگر کاربر در این مرحله Cancel بزند، به منوی اصلی برمی‌گردد
    if [ $? -ne 0 ]; then
        return  # بازگشت به منوی اصلی در صورت لغو
    fi

    # بررسی اینکه آیا اینترفیس انتخاب‌شده یک VLAN است (بر اساس فرمت)
    if [[ "$interface" == *.* || "$interface" == *@* ]]; then
        # اگر اینترفیس VLAN بود، فقط IP دریافت می‌شود
        while true; do
            ip_address=$(dialog --inputbox "Enter IP address for the VLAN interface (e.g., 192.168.1.10/24):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

            # در صورت کنسل کردن در این مرحله به صفحه انتخاب اینترفیس برمی‌گردد
            if [ $? -ne 0 ]; then
                set_vlan_ip
                return
            fi

            # بررسی اینکه IP آدرس وارد شده خالی نباشد و فرمت درستی داشته باشد
            if [[ -z "$ip_address" ]]; then
                show_msg "IP address cannot be empty! Please enter a valid IP."
            elif ! [[ "$ip_address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$ ]]; then
                show_msg "Invalid IP format! Please enter a valid IP (e.g., 192.168.1.10/24)."
            else
                break
            fi
        done
    else
        # دریافت VLAN ID از کاربر برای اینترفیس‌های فیزیکی
        while true; do
            vlan_id=$(dialog --inputbox "Enter VLAN ID (e.g., 10):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

            # در صورت کنسل کردن در این مرحله به صفحه انتخاب اینترفیس برمی‌گردد
            if [ $? -ne 0 ]; then
                set_vlan_ip
                return
            fi
            
            # بررسی اینکه VLAN ID خالی نباشد و یک عدد صحیح مثبت باشد
            if [[ -z "$vlan_id" ]]; then
                show_msg "VLAN ID cannot be empty! Please enter a valid VLAN ID."
            elif ! [[ "$vlan_id" =~ ^[0-9]+$ ]]; then
                show_msg "Invalid VLAN ID! You must enter a positive number."
            else
                break
            fi
        done

        # ساخت اینترفیس VLAN
        vlan_interface="${interface}.${vlan_id}"
        sudo ip link add link "$interface" name "$vlan_interface" type vlan id "$vlan_id"
        sudo ip link set dev "$vlan_interface" up

        # دریافت IP از کاربر
        while true; do
            ip_address=$(dialog --inputbox "Enter IP address for the VLAN interface (e.g., 192.168.1.10/24):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

            # در صورت کنسل کردن در این مرحله به صفحه انتخاب اینترفیس برمی‌گردد
            if [ $? -ne 0 ]; then
                set_vlan_ip
                return
            fi

            # بررسی اینکه IP آدرس وارد شده خالی نباشد و فرمت درستی داشته باشد
            if [[ -z "$ip_address" ]]; then
                show_msg "IP address cannot be empty! Please enter a valid IP."
            elif ! [[ "$ip_address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$ ]]; then
                show_msg "Invalid IP format! Please enter a valid IP (e.g., 192.168.1.10/24)."
            else
                break
            fi
        done
    fi

    # بررسی اینکه آیا IP از قبل وجود دارد یا خیر
    if ip addr show dev "$interface" | grep -q "$ip_address"; then
        show_msg "IP address $ip_address is already assigned to interface $interface."
        return
    fi

    # تنظیم IP برای اینترفیس VLAN
    if sudo ip addr add "$ip_address" dev "$interface"; then
        show_msg "IP address $ip_address added to VLAN interface $interface."
    else
        show_msg "Failed to add IP address $ip_address to VLAN interface $interface. Please check the details."
    fi

    # بازگشت به صفحه انتخاب اینترفیس بعد از اعمال تغییرات
    set_vlan_ip
}

# 6. Configure QoS for a Port
function set_qos() {
    get_terminal_size  # تنظیم ابعاد پویا برای نمایش
    while true; do
        # نمایش منوی اصلی QoS
        qos_action=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3QoS Configuration Menu\Zn" \
            --menu "\nChoose an action for QoS:" "$dialog_height" "$dialog_width" 4 \
            1 "\Zb\Z2Set QoS for a Port\Zn" \
            2 "\Zb\Z2View Current QoS for a Port\Zn" \
            3 "\Zb\Z2Remove QoS from a Port\Zn" \
            4 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ] || [ -z "$qos_action" ]; then
            return  
        fi

        case $qos_action in
            1)  # تنظیم QoS برای یک پورت
                # لیست کردن بریج‌های موجود
                bridges=$(sudo ovs-vsctl list-br)

                if [ -z "$bridges" ]; then
                    show_msg "No OVS bridges available!"
                    continue  # بازگشت به منوی QoS
                fi

                port_list=()
                # لیست پورت‌های هر بریج
                for bridge in $bridges; do
                    ports=$(sudo ovs-vsctl list-ports "$bridge")
                    for port in $ports; do
                        port_list+=("$port" "$bridge")
                    done
                done

                # بررسی اینکه آیا پورت‌ها موجود هستند
                if [ ${#port_list[@]} -eq 0 ]; then
                    show_msg "No ports available!"
                    continue  # بازگشت به منوی QoS
                fi

                # نمایش لیست پورت‌ها برای انتخاب
                port=$(dialog --menu "Select Port to apply QoS" "$dialog_height" "$dialog_width" 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

                if [ $? -ne 0 ] || [ -z "$port" ]; then
                    continue  # بازگشت به منوی QoS در صورت لغو
                fi

                # دریافت نرخ حداکثر (Max Rate) از کاربر
                while true; do
                    max_rate=$(dialog --inputbox "Enter maximum rate (in kbps):" "$dialog_height" "$dialog_width" 3>&1 1>&2 2>&3)

                    # بررسی اینکه max_rate خالی نباشد و یک عدد صحیح مثبت باشد
                    if [[ -z "$max_rate" ]]; then
                        show_msg "Maximum rate cannot be empty! Please enter a valid rate."
                        set_qos
                    elif ! [[ "$max_rate" =~ ^[0-9]+$ ]]; then
                        show_msg "Invalid rate! You must enter a positive number."
                        set_qos
                    else
                        break
                    fi
                done

                # اعمال QoS به پورت
                sudo ovs-vsctl set port $port qos=@newqos -- --id=@newqos create qos type=linux-htb other-config:max-rate=$((max_rate*1024)) queues:0=@q0 -- --id=@q0 create queue other-config:max-rate=$((max_rate*1024))
                show_msg "QoS applied to port $port with max rate ${max_rate} kbps."
                ;;

            2)  # نمایش وضعیت فعلی QoS برای یک پورت
                qos_list=$(sudo ovs-vsctl list qos)

                if [ -z "$qos_list" ]; then
                    show_msg "No QoS configurations available!"
                    continue  # بازگشت به منوی QoS
                fi

                # نمایش وضعیت فعلی تمامی QoSها
                dialog --msgbox "QoS Configurations:\n\n$qos_list" "$dialog_height" "$dialog_width"
                ;;

            3)  # حذف QoS از یک پورت
                # لیست کردن بریج‌های موجود
                bridges=$(sudo ovs-vsctl list-br)

                if [ -z "$bridges" ]; then
                    show_msg "No OVS bridges available!"
                    continue  # بازگشت به منوی QoS
                fi

                port_list=()
                # لیست پورت‌های هر بریج
                for bridge in $bridges; do
                    ports=$(sudo ovs-vsctl list-ports "$bridge")
                    for port in $ports; do
                        port_list+=("$port" "$bridge")
                    done
                done

                # بررسی اینکه آیا پورت‌ها موجود هستند
                if [ ${#port_list[@]} -eq 0 ]; then
                    show_msg "No ports available!"
                    continue  # بازگشت به منوی QoS
                fi

                # نمایش لیست پورت‌ها برای انتخاب
                port=$(dialog --menu "Select Port to remove QoS" "$dialog_height" "$dialog_width" 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

                if [ $? -ne 0 ] || [ -z "$port" ]; then
                    continue  # بازگشت به منوی QoS در صورت لغو
                fi

                # تأیید حذف QoS از پورت
                dialog --yesno "Are you sure you want to remove QoS from port $port?" 10 40
                if [ $? -ne 0 ]; then
                    continue  # کاربر عملیات حذف را لغو کرد
                fi

                # حذف QoS از پورت
                sudo ovs-vsctl clear port "$port" qos

                # حذف کامل پیکربندی QoS و صف‌های مرتبط
                qos_uuids=$(sudo ovs-vsctl --no-heading --columns=_uuid find qos)
                for qos_uuid in $qos_uuids; do
                    # حذف صف‌های مرتبط با QoS
                    queue_uuids=$(sudo ovs-vsctl --no-heading --columns=queues find qos _uuid="$qos_uuid")
                    for queue_uuid in $queue_uuids; do
                        sudo ovs-vsctl destroy queue "$queue_uuid"
                    done
                    # حذف QoS
                    sudo ovs-vsctl destroy qos "$qos_uuid"
                done

                # نمایش پیام نهایی به کاربر
                show_msg "QoS cleared from port $port."
                ;;

            4)  # بازگشت به منوی قبلی
                break  
                ;;
        esac
    done
}

# 7. View Traffic Stats for a Port
function show_traffic_stats() {
    # لیست کردن بریج‌های موجود
    bridges=$(sudo ovs-vsctl list-br)

    if [ -z "$bridges" ]; then
        show_msg "No OVS bridges available!"
        return
    fi

    port_list=()
    # لیست پورت‌های هر بریج
    for bridge in $bridges; do
        ports=$(sudo ovs-vsctl list-ports "$bridge")
        for port in $ports; do
            port_list+=("$port" "$bridge")
        done
    done

    # بررسی اینکه آیا پورت‌ها موجود هستند
    if [ ${#port_list[@]} -eq 0 ]; then
        show_msg "No ports available!"
        return
    fi

    # نمایش لیست پورت‌ها برای انتخاب
    port=$(dialog --menu "Select Port to view traffic stats" 15 40 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$port" ]; then
        return  # بازگشت به منوی قبلی در صورت لغو
    fi

    # نمایش آمار ترافیک پورت
    ovs-vsctl list interface $port > /tmp/traffic_stats.txt
    dialog --textbox /tmp/traffic_stats.txt 20 60
}

# 8. Backup OVS Configuration
function backup_ovs_config() {
    # مسیر فعلی و فولدر OVS_backup
    backup_dir="$HOME/net-tool/OVS_backup"
    
    # اگر فولدر OVS_backup وجود ندارد، آن را ایجاد کن
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi

    # فایل بکاپ در فولدر OVS_backup
    backup_file="$backup_dir/ovs_backup_$(date +%F_%T).txt"
    
    # ذخیره پیکربندی OVS در فایل بکاپ
    sudo ovs-vsctl show > "$backup_file"
    
    show_msg "OVS configuration backed up to $backup_file"
}

# 9. Restore OVS Configuration
function restore_ovs_config() {
    # مسیر فعلی و فولدر OVS_backup
    backup_dir="$HOME/net-tool/OVS_backup"
    
    # بررسی اینکه آیا فایل بکاپی در فولدر وجود دارد
    backup_files=$(ls "$backup_dir"/ovs_backup_*.txt 2>/dev/null)
    if [ -z "$backup_files" ]; then
        show_msg "No backup files found in $backup_dir!"
        return
    fi

    file_list=()
    declare -A file_map 

    for file in $backup_files; do
        filename=$(basename "$file") 
        file_list+=("$filename" "")  
        file_map["$filename"]="$file" 
    done

    # نمایش لیست فایل‌های بکاپ به کاربر برای انتخاب
    selected_backup=$(dialog --menu "Select a backup file to restore" 15 50 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

    # بررسی اینکه کاربر فایلی انتخاب کرده یا خیر
    if [ $? -ne 0 ] || [ -z "$selected_backup" ]; then
        show_msg "No backup file selected!"
        return
    fi

    # دریافت مسیر کامل فایل انتخاب‌شده از file_map
    selected_backup_full_path="${file_map[$selected_backup]}"

    # بازیابی پیکربندی OVS از فایل انتخاب‌شده
    sudo ovs-vsctl --no-wait init
    sudo ovs-vsctl --no-wait load "$selected_backup_full_path"
    
    show_msg "OVS configuration restored from $selected_backup"
}
function delete_ovs_backup() {
    # مسیر فعلی و فولدر OVS_backup
    backup_dir="$HOME/net-tool/OVS_backup"

    # بررسی اینکه آیا فایل بکاپی در فولدر وجود دارد
    backup_files=$(ls "$backup_dir"/ovs_backup_*.txt 2>/dev/null)
    if [ -z "$backup_files" ]; then
        show_msg "No backup files found in $backup_dir!"
        return
    fi

    # ساخت لیست برای نمایش فایل‌ها (فقط نام فایل‌ها بدون مسیر) در حالت چک باکس
    file_list=()
    declare -A file_map  # نگهداری مسیر کامل فایل‌ها

    for file in $backup_files; do
        filename=$(basename "$file")  # استخراج نام فایل
        file_list+=("$filename" "" "off")  # افزودن به لیست چک باکس
        file_map["$filename"]="$file"  # نگه‌داری نام فایل و مسیر کامل آن
    done

    # نمایش لیست فایل‌های بکاپ به کاربر برای حذف (چک باکس)
    selected_backups=$(dialog --checklist "Select backup files to delete" 15 50 10 "${file_list[@]}" 3>&1 1>&2 2>&3)

    # بررسی اینکه کاربر بکاپی انتخاب کرده یا خیر
    if [ $? -ne 0 ] || [ -z "$selected_backups" ]; then
        show_msg "No backup files selected for deletion!"
        return
    fi

    # حذف بکاپ‌های انتخاب شده
    for backup in $selected_backups; do
        backup=$(echo "$backup" | tr -d '"')  # حذف نقل قول‌های اضافی
        backup_full_path="${file_map[$backup]}"
        rm -f "$backup_full_path"  # حذف فایل
    done

    show_msg "Selected backup files have been deleted."
}
# 9. Function to display OVS service status and allow restart if needed
ovs_service_status() {
    # Check if OVS service is running
    service_status=$(systemctl is-active openvswitch-switch)
    
    if [ "$service_status" = "active" ]; then
        message="\Zb\Z3Open vSwitch service is currently: Active\Zn"
    else
        message="\Zb\Z1Open vSwitch service is currently: Inactive\Zn"
    fi

    # Display current status and ask if user wants to restart
    dialog --colors --title "Open vSwitch Service Status" --yesno "$message\n\nWould you like to restart the service?" 10 50
    
    if [ $? -eq 0 ]; then
        # If user selects Yes, restart the service
        sudo systemctl restart openvswitch-switch
        
        # Check service status again after restart
        new_status=$(systemctl is-active openvswitch-switch)
        if [ "$new_status" = "active" ]; then
            dialog --colors --msgbox "\Zb\Z2Open vSwitch service restarted successfully and is now active.\Zn" 10 50
        else
            dialog --colors --msgbox "\Zb\Z1Failed to restart Open vSwitch service. It is still inactive.\Zn" 10 50
        fi
    else
        # If user selects No, just return to the previous menu
        dialog --msgbox "No changes were made to the Open vSwitch service." 10 50
    fi
}

# Main Menu
function ovs_managemanet(){
while true; do
    get_terminal_size  # به‌روزرسانی ابعاد ترمینال
    choice=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Open vSwitch Management\Zn" \
        --menu "\nChoose an action:" "$dialog_height" "$dialog_width" 10 \
        1 "\Zb\Z2Manage Bridges\Zn" \
        2 "\Zb\Z2Manage Ports\Zn" \
        3 "\Zb\Z2Toggle Port (Enable/Disable)\Zn" \
        4 "\Zb\Z2Configure VLAN\Zn" \
        5 "\Zb\Z2Set VLAN IP\Zn" \
        6 "\Zb\Z2Set QoS for Port\Zn" \
        7 "\Zb\Z2Show Traffic Stats\Zn" \
        8 "\Zb\Z2Backup/Restore OVS Config\Zn" \
        9 "\Zb\Z2OVS Service Status\Zn" \
        10 "\Zb\Z1Return to Main Menu\Zn" 3>&1 1>&2 2>&3)

    # بررسی لغو عملیات توسط کاربر
    if [ $? -ne 0 ]; then
        clear
        exit 0
    fi

    case $choice in
        1) manage_bridges ;;
        2) manage_ports ;;
        3) toggle_port ;;
        4) configure_vlan ;;
        5) set_vlan_ip ;;
        6) set_qos ;;
        7) show_traffic_stats ;;
        8)
            sub_choice=$(dialog --colors --backtitle "\Zb\Z4Open vSwitch Management\Zn" --title "\Zb\Z3Backup/Restore OVS Config\Zn" \
                --menu "\nChoose an action:" "$dialog_height" "$dialog_width" 4 \
                1 "\Zb\Z2Backup Configuration\Zn" \
                2 "\Zb\Z2Restore Configuration\Zn" \
                3 "\Zb\Z2Delete Backup Configuration\Zn" \
                4 "\Zb\Z1Return to Previous Menu\Zn" 3>&1 1>&2 2>&3)

            # بررسی لغو عملیات
            if [ $? -ne 0 ]; then continue; fi

            case $sub_choice in
                1) backup_ovs_config ;;
                2) restore_ovs_config ;;
                3) delete_ovs_backup ;;
                4) ovs_managemanet ;;
                *) show_msg "Invalid choice!" ;;
            esac
            ;;
        9) ovs_service_status ;;
        10) clear;$BASE_DIR/.././net-tool.sh; exit 0 ;;
        *)
            break
            ;;
    esac
    done
}
ovs_managemanet
