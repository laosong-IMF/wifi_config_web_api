#!/bin/sh

# Configuration variables
NGINX_CMD="/opt/gnc/www/S50nginx"

# Get list of all connected stations
connected_stations=$(hostapd_cli -i wlan0 all_sta | awk '/^[[:xdigit:]:]{17}/ {print $1}')

if [ -n "$connected_stations" ]; then
    echo "Sending deauthentication messages to connected stations..."
    for station in $connected_stations; do
        echo "Deauthenticating station: $station"
        hostapd_cli deauthenticate $station reason=3
    done
fi

echo "Stopping hostapd..."
pkill -f "hostapd"

echo "Stopping dnsmasq..."
pkill -f "dnsmasq"

echo "Flushing PREROUTING NAT rules..."
iptables -t nat -F PREROUTING

echo "Bringing down wlan0 interface..."
ip link set wlan0 down

echo "Flushing IP addresses from wlan0..."
ip addr flush dev wlan0

echo "Stopping nginx web server..."
$NGINX_CMD stop

echo "AP network stopped successfully."

