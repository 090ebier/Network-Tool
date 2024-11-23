#!/bin/bash

check_configuration() {
    if command -v netplan >/dev/null 2>&1; then
        echo "Netplan is being used for network configuration."
        return 0
    elif [ -d /etc/network/interfaces.d ]; then
        echo "Legacy configuration using /etc/network/interfaces detected."
        return 0
    else
        echo "Unknown network configuration method."
        return 1
    fi
}

check_configuration

check_dhcp_service() {
    if command -v "dhclient" > /dev/null; then
        echo "dhclient is running. DHCP service is provided by dhclient (client-side)."
        return 0

    elif command -v "dhcpcd" > /dev/null; then
        echo "dhcpcd is running. DHCP service is provided by dhcpcd (client-side)."
        return 0

    elif command -v "udhcpc" > /dev/null; then
        echo "udhcpc is running. DHCP service is provided by udhcpc (client-side)."
        return 0

    elif systemctl is-active --quiet NetworkManager; then

        NM_DHCP_STATUS=$(nmcli device show | grep -i "IP4.DHCP4" | awk '{print $2}')
        if [ "$NM_DHCP_STATUS" == "yes" ]; then
            echo "NetworkManager is managing DHCP for interfaces. DHCP service is provided by NetworkManager (client-side)."
        else
            echo "NetworkManager is active, but no DHCP is configured."
        fi
        return 0

    elif systemctl is-active --quiet systemd-networkd; then

        if grep -i "DHCP=ipv4" /etc/systemd/network/*.network > /dev/null; then
            echo "systemd-networkd is managing DHCP for interfaces. DHCP service is provided by systemd-networkd (client-side)."
        else
            echo "systemd-networkd is active, but no DHCP configuration found."
        fi
        return 0
    else
        echo "No DHCP service detected on the system."
        return 1
    fi
}

check_dhcp_service
