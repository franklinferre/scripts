apt update && apt install sudo curl lsb-release -y

# add GPG key
curl -s https://deb.frrouting.org/frr/keys.gpg | sudo tee /usr/share/keyrings/frrouting.gpg > /dev/null

# possible values for FRRVER: 
frr-6 frr-7 frr-8 frr-9 frr-9.0 frr-9.1 frr-10 frr10.0 frr10.1 frr-10.2 frr-10.3 frr-rc frr-stable
# frr-stable will be the latest official stable release. frr-rc is the latest release candidate in beta testing
FRRVER="frr-stable"
echo deb '[signed-by=/usr/share/keyrings/frrouting.gpg]' https://deb.frrouting.org/frr \
     $(lsb_release -s -c) $FRRVER | sudo tee -a /etc/apt/sources.list.d/frr.list

# update and install FRR
sudo apt update && sudo apt install frr frr-pythontools
# Habilitar BGP daemon
sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons

# Gerar configuração do FRR
echo "Gerando configuração do FRR..."
cat > /etc/frr/frr.conf << EOF
frr version 9.1
frr defaults traditional
log syslog informational
service integrated-vtysh-config
!
router bgp 262713
 no bgp hard-administrative-reset
 no bgp graceful-restart notification
 neighbor 172.16.234.234 remote-as 262713
 neighbor 172.16.234.234 description "loopback-RR-ALL-FW"
 !
 address-family ipv4 unicast
  redistribute kernel
  redistribute connected
  redistribute static
  neighbor 172.16.234.234 prefix-list RR-IPV4-IN in
  neighbor 172.16.234.234 prefix-list RR-IPV4-OUT out
  neighbor 172.16.234.234 route-map SET-COMMUNITY out
 exit-address-family
exit
!
ip prefix-list RR-IPV4-IN seq 5 deny any
ip prefix-list RR-IPV4-OUT seq 5 permit 186.208.0.0/20 le 32
ip prefix-list BLOQUEIA-TUDO seq 5 deny any
!
route-map SET-COMMUNITY permit 10
 set community 262713:1010
exit
!
EOF

systemctl restart frr

