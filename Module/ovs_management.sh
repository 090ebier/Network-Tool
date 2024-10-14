#!/bin/bash

TITLE="Open vSwitch Management"

function show_msg() {
    dialog --msgbox "$1" 10 40
}



# 1. Add/Delete/View Bridges
function manage_bridges() {
    # منوی مدیریت بریج‌ها
    action=$(dialog --menu "Manage OVS Bridges" 15 60 5 \
        1 "Add Bridge" \
        2 "Delete Bridge" \
        3 "View Current Bridges" \
        4 "Back to Main Menu" 3>&1 1>&2 2>&3)

    case $action in
        1)
            # اضافه کردن بریج جدید
            bridge_name=$(dialog --inputbox "Enter bridge name to add (alphanumeric, hyphens or underscores, max 16 chars):" 10 50 3>&1 1>&2 2>&3)
            if [[ ! "$bridge_name" =~ ^[a-zA-Z0-9_-]{1,16}$ ]]; then
                show_msg "Bridge name is invalid! Use only alphanumeric characters, hyphens, or underscores, and no more than 16 characters."
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
        dialog --msgbox "No bridges currently exist." 10 40
        return
    fi

    # انتخاب بریج برای حذف
    bridge_to_delete=$(dialog --menu "Select a bridge to delete" 15 60 10 $(echo "$current_bridges" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)

    # اگر بریجی انتخاب شد، سوال برای تایید حذف
    if [ -n "$bridge_to_delete" ]; then
        selected_bridge=$(echo "$current_bridges" | sed -n "${bridge_to_delete}p")
        dialog --yesno "Are you sure you want to delete the bridge: $selected_bridge?" 10 40
        response=$?  # گرفتن نتیجه از dialog --yesno
        if [ $response -eq 0 ]; then
            # اگر کاربر تایید کرد
            sudo ovs-vsctl del-br "$selected_bridge"
            dialog --msgbox "Bridge $selected_bridge deleted successfully." 10 40
        else
            dialog --msgbox "Bridge deletion canceled." 10 40
        fi
    else
        dialog --msgbox "No bridge selected for deletion." 10 40
    fi
    ;;


3)
    # نمایش بریج‌های موجود
    current_bridges=$(sudo ovs-vsctl list-br)
    if [ -z "$current_bridges" ]; then
        dialog --msgbox "No bridges currently exist." 10 40
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
        dialog --textbox /tmp/bridge_info.txt 20 50
    fi
    ;;


        4)
            return  # بازگشت به منوی اصلی
            ;;
    esac
}
# نمایش پیام‌ها به کاربر
function show_msg() {
    dialog --msgbox "$1" 10 40
}
 # 2. Add/Delete Ports and View Port Status with Selections
