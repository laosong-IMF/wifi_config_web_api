#!/bin/sh

WPA_SUPPLICANT_CONF="/opt/gnc/etc/wpa_supplicant.conf"

# Check if udhcpc or wpa_supplicant processes are already running
if pgrep -f "udhcpc -i wlan0" > /dev/null || pgrep -x "wpa_supplicant" > /dev/null; then
    echo "Error: There is already a running 'udhcpc -i wlan0' or wpa_supplicant process."
    echo "Please stop the network first using the stop parameter."
    exit 1
fi

if [ ! -f "$WPA_SUPPLICANT_CONF" ]; then
    echo "$WPA_SUPPLICANT_CONF not found. Exiting."
    exit 1
fi

echo "Bringing up wlan0 interface..."
ip link set wlan0 up

echo "Starting wpa_supplicant..."
wpa_supplicant -D nl80211 -i wlan0 -c $WPA_SUPPLICANT_CONF -B

echo "Waiting for wpa_supplicant to connect to the AP..."
max_retries=30
for i in $(seq 1 $max_retries); do
    sleep 1
    if iw dev wlan0 link | grep -q "Connected to"; then
        echo "Successfully connected to the AP."
        break
    fi
    echo "Waiting for connection... ($i/$max_retries)"
done

if [ $i -eq $max_retries ]; then
    echo "Error: wpa_supplicant failed to connect to the AP. Exiting."
    exit 1
fi

echo "Starting udhcpc to obtain IP address for wlan0..."
udhcpc -i wlan0 -b -t 10 -R -O staticroutes \
       -p /var/run/udhcpc.wlan0.pid

if ip addr show wlan0 | grep -q "inet "; then
    echo "Successfully obtained IP address."
else
    echo "Error: Failed to obtain IP address."
    exit 1
fi

echo "wlan0 network setup completed successfully."

