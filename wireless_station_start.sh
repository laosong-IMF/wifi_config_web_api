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

echo "Waiting for wpa_supplicant to authenticate with the AP..."
max_retries=30
for i in $(seq 1 $max_retries); do
    sleep 1
    auth_status=$(wpa_cli -i wlan0 status 2>/dev/null | grep "wpa_state" | cut -d= -f2)

    if [ "$auth_status" = "COMPLETED" ]; then
        echo "Successfully authenticated with the AP."
        break
    else
        echo "Waiting for authentication... ($i/$max_retries)"
        echo "Current state: $auth_status"
    fi
done

if [ "$i" -eq "$max_retries" ] && [ "$auth_status" != "COMPLETED" ]; then
    echo "Error: Failed to authenticate within $max_retries seconds."
    wpa_cli -i wlan0 status
    #有一种场景是AP当前不可用但是后续可用，不返回以让后面的udhcpc在后台运行
    #exit 1
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