function manage_ports() {
    action=$(dialog --menu "Manage OVS Ports" 15 60 4 \
        1 "Add Port" \
        2 "Delete Port" \
        3 "View Ports Status" \
        4 "Back to Main Menu" 3>&1 1>&2 2>&3)

    case $action in
        1)
            # نمایش لیست بریج‌ها برای انتخاب
            bridges=$(sudo ovs-vsctl list-br)
            if [ -z "$bridges" ]; then
                show_msg "No bridges available to add a port."
                return
            fi

            bridge=$(dialog --menu "Select Bridge to Add Port" 15 60 10 $(echo "$bridges" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)
            selected_bridge=$(echo "$bridges" | sed -n "${bridge}p")

            # وارد کردن نام پورت
            port=$(dialog --inputbox "Enter port name to add:" 10 30 3>&1 1>&2 2>&3)
            if [ -z "$port" ]; then
                show_msg "Port name cannot be empty!"
                return
            fi

            # ایجاد پورت در سیستم (dummy interface)
            sudo ip link add "$port" type dummy
            sudo ip link set "$port" up

            # پرسش در مورد VLAN (اختیاری)
            vlan=$(dialog --inputbox "Enter VLAN ID (optional, leave blank for none):" 10 30 3>&1 1>&2 2>&3)

            # افزودن پورت به بریج و VLAN
            sudo ovs-vsctl add-port $selected_bridge $port
            if [ -n "$vlan" ]; then
                sudo ovs-vsctl set port $port tag=$vlan
                show_msg "Port $port added to bridge $selected_bridge with VLAN $vlan."
            else
                show_msg "Port $port added to bridge $selected_bridge without VLAN."
            fi
            ;;

        2)
            # نمایش لیست بریج‌ها برای انتخاب
            bridges=$(sudo ovs-vsctl list-br)
            if [ -z "$bridges" ]; then
                show_msg "No bridges available to delete a port from."
                return
            fi

            bridge=$(dialog --menu "Select Bridge to Delete Port From" 15 60 10 $(echo "$bridges" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)
            selected_bridge=$(echo "$bridges" | sed -n "${bridge}p")

            # نمایش لیست پورت‌های بریج انتخاب شده
            ports=$(sudo ovs-vsctl list-ports $selected_bridge)
            if [ -z "$ports" ]; then
                show_msg "No ports available to delete in bridge $selected_bridge."
                return
            fi

            port_to_delete=$(dialog --menu "Select Port to Delete" 15 60 10 $(echo "$ports" | awk '{print NR, $1}') 3>&1 1>&2 2>&3)
            selected_port=$(echo "$ports" | sed -n "${port_to_delete}p")

            # تایید حذف
            dialog --yesno "Are you sure you want to delete port $selected_port from bridge $selected_bridge?" 10 30
            if [ $? -eq 0 ]; then
                sudo ovs-vsctl del-port $selected_bridge $selected_port
                sudo ip link delete "$selected_port"  # حذف پورت از سیستم
                show_msg "Port $selected_port deleted from bridge $selected_bridge."
            else
                show_msg "Deletion cancelled."
            fi
            ;;

        3)
            # نمایش وضعیت پورت‌ها
            bridge=$(dialog --inputbox "Enter bridge name to view port status (Leave empty to view all):" 10 30 3>&1 1>&2 2>&3)

            output="| Bridge Name   | Port Name     | Admin State | Link State |\n"
            output+="----------------------------------------------------------\n"

            if [ -z "$bridge" ]; then
                # اگر بریج مشخص نشده باشد، همه بریج‌ها و پورت‌ها نمایش داده می‌شوند
                current_bridges=$(sudo ovs-vsctl list-br)
                if [ -z "$current_bridges" ]; then
                    dialog --msgbox "No bridges currently exist." 10 30
                    exit 0
                fi

                for current_bridge in $current_bridges; do
                    current_ports=$(sudo ovs-vsctl list-ports "$current_bridge")
                    if [ -z "$current_ports" ]; then
                        output+="$current_bridge          No Ports\n"
                    else
                        for port in $current_ports; do
                            admin_state=$(sudo ovs-vsctl get Interface "$port" admin_state)
                            link_state=$(sudo ovs-vsctl get Interface "$port" link_state)
                            output+="$current_bridge        $port       $admin_state   $link_state\n"
                        done
                    fi
                done
            else
                # اگر بریج مشخص شده باشد، بررسی وجود آن بریج
                if ! sudo ovs-vsctl br-exists "$bridge"; then
                    dialog --msgbox "Bridge $bridge does not exist." 10 30
                    exit 0
                fi

                # نمایش وضعیت پورت‌های بریج مشخص شده
                current_ports=$(sudo ovs-vsctl list-ports "$bridge")
                if [ -z "$current_ports" ]; then
                    dialog --msgbox "No ports found on bridge $bridge." 10 30
                    exit 0
                fi

                for port in $current_ports; do
                    admin_state=$(sudo ovs-vsctl get Interface "$port" admin_state)
                    link_state=$(sudo ovs-vsctl get Interface "$port" link_state)
                    output+="$bridge           $port      $admin_state  $link_state\n"
                done
            fi

            # نمایش خروجی در dialog --msgbox
            dialog --msgbox "$output" 20 60
            ;;

        4)
            return  # بازگشت به منوی اصلی
            ;;
    esac
}


