#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para imprimir mensagens coloridas
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para validar IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        IFS='.' read -a ip_parts <<< "${ip%/*}"
        for part in "${ip_parts[@]}"; do
            if [[ $part -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Função para listar interfaces de rede (excluindo loopback e virtuais)
list_network_interfaces() {
    print_info "Listando interfaces de rede disponíveis..."
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v '@' | sort))
    echo "${interfaces[@]}"
}

# Função para selecionar interface
select_interface() {
    local interfaces=($(list_network_interfaces))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        print_error "Nenhuma interface de rede encontrada!"
        exit 1
    elif [[ ${#interfaces[@]} -eq 1 ]]; then
        selected_interface="${interfaces[0]}"
        print_info "Interface selecionada automaticamente: $selected_interface"
    else
        echo
        print_info "Múltiplas interfaces encontradas:"
        for i in "${!interfaces[@]}"; do
            echo "  $((i+1))) ${interfaces[i]}"
        done
        
        while true; do
            echo
            read -p "Selecione a interface (1-${#interfaces[@]}): " choice
            
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#interfaces[@]} ]]; then
                selected_interface="${interfaces[$((choice-1))]}"
                print_success "Interface selecionada: $selected_interface"
                break
            else
                print_error "Seleção inválida. Digite um número entre 1 e ${#interfaces[@]}."
            fi
        done
    fi
}

# Função para obter próximo número de subinterface disponível
get_next_subinterface() {
    local base_interface=$1
    local max_sub=0
    
    # Verifica subinterfaces existentes
    for sub in $(ip addr show | grep -o "${base_interface}\.[0-9]*" | cut -d'.' -f2 | sort -n); do
        if [[ $sub -gt $max_sub ]]; then
            max_sub=$sub
        fi
    done
    
    echo $((max_sub + 1))
}

# Função para configurar subinterface
configure_subinterface() {
    local interface=$1
    local ip_cidr=$2
    local sub_num=$(get_next_subinterface "$interface")
    local sub_interface="${interface}.${sub_num}"
    
    print_info "Configurando subinterface: $sub_interface"
    
    # Criar subinterface
    ip link add link "$interface" name "$sub_interface" type vlan id "$sub_num"
    
    if [[ $? -ne 0 ]]; then
        print_error "Falha ao criar subinterface $sub_interface"
        return 1
    fi
    
    # Configurar IP na subinterface
    ip addr add "$ip_cidr" dev "$sub_interface"
    
    if [[ $? -ne 0 ]]; then
        print_error "Falha ao configurar IP $ip_cidr na subinterface $sub_interface"
        ip link delete "$sub_interface"
        return 1
    fi
    
    # Ativar subinterface
    ip link set "$sub_interface" up
    
    if [[ $? -ne 0 ]]; then
        print_error "Falha ao ativar subinterface $sub_interface"
        return 1
    fi
    
    print_success "Subinterface $sub_interface configurada com IP $ip_cidr"
    
    # Tornar configuração persistente
    make_persistent "$sub_interface" "$ip_cidr" "$interface" "$sub_num"
    
    echo "$sub_interface"
}

# Função para tornar configuração persistente
make_persistent() {
    local sub_interface=$1
    local ip_cidr=$2
    local parent_interface=$3
    local vlan_id=$4
    
    print_info "Tornando configuração persistente..."
    
    # Para sistemas com netplan (Ubuntu 18.04+)
    if command -v netplan &> /dev/null; then
        local netplan_file="/etc/netplan/99-subinterface-${sub_interface}.yaml"
        cat > "$netplan_file" << EOF
network:
  version: 2
  vlans:
    ${sub_interface}:
      id: ${vlan_id}
      link: ${parent_interface}
      addresses:
        - ${ip_cidr}
EOF
        print_success "Configuração netplan criada em: $netplan_file"
        
    # Para sistemas com interfaces (Debian/Ubuntu mais antigos)
    elif [[ -f /etc/network/interfaces ]]; then
        echo "" >> /etc/network/interfaces
        echo "# Subinterface ${sub_interface}" >> /etc/network/interfaces
        echo "auto ${sub_interface}" >> /etc/network/interfaces
        echo "iface ${sub_interface} inet static" >> /etc/network/interfaces
        echo "    address ${ip_cidr}" >> /etc/network/interfaces
        echo "    vlan-raw-device ${parent_interface}" >> /etc/network/interfaces
        print_success "Configuração adicionada em /etc/network/interfaces"
    fi
}

# Função para instalar e configurar FRR
install_frr() {
    print_info "Atualizando sistema e instalando dependências..."
    apt update && apt install sudo curl lsb-release -y

    print_info "Adicionando chave GPG do FRR..."
    curl -s https://deb.frrouting.org/frr/keys.gpg | sudo tee /usr/share/keyrings/frrouting.gpg > /dev/null

    print_info "Adicionando repositório do FRR..."
    FRRVER="frr-stable"
    echo deb '[signed-by=/usr/share/keyrings/frrouting.gpg]' https://deb.frrouting.org/frr \
         $(lsb_release -s -c) $FRRVER | sudo tee -a /etc/apt/sources.list.d/frr.list

    print_info "Instalando FRR..."
    sudo apt update
    sudo apt upgrade -y && sudo apt install frr frr-pythontools -y

    print_success "FRR instalado com sucesso!"
}

# Função para configurar FRR
configure_frr() {
    local subnet_to_announce=$1
    
    print_info "Habilitando daemon BGP..."
    sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons

    print_info "Gerando configuração do FRR..."
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
ip prefix-list RR-IPV4-OUT seq 10 permit 172.64.0.0/20 le 32
ip prefix-list RR-IPV4-OUT seq 15 permit ${subnet_to_announce} le 32
ip prefix-list BLOQUEIA-TUDO seq 5 deny any
!
route-map SET-COMMUNITY permit 10
 set community 262713:1010
exit
!
EOF

    print_info "Reiniciando serviço FRR..."
    systemctl restart frr
    
    if [[ $? -eq 0 ]]; then
        print_success "FRR configurado e reiniciado com sucesso!"
    else
        print_error "Falha ao reiniciar o FRR"
        return 1
    fi
}

# Função principal
main() {
    echo
    print_info "=== Script de Instalação e Configuração FRR com Subinterfaces ==="
    echo
    
    # Verificar se é root
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script deve ser executado como root"
        exit 1
    fi
    
    # Selecionar interface
    select_interface
    
    # Solicitar IP para subinterface
    while true; do
        echo
        read -p "Digite o IP/CIDR para a subinterface (ex: 192.168.1.10/24): " ip_input
        
        if validate_ip "$ip_input"; then
            # Verificar se tem CIDR, se não, adicionar /24 como padrão
            if [[ ! "$ip_input" =~ "/" ]]; then
                ip_input="${ip_input}/24"
                print_warning "CIDR não especificado, usando /24 como padrão: $ip_input"
            fi
            break
        else
            print_error "IP inválido. Use o formato: IP/CIDR (ex: 192.168.1.10/24)"
        fi
    done
    
    # Configurar subinterface
    sub_interface=$(configure_subinterface "$selected_interface" "$ip_input")
    
    if [[ $? -ne 0 ]]; then
        print_error "Falha ao configurar subinterface"
        exit 1
    fi
    
    # Extrair subnet para anúncio BGP
    subnet=$(echo "$ip_input" | cut -d'/' -f1 | cut -d'.' -f1-3).0/$(echo "$ip_input" | cut -d'/' -f2)
    
    # Perguntar se quer instalar FRR
    echo
    read -p "Deseja instalar e configurar o FRR? (s/n): " install_frr_choice
    
    if [[ "$install_frr_choice" =~ ^[SsYy]$ ]]; then
        install_frr
        configure_frr "$subnet"
        
        echo
        print_success "=== Configuração Completa ==="
        print_info "Subinterface criada: $sub_interface"
        print_info "IP configurado: $ip_input"
        print_info "Subnet para anúncio BGP: $subnet"
        print_info "FRR instalado e configurado"
        echo
        print_info "Para verificar o status:"
        echo "  - ip addr show $sub_interface"
        echo "  - vtysh -c 'show ip bgp summary'"
        echo "  - vtysh -c 'show ip route'"
    else
        echo
        print_success "=== Configuração de Subinterface Completa ==="
        print_info "Subinterface criada: $sub_interface"
        print_info "IP configurado: $ip_input"
        echo
        print_info "Para verificar: ip addr show $sub_interface"
    fi
    
    echo
}

# Executar função principal
main "$@"
