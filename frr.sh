#!/bin/bash

set -e

echo "[+] Adicionando chave e repositório do FRRouting..."
curl -s https://deb.frrouting.org/frr/keys.gpg | sudo tee /usr/share/keyrings/frrouting.gpg > /dev/null
FRRVER="frr-stable"
echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -sc) $FRRVER" | sudo tee /etc/apt/sources.list.d/frr.list

echo "[+] Atualizando pacotes e instalando FRRouting..."
sudo apt update && sudo apt -y install frr frr-pythontools

echo "[+] Habilitando daemon BGP..."
sudo sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons

echo "[+] Gerando configuração do FRR..."
sudo tee /etc/frr/frr.conf > /dev/null <<EOF
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

echo "[+] Reiniciando serviço FRR..."
sudo systemctl restart frr
sudo systemctl enable frr

echo "[✓] FRRouting instalado e BGP configurado com sucesso."