# 3. Enable/Disable Ports with ip link
function toggle_port() {
    bridge=$(dialog --inputbox "Enter bridge name to view ports (or leave empty to view all):" 10 40 3>&1 1>&2 2>&3)

    if [ -z "$bridge" ]; then
        current_bridges=$(sudo ovs-vsctl list-br)
        port_list=()
        for bridge in $current_bridges; do
            ports=$(sudo ovs-vsctl list-ports "$bridge")
            for port in $ports; do
                port_list+=("$port" "$bridge")
            done
        done
    else
        current_ports=$(sudo ovs-vsctl list-ports "$bridge")
        if [ -z "$current_ports" ]; then
            show_msg "No ports found on bridge $bridge."
            return
        fi
        port_list=()
        for port in $current_ports; do
            port_list+=("$port" "$bridge")
        done
    fi

    # نمایش لیست پورت‌ها برای انتخاب
    port_choice=$(dialog --menu "Select a port to toggle" 15 60 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$port_choice" ]; then
        show_msg "No port selected."
        return
    fi

    # بررسی وضعیت فعلی پورت
    port_status=$(sudo ovs-vsctl get Interface "$port_choice" admin_state)
    if [[ "$port_status" == "up" ]]; then
        # اگر پورت فعال باشد، نمایش گزینه غیرفعال کردن
        action=$(dialog --menu "Port $port_choice is currently ENABLED. What do you want to do?" 15 60 2 \
            1 "Disable" \
            2 "Back to Menu" 3>&1 1>&2 2>&3)
    else
        # اگر پورت غیرفعال باشد، نمایش گزینه فعال کردن
        action=$(dialog --menu "Port $port_choice is currently DISABLED. What do you want to do?" 15 60 2 \
            1 "Enable" \
            2 "Back to Menu" 3>&1 1>&2 2>&3)
    fi

    case $action in
        1)
            if [[ "$port_status" == "up" ]]; then
                dialog --yesno "Are you sure you want to disable port $port_choice?" 10 40
                if [ $? -eq 0 ]; then
                    sudo ovs-vsctl set Interface "$port_choice" admin_state=down
                    sudo ip link set "$port_choice" down
                    show_msg "Port $port_choice disabled."
                else
                    show_msg "Action canceled."
                fi
            else
                dialog --yesno "Are you sure you want to enable port $port_choice?" 10 40
                if [ $? -eq 0 ]; then
                    sudo ip link add "$port_choice" type dummy
                    sudo ip link set "$port_choice" up
                    sudo ovs-vsctl set Interface "$port_choice" admin_state=up
                    show_msg "Port $port_choice enabled."
                else
                    show_msg "Action canceled."
                fi
            fi
            ;;
        2)
            return  # بازگشت به منوی قبلی
            ;;
    esac
}

