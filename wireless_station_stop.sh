#!/bin/sh

if pkill -x "wpa_supplicant"; then
    echo "Stopping wpa_supplicant..."
fi

if pkill -f "udhcpc -i wlan0"; then
    echo "Stopping udhcpc for wlan0..."
fi

echo "Bringing down wlan0 interface..."
ip link set wlan0 down

echo "Flushing IP addresses from wlan0..."
ip addr flush dev wlan0

echo "Network stopped successfully."

