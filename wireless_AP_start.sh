#!/bin/sh

# Configuration variables
AP_IP="192.168.100.1"
HOSTAPD_CONF="/opt/gnc/etc/hostapd.conf"
DNSMASQ_CONF="/opt/gnc/etc/dnsmasq.conf"
NGINX_CMD="/opt/gnc/www/S50nginx"

# Check if hostapd or dnsmasq is already running
if pgrep -f "hostapd" > /dev/null || pgrep -f "dnsmasq" > /dev/null; then
    echo "Error: There is already a running hostapd or dnsmasq process."
    echo "Please stop the network first using the stop parameter."
    exit 1
fi

echo "Setting up wlan0 interface for AP mode..."
ip addr add $AP_IP/24 dev wlan0
ip link set wlan0 up

echo "Starting hostapd (Access Point)..."
hostapd $HOSTAPD_CONF -B

echo "Starting dnsmasq for DHCP and DNS services..."
dnsmasq -C $DNSMASQ_CONF

echo "Flushing all NAT rules..."
iptables -t nat -F

echo "Setting up NAT rule for port forwarding..."
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $AP_IP:80

echo "Starting nginx web server..."
$NGINX_CMD start

echo "AP network setup completed successfully."