# 4. Set VLAN to Access/Trunk with View/Remove VLAN Status and Main Menu Option
# 4. Configure VLAN (Set Access/Trunk Mode and Manage VLANs)
function configure_vlan() {
    bridge=$(dialog --inputbox "Enter bridge name to view ports:" 10 40 3>&1 1>&2 2>&3)
    
    if [ -z "$bridge" ];then
        # اگر نام بریج مشخص نشده، لیست همه بریج‌ها و پورت‌ها نمایش داده شود
        current_bridges=$(sudo ovs-vsctl list-br)
        port_list=()
        for bridge in $current_bridges; do
            ports=$(sudo ovs-vsctl list-ports "$bridge")
            for port in $ports; do
                port_list+=("$port" "$bridge")
            done
        done
    else
        # اگر بریج مشخص شده، پورت‌های آن بریج را نمایش می‌دهد
        current_ports=$(sudo ovs-vsctl list-ports "$bridge")
        if [ -z "$current_ports" ];then
            show_msg "No ports found on bridge $bridge."
            return
        fi
        port_list=()
        for port in $current_ports; do
            port_list+=("$port" "$bridge")
        done
    fi

    # انتخاب پورت برای پیکربندی VLAN
    port_choice=$(dialog --menu "Select a port to configure VLAN" 15 60 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$port_choice" ];then
        show_msg "No port selected."
        return
    fi

    # منوی تنظیم VLAN: تنظیم یا نمایش یا حذف
    vlan_action=$(dialog --menu "VLAN Configuration/Status/Remove" 15 60 4 \
        1 "Configure VLAN" \
        2 "View VLAN Status" \
        3 "Remove VLAN" \
        4 "Back to Main Menu" 3>&1 1>&2 2>&3)

    case $vlan_action in
        1)
            # انتخاب حالت VLAN: Access یا Trunk
            mode=$(dialog --menu "Select VLAN Mode" 15 60 2 \
                1 "Access" \
                2 "Trunk" 3>&1 1>&2 2>&3)

            # نمایش پیغام به کاربر برای حذف پیکربندی قبلی
            dialog --msgbox "Changing VLAN mode will remove the previous configuration (Access or Trunk) for port $port_choice." 10 50

            # بررسی حالت فعلی پورت و پاک‌سازی تنظیمات قبلی (Access یا Trunk)
            current_tag=$(sudo ovs-vsctl get port "$port_choice" tag)
            current_trunks=$(sudo ovs-vsctl get port "$port_choice" trunks)

            if [ "$current_tag" != "[]" ]; then
                sudo ovs-vsctl clear port "$port_choice" tag  # حذف VLAN در حالت Access
            fi
            if [ "$current_trunks" != "[]" ]; then
                sudo ovs-vsctl clear port "$port_choice" trunks  # حذف VLAN در حالت Trunk
            fi

            case $mode in
                1)  # حالت Access
                    while true; do
                        vlan_id=$(dialog --inputbox "Enter VLAN ID for access mode (single VLAN only, e.g., 10):" 10 50 3>&1 1>&2 2>&3)
                        
                        # بررسی اینکه مقدار خالی نباشد و یک عدد صحیح مثبت باشد
                        if [[ -z "$vlan_id" ]]; then
                            show_msg "VLAN ID cannot be empty! Please enter a valid VLAN ID."
                        elif ! [[ "$vlan_id" =~ ^[0-9]+$ ]]; then
                            show_msg "Invalid VLAN ID! You must enter a positive number."
                        else
                            # اگر مقدار درست بود، از حلقه خارج می‌شود
                            break
                        fi
                    done

                    # تنظیم VLAN ID برای حالت Access
                    sudo ovs-vsctl set port "$port_choice" tag="$vlan_id"
                    show_msg "Port $port_choice set to access mode with VLAN $vlan_id."
                    ;;
                    
                2)  # حالت Trunk
                    while true; do
                        vlans=$(dialog --inputbox "Enter allowed VLANs (comma-separated, e.g., 10,20,30) for trunk mode:" 10 50 3>&1 1>&2 2>&3)

                        # بررسی اینکه مقدار خالی نباشد و به صورت اعداد صحیح مثبت و جدا شده با کاما باشد
                        if [[ -z "$vlans" ]]; then
                            show_msg "Allowed VLANs cannot be empty! Please enter a valid list of VLANs."
                        elif ! [[ "$vlans" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
                            show_msg "Invalid VLAN format! You must enter a comma-separated list of positive numbers (e.g., 10,20,30)."
                        else
                            # اگر مقدار درست بود، از حلقه خارج می‌شود
                            break
                        fi
                    done

                    # تنظیم VLANها برای حالت Trunk
                    sudo ovs-vsctl set port "$port_choice" trunks="[$vlans]"
                    show_msg "Port $port_choice set to trunk mode with allowed VLANs: $vlans."
                    ;;
            esac 
            ;;
        2)
            # نمایش وضعیت فعلی VLAN
            vlan_tag=$(sudo ovs-vsctl get port "$port_choice" tag)
            trunk_vlans=$(sudo ovs-vsctl get port "$port_choice" trunks)
            if [ "$vlan_tag" == "[]" ];then vlan_tag="None"; fi
            if [ "$trunk_vlans" == "[]" ];then trunk_vlans="None"; fi
            vlan_info="VLAN Status for Port: $port_choice\n"
            vlan_info+="------------------------------\n"
            vlan_info+="Access VLAN: $vlan_tag\n"
            vlan_info+="Trunk VLANs: $trunk_vlans\n"
            dialog --msgbox "$vlan_info" 15 50
            ;;
        3)
            # حذف VLANهای پورت
            vlan_tag=$(sudo ovs-vsctl get port "$port_choice" tag)
            trunk_vlans=$(sudo ovs-vsctl get port "$port_choice" trunks)

            # تبدیل [] به خالی برای شناسایی درست خروجی
            if [ "$vlan_tag" == "[]" ]; then
                vlan_tag=""
            fi
            if [ "$trunk_vlans" == "[]" ]; then
                trunk_vlans=""
            fi

            # بررسی وجود VLAN ها
            if [ -z "$vlan_tag" ] && [ -z "$trunk_vlans" ]; then
                show_msg "No VLANs configured on port $port_choice to remove."
                return
            fi

            # ساخت لیست VLANها برای نمایش به کاربر
            vlan_list=()
            if [ -n "$vlan_tag" ]; then  # اگر tag خالی نباشد
                vlan_list+=("$vlan_tag" "Access VLAN" "off")
            fi
            if [ -n "$trunk_vlans" ]; then
                IFS=',' read -ra vlans_array <<< "$trunk_vlans"
                for vlan in "${vlans_array[@]}"; do
                    # حذف براکت‌های اضافی از VLAN ID
                    clean_vlan=$(echo "$vlan" | tr -d '[]')
                    vlan_list+=("$clean_vlan" "Trunk VLAN" "off")  # نمایش VLAN ID فقط یک بار
                done
            fi

            # نمایش VLAN ها برای حذف با استفاده از چک‌باکس
            vlan_selection=$(dialog --checklist "Select VLAN(s) to remove" 15 60 10 "${vlan_list[@]}" 3>&1 1>&2 2>&3)

            if [ -z "$vlan_selection" ]; then
                show_msg "No VLANs selected for removal."
                return
            fi

            # حذف VLANهای انتخاب شده توسط کاربر
            dialog --yesno "Are you sure you want to remove the selected VLAN(s) from port $port_choice?" 10 50
            if [ $? -eq 0 ]; then
                IFS=' ' read -ra selected_vlans <<< "$vlan_selection"
                removed_vlans=()  # لیستی برای ذخیره VLANهای حذف‌شده
                for vlan in "${selected_vlans[@]}"; do
                    vlan=$(echo $vlan | tr -d '"')  # حذف نقل قول‌های اضافی
                    if [ "$vlan" == "$vlan_tag" ]; then
                        sudo ovs-vsctl clear port "$port_choice" tag  # حذف VLAN در حالت Access
                        removed_vlans+=("$vlan")  # اضافه کردن VLAN به لیست حذف‌شده‌ها
                    else
                        sudo ovs-vsctl remove port "$port_choice" trunks "$vlan"  # حذف VLAN در حالت Trunk
                        removed_vlans+=("$vlan")  # اضافه کردن VLAN به لیست حذف‌شده‌ها
                    fi
                done

                # نمایش پیغام نهایی برای همه VLANهای حذف‌شده
                if [ ${#removed_vlans[@]} -gt 0 ]; then
                    vlan_list_str=$(printf ", %s" "${removed_vlans[@]}")  # ساختن رشته‌ای از VLANهای حذف‌شده
                    vlan_list_str=${vlan_list_str:2}  # حذف اولین کاما و فضای اضافی
                    show_msg "VLAN(s) $vlan_list_str removed from port $port_choice."
                else
                    show_msg "No VLANs were removed."
                fi
            else
                show_msg "Action canceled."
            fi
            ;;

        4)
            return  # بازگشت به منوی اصلی
            ;;
    esac
}

