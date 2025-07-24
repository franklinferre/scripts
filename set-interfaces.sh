#!/bin/bash
cat <<EOF > /etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# Loopback principal
auto lo
iface lo inet loopback

# Interface ens18 usando DHCP
allow-hotplug ens18
iface ens18 inet dhcp

# Interface loopback adicional com IP 186.208.0.51/32
auto lo:0
iface lo:0 inet static
    address 186.208.0.51
    netmask 255.255.255.255
EOF