# 5. Set VLAN IP
function set_vlan_ip() {
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
    interface=$(dialog --menu "Select interface" 15 40 10 "${interface_list[@]}" 3>&1 1>&2 2>&3)

    # بررسی اینکه آیا کاربر Cancel کرده یا چیزی انتخاب نشده است
    if [ $? -ne 0 ] || [ -z "$interface" ]; then
        return  # بازگشت به منوی قبلی
    fi

    # بررسی اینکه آیا اینترفیس انتخاب‌شده یک VLAN است (بر اساس فرمت)
    if [[ "$interface" == *.* || "$interface" == *@* ]]; then
        # اگر اینترفیس VLAN بود، فقط IP دریافت می‌شود
        while true; do
            ip_address=$(dialog --inputbox "Enter IP address for the VLAN interface (e.g., 192.168.1.10/24):" 10 50 3>&1 1>&2 2>&3)

            # بررسی اینکه IP آدرس وارد شده خالی نباشد و فرمت درستی داشته باشد
            if [[ -z "$ip_address" ]]; then
                show_msg "IP address cannot be empty! Please enter a valid IP."
                return
            elif ! [[ "$ip_address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$ ]]; then
                show_msg "Invalid IP format! Please enter a valid IP (e.g., 192.168.1.10/24)."
            else
                break
            fi
        done
    else
        # دریافت VLAN ID از کاربر برای اینترفیس‌های فیزیکی
        while true; do
            vlan_id=$(dialog --inputbox "Enter VLAN ID (e.g., 10):" 10 50 3>&1 1>&2 2>&3)
            
            # بررسی اینکه VLAN ID خالی نباشد و یک عدد صحیح مثبت باشد
            if [[ -z "$vlan_id" ]]; then
                show_msg "VLAN ID cannot be empty! Please enter a valid VLAN ID."
                return
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
            ip_address=$(dialog --inputbox "Enter IP address for the VLAN interface (e.g., 192.168.1.10/24):" 10 50 3>&1 1>&2 2>&3)

            # بررسی اینکه IP آدرس وارد شده خالی نباشد و فرمت درستی داشته باشد
            if [[ -z "$ip_address" ]]; then
                show_msg "IP address cannot be empty! Please enter a valid IP."
                return
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
}

# 6. Configure QoS for a Port
function set_qos() {
    while true; do
        # نمایش منوی اصلی QoS
        qos_action=$(dialog --menu "QoS Configuration Menu" 15 50 4 \
            1 "Set QoS for a Port" \
            2 "View Current QoS for a Port" \
            3 "Remove QoS from a Port" \
            4 "Back to Main Menu" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ] || [ -z "$qos_action" ]; then
            return  # بازگشت به منوی قبلی در صورت لغو
        fi

        case $qos_action in
            1)  # تنظیم QoS برای یک پورت
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
                port=$(dialog --menu "Select Port to apply QoS" 15 40 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

                if [ $? -ne 0 ] || [ -z "$port" ]; then
                    continue  # بازگشت به منوی اصلی در صورت لغو
                fi

                # دریافت نرخ حداکثر (Max Rate) از کاربر
                while true; do
                    max_rate=$(dialog --inputbox "Enter maximum rate (in kbps):" 10 30 3>&1 1>&2 2>&3)

                    # بررسی اینکه max_rate خالی نباشد و یک عدد صحیح مثبت باشد
                    if [[ -z "$max_rate" ]]; then
                        show_msg "Maximum rate cannot be empty! Please enter a valid rate."
                    elif ! [[ "$max_rate" =~ ^[0-9]+$ ]]; then
                        show_msg "Invalid rate! You must enter a positive number."
                    else
                        break
                    fi
                done

                # اعمال QoS به پورت
                sudo ovs-vsctl set port $port qos=@newqos -- --id=@newqos create qos type=linux-htb other-config:max-rate=$((max_rate*1024)) queues:0=@q0 -- --id=@q0 create queue other-config:max-rate=$((max_rate*1024))
                show_msg "QoS applied to port $port with max rate ${max_rate} kbps."
                ;;

            2)  # نمایش وضعیت فعلی QoS برای یک پورت

                # بررسی وجود QoS
                qos_list=$(sudo ovs-vsctl list qos)

                if [ -z "$qos_list" ]; then
                    show_msg "No QoS configurations available!"
                    return
                fi

                # نمایش وضعیت فعلی تمامی QoSها
                dialog --msgbox "QoS Configurations:\n\n$qos_list" 20 60
                ;;

            3)  # حذف QoS از یک پورت
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
                port=$(dialog --menu "Select Port to remove QoS" 15 40 10 "${port_list[@]}" 3>&1 1>&2 2>&3)

                if [ $? -ne 0 ] || [ -z "$port" ]; then
                    continue  # بازگشت به منوی اصلی در صورت لغو
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
                message="QoS cleared from port $port.\nQoS and related queues removed for port $port."
                dialog --msgbox "$message" 10 50
                ;;


            4)  # بازگشت به منوی قبلی
                return  # بازگشت به منوی قبلی
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
    backup_dir="$(pwd)/OVS_backup"
    
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
    backup_dir="$(pwd)/OVS_backup"
    
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
    backup_dir="$(pwd)/OVS_backup"

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
while true; do
    choice=$(dialog --menu "Open vSwitch Management" 15 60 10 \
        1 "Manage Bridges" \
        2 "Manage Ports" \
        3 "Toggle Port (Enable/Disable)" \
        4 "Configure VLAN" \
        5 "Set VLAN IP" \
        6 "Set QoS for Port" \
        7 "Show Traffic Stats" \
        8 "Backup/Restore OVS Config" \
        9 "OVS Service Status" \
        10 "Return to Main Menu" 3>&1 1>&2 2>&3)
        
    case $choice in
        1) manage_bridges ;;
        2) manage_ports ;;
        3) toggle_port ;;
        4) configure_vlan ;;
        5) set_vlan_ip ;;
        6) set_qos ;;
        7) show_traffic_stats ;;
8)
    sub_choice=$(dialog --menu "Backup/Restore OVS Config" 15 60 3 \
        1 "Backup Configuration" \
        2 "Restore Configuration" \
        3 "Delete Backup Configuration" 3>&1 1>&2 2>&3)

    case $sub_choice in
        1) backup_ovs_config ;;
        2) restore_ovs_config ;;
        3) delete_ovs_backup ;;
        *) show_msg "Invalid choice!" ;;
    esac
    ;;
        9) ovs_service_status ;;
        10)
            ./main_menu.sh
            exit 0
            ;;  # Return to main menu and close this script
        *)
            break
            ;;
    esac
done
