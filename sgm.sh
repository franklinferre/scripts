
#!/bin/bash

# ==================================================================================
# Sistema de Gestão de Máquina (SGM) - Versão 3.0
# Baseado em frr2.sh com expansões completas
# Funcionalidades: Docker, Rede, Sistema, Segurança, FRR, Manutenção
# Compatível: Debian/Ubuntu
# ==================================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Variáveis globais
SCRIPT_VERSION="3.0"
LOG_FILE="/var/log/sgm.log"

# ==================================================================================
# FUNÇÕES UTILITÁRIAS
# ==================================================================================

# Função para logging
log_action() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# Funções para imprimir mensagens coloridas
print_header() {
    echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${WHITE}                    Sistema de Gestão de Máquina v${SCRIPT_VERSION}                    ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_action "INFO: $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_action "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_action "WARNING: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_action "ERROR: $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
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

# Função para verificar se é root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script deve ser executado como root"
        exit 1
    fi
}

# Função para pausar
press_enter() {
    echo
    read -p "Pressione ENTER para continuar..."
    echo
}

# ==================================================================================
# MÓDULO SISTEMA
# ==================================================================================

system_update() {
    print_step "Atualizando sistema..."
    
    print_info "Atualizando lista de pacotes..."
    apt update
    
    print_info "Fazendo upgrade do sistema..."
    apt upgrade -y
    
    print_info "Fazendo dist-upgrade..."
    apt dist-upgrade -y
    
    print_info "Removendo pacotes órfãos..."
    apt autoremove -y
    
    print_info "Limpando cache do APT..."
    apt autoclean
    
    print_success "Sistema atualizado com sucesso!"
}

install_essential_packages() {
    print_step "Instalando pacotes essenciais..."
    
    local packages=(
        "curl" "wget" "vim" "nano" "htop" "tree" "unzip" "git"
        "net-tools" "dnsutils" "tcpdump" "iptables-persistent"
        "software-properties-common" "apt-transport-https" "ca-certificates"
        "gnupg" "lsb-release" "sudo" "ufw" "fail2ban"
    )
    
    for package in "${packages[@]}"; do
        print_info "Instalando $package..."
        apt install -y "$package"
    done
    
    print_success "Pacotes essenciais instalados!"
}

configure_timezone() {
    print_step "Configurando timezone..."
    
    echo "Timezones disponíveis:"
    echo "1) America/Sao_Paulo"
    echo "2) UTC"
    echo "3) America/New_York"
    echo "4) Europe/London"
    echo "5) Personalizado"
    
    read -p "Selecione o timezone (1-5): " tz_choice
    
    case $tz_choice in
        1) timedatectl set-timezone America/Sao_Paulo ;;
        2) timedatectl set-timezone UTC ;;
        3) timedatectl set-timezone America/New_York ;;
        4) timedatectl set-timezone Europe/London ;;
        5) 
            read -p "Digite o timezone (ex: America/Sao_Paulo): " custom_tz
            timedatectl set-timezone "$custom_tz"
            ;;
        *) print_warning "Opção inválida, mantendo timezone atual" ;;
    esac
    
    print_success "Timezone configurado: $(timedatectl show --property=Timezone --value)"
}

# ==================================================================================
# MÓDULO DOCKER
# ==================================================================================

install_docker() {
    print_step "Instalando Docker..."
    
    # Remover versões antigas
    print_info "Removendo versões antigas do Docker..."
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Adicionar repositório oficial
    print_info "Adicionando repositório oficial do Docker..."
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Instalar Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Configurar serviço
    systemctl enable docker
    systemctl start docker
    
    # Adicionar usuário ao grupo docker
    if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER"
        print_info "Usuário $SUDO_USER adicionado ao grupo docker"
    fi
    
    print_success "Docker instalado com sucesso!"
    print_info "Versão: $(docker --version)"
}

docker_cleanup() {
    print_step "Limpeza completa do Docker..."
    
    print_info "Parando todos os containers..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    print_info "Removendo containers parados..."
    docker container prune -f
    
    print_info "Removendo imagens não utilizadas..."
    docker image prune -af
    
    print_info "Removendo volumes órfãos..."
    docker volume prune -f
    
    print_info "Removendo redes não utilizadas..."
    docker network prune -f
    
    print_info "Limpeza completa do sistema Docker..."
    docker system prune -af --volumes
    
    print_success "Limpeza do Docker concluída!"
    print_info "Espaço liberado: $(docker system df)"
}

# ==================================================================================
# MÓDULO REDE
# ==================================================================================

list_network_interfaces() {
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|enp|eno|wlan|wlp)[0-9]' | sed 's/@.*//' | sort))
    echo "${interfaces[@]}"
}

select_interface() {
    print_info "Listando interfaces de rede disponíveis..."
    local interfaces=($(list_network_interfaces))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        print_error "Nenhuma interface de rede encontrada!"
        exit 1
    elif [[ ${#interfaces[@]} -eq 1 ]]; then
        selected_interface="${interfaces[0]}"
        print_info "Interface selecionada automaticamente: $selected_interface"
    else
        echo
        print_info "Interfaces disponíveis:"
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

configure_ip_subinterface() {
    print_step "Configuração de sub-IP em interface..."
    
    # Selecionar interface
    select_interface
    
    # Solicitar IP
    while true; do
        echo
        read -p "Digite o IP/CIDR para adicionar como sub-IP (ex: 172.64.0.4/32): " ip_input
        
        if validate_ip "$ip_input"; then
            # Verificar se tem CIDR, se não, adicionar /32 como padrão para IPs únicos
            if [[ ! "$ip_input" =~ "/" ]]; then
                ip_input="${ip_input}/32"
                print_warning "CIDR não especificado, usando /32 como padrão: $ip_input"
            fi
            break
        else
            print_error "IP inválido. Use o formato: IP/CIDR (ex: 172.64.0.4/32)"
        fi
    done
    
    # Extrair IP sem CIDR para iptables
    local ip_only=$(echo "$ip_input" | cut -d'/' -f1)
    
    print_info "Adicionando IP $ip_input como sub-IP na interface $selected_interface..."
    
    # Adicionar IP à interface (permitir múltiplos IPs)
    ip addr add "$ip_input" dev "$selected_interface" 2>/dev/null
    
    # Verificar resultado
    if [[ $? -eq 0 ]]; then
        print_success "IP $ip_input adicionado como sub-IP na interface $selected_interface"
    elif ip addr show "$selected_interface" | grep -q "$ip_input"; then
        print_warning "IP $ip_input já estava configurado na interface $selected_interface"
        print_info "Continuando com a configuração..."
    else
        print_error "Falha ao adicionar IP à interface"
        return 1
    fi
    
    # Configurar regra iptables SNAT
    print_info "Configurando regra iptables SNAT..."
    
    # Verificar se regra já existe
    if iptables -t nat -C POSTROUTING -o "$selected_interface" ! -d 10.128.0.0/10 -j SNAT --to-source "$ip_only" 2>/dev/null; then
        print_warning "Regra iptables SNAT já existe para $ip_only"
    else
        iptables -t nat -A POSTROUTING -o "$selected_interface" ! -d 10.128.0.0/10 -j SNAT --to-source "$ip_only"
        
        if [[ $? -eq 0 ]]; then
            print_success "Regra iptables SNAT configurada para $ip_only"
        else
            print_error "Falha ao configurar regra iptables"
            return 1
        fi
    fi
    
    # Salvar configuração do iptables
    print_info "Salvando configuração do iptables..."
    iptables-save > /etc/iptables/rules.v4
    
    # Tornar configuração de sub-IP persistente
    make_ip_persistent "$selected_interface" "$ip_input"
    
    print_success "Configuração de sub-IP completa!"
    print_info "Interface: $selected_interface"
    print_info "Sub-IP adicionado: $ip_input"
    print_info "SNAT configurado para: $ip_only"
}

make_ip_persistent() {
    local interface=$1
    local ip_cidr=$2
    
    print_info "Tornando configuração de sub-IP persistente..."
    
    # Para sistemas com netplan (Ubuntu 18.04+)
    if command -v netplan &> /dev/null; then
        local netplan_file="/etc/netplan/99-custom-ip-${interface}.yaml"
        
        # Verificar se já existe configuração para esta interface
        if [[ -f "$netplan_file" ]]; then
            print_info "Arquivo netplan já existe, adicionando IP à configuração existente..."
            
            # Verificar se IP já está no arquivo
            if grep -q "$ip_cidr" "$netplan_file"; then
                print_warning "IP $ip_cidr já está no arquivo netplan"
                return 0
            fi
            
            # Adicionar IP à lista existente
            sed -i "/addresses:/a\\        - ${ip_cidr}" "$netplan_file"
            print_success "IP $ip_cidr adicionado ao netplan existente"
        else
            # Criar novo arquivo preservando DHCP
            cat > "$netplan_file" << EOF
network:
  version: 2
  ethernets:
    ${interface}:
      dhcp4: true
      addresses:
        - ${ip_cidr}
EOF
            print_success "Configuração netplan criada em: $netplan_file"
        fi
        
    # Para sistemas com interfaces (Debian/Ubuntu mais antigos)
    elif [[ -f /etc/network/interfaces ]]; then
        # Verificar se já existe configuração para este IP
        if ! grep -q "$ip_cidr" /etc/network/interfaces; then
            echo "" >> /etc/network/interfaces
            echo "# Sub-IP adicional ${ip_cidr} em ${interface}" >> /etc/network/interfaces
            echo "post-up ip addr add ${ip_cidr} dev ${interface}" >> /etc/network/interfaces
            echo "pre-down ip addr del ${ip_cidr} dev ${interface}" >> /etc/network/interfaces
            print_success "Configuração adicionada em /etc/network/interfaces"
        else
            print_warning "Configuração já existe em /etc/network/interfaces"
        fi
    fi
}

configure_dns() {
    print_step "Configuração de DNS..."
    
    echo "Selecione a configuração de DNS:"
    echo "1) Google DNS (8.8.8.8, 8.8.4.4)"
    echo "2) Cloudflare DNS (1.1.1.1, 1.0.0.1)"
    echo "3) OpenDNS (208.67.222.222, 208.67.220.220)"
    echo "4) DNS personalizado"
    echo "5) Manter atual"
    
    read -p "Selecione uma opção (1-5): " dns_choice
    
    case $dns_choice in
        1)
            dns1="8.8.8.8"
            dns2="8.8.4.4"
            ;;
        2)
            dns1="1.1.1.1"
            dns2="1.0.0.1"
            ;;
        3)
            dns1="208.67.222.222"
            dns2="208.67.220.220"
            ;;
        4)
            read -p "Digite o DNS primário: " dns1
            read -p "Digite o DNS secundário: " dns2
            ;;
        5)
            print_info "Mantendo configuração atual de DNS"
            return 0
            ;;
        *)
            print_error "Opção inválida"
            return 1
            ;;
    esac
    
    # Backup do resolv.conf atual
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s)
    
    # Configurar novo DNS
    cat > /etc/resolv.conf << EOF
# DNS configurado pelo SGM
nameserver $dns1
nameserver $dns2
EOF
    
    print_success "DNS configurado:"
    print_info "Primário: $dns1"
    print_info "Secundário: $dns2"
    
    # Teste de conectividade
    print_info "Testando conectividade DNS..."
    if nslookup google.com >/dev/null 2>&1; then
        print_success "Teste de DNS bem-sucedido!"
    else
        print_warning "Falha no teste de DNS"
    fi
}

# Função para listar sub-IPs
list_sub_ips() {
    print_step "Listando sub-IPs configurados..."
    
    # Selecionar interface
    select_interface
    
    print_info "Sub-IPs configurados na interface $selected_interface:"
    echo
    
    # Listar todos os IPs da interface (exceto o principal)
    local ips=($(ip addr show "$selected_interface" | grep 'inet ' | awk '{print $2}' | grep -v '/24$' | grep -v '/16$' | grep -v '/8$'))
    
    if [[ ${#ips[@]} -eq 0 ]]; then
        print_warning "Nenhum sub-IP encontrado na interface $selected_interface"
        return 0
    fi
    
    for i in "${!ips[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} ${ips[i]}"
    done
    
    echo
    print_info "Total de sub-IPs: ${#ips[@]}"
    
    # Mostrar regras iptables relacionadas
    echo
    print_info "Regras iptables SNAT ativas para esta interface:"
    iptables -t nat -L POSTROUTING -n | grep "$selected_interface" | grep SNAT || echo "  Nenhuma regra SNAT encontrada"
}

# Função para remover sub-IP específico
remove_sub_ip() {
    print_step "Removendo sub-IP específico..."
    
    # Selecionar interface
    select_interface
    
    # Listar sub-IPs disponíveis
    local ips=($(ip addr show "$selected_interface" | grep 'inet ' | awk '{print $2}' | grep -v '/24$' | grep -v '/16$' | grep -v '/8$'))
    
    if [[ ${#ips[@]} -eq 0 ]]; then
        print_warning "Nenhum sub-IP encontrado na interface $selected_interface"
        return 0
    fi
    
    echo
    print_info "Sub-IPs disponíveis para remoção:"
    for i in "${!ips[@]}"; do
        echo "  $((i+1))) ${ips[i]}"
    done
    
    echo
    read -p "Selecione o sub-IP para remover (1-${#ips[@]}): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#ips[@]} ]]; then
        local selected_ip="${ips[$((choice-1))]}"
        local ip_only=$(echo "$selected_ip" | cut -d'/' -f1)
        
        echo
        print_warning "ATENÇÃO: Você está prestes a remover:"
        print_info "Interface: $selected_interface"
        print_info "Sub-IP: $selected_ip"
        print_info "Regra iptables SNAT para: $ip_only"
        echo
        
        read -p "Confirma a remoção? (s/n): " confirm
        if [[ "$confirm" =~ ^[SsYy]$ ]]; then
            
            # Remover IP da interface
            print_info "Removendo IP $selected_ip da interface $selected_interface..."
            ip addr del "$selected_ip" dev "$selected_interface"
            
            if [[ $? -eq 0 ]]; then
                print_success "IP $selected_ip removido da interface"
            else
                print_error "Falha ao remover IP da interface"
            fi
            
            # Remover regra iptables SNAT se existir
            print_info "Removendo regra iptables SNAT para $ip_only..."
            if iptables -t nat -C POSTROUTING -o "$selected_interface" ! -d 10.128.0.0/10 -j SNAT --to-source "$ip_only" 2>/dev/null; then
                iptables -t nat -D POSTROUTING -o "$selected_interface" ! -d 10.128.0.0/10 -j SNAT --to-source "$ip_only"
                
                if [[ $? -eq 0 ]]; then
                    print_success "Regra iptables SNAT removida para $ip_only"
                else
                    print_error "Falha ao remover regra iptables"
                fi
            else
                print_info "Nenhuma regra iptables SNAT encontrada para $ip_only"
            fi
            
            # Salvar configuração do iptables
            print_info "Salvando configuração do iptables..."
            iptables-save > /etc/iptables/rules.v4
            
            # Remover da configuração persistente
            remove_from_persistent_config "$selected_interface" "$selected_ip"
            
            print_success "Remoção completa!"
            
        else
            print_info "Remoção cancelada"
        fi
    else
        print_error "Seleção inválida"
    fi
}

# Função para remover da configuração persistente
remove_from_persistent_config() {
    local interface=$1
    local ip_cidr=$2
    
    print_info "Removendo da configuração persistente..."
    
    # Para sistemas com netplan
    local netplan_file="/etc/netplan/99-custom-ip-${interface}.yaml"
    if [[ -f "$netplan_file" ]]; then
        if grep -q "$ip_cidr" "$netplan_file"; then
            print_info "Removendo de $netplan_file..."
            sed -i "/$ip_cidr/d" "$netplan_file"
            # Se arquivo ficou vazio, remover
            if [[ $(grep -c "addresses:" "$netplan_file") -eq 0 ]] || [[ $(wc -l < "$netplan_file") -le 5 ]]; then
                rm -f "$netplan_file"
                print_info "Arquivo netplan removido (vazio)"
            fi
        fi
    fi
    
    # Para sistemas com interfaces
    if [[ -f /etc/network/interfaces ]]; then
        if grep -q "$ip_cidr" /etc/network/interfaces; then
            print_info "Removendo de /etc/network/interfaces..."
            # Remove as linhas relacionadas ao IP
            sed -i "/# Sub-IP adicional ${ip_cidr}/,+2d" /etc/network/interfaces
        fi
    fi
}

# Função para mostrar regras iptables ativas
show_iptables_snat() {
    print_step "Regras iptables SNAT ativas..."
    
    echo
    print_info "Regras SNAT na tabela NAT:"
    echo
    
    # Mostrar cabeçalho
    echo -e "${WHITE}TARGET     PROT OPT SOURCE        DESTINATION    EXTRAS${NC}"
    echo -e "${WHITE}================================================================${NC}"
    
    # Mostrar regras SNAT
    iptables -t nat -L POSTROUTING -n --line-numbers | grep SNAT | while read line; do
        echo -e "${CYAN}$line${NC}"
    done
    
    echo
    print_info "Para ver detalhes completos:"
    echo "  iptables -t nat -L POSTROUTING -n -v"
    
    echo
    print_info "Interfaces com sub-IPs:"
    ip addr show | grep -E "(^[0-9]+:|inet.*scope global)" | grep -A1 "scope global" | grep -B1 "/32" | grep -E "^[0-9]+" | awk '{print $2}' | cut -d':' -f1 | sort -u | while read iface; do
        local sub_count=$(ip addr show "$iface" | grep 'inet ' | grep '/32' | wc -l)
        if [[ $sub_count -gt 0 ]]; then
            echo -e "  ${GREEN}●${NC} $iface: $sub_count sub-IP(s)"
        fi
    done
}

# ==================================================================================
# MÓDULO SEGURANÇA
# ==================================================================================

configure_firewall() {
    print_step "Configuração de Firewall (UFW)..."
    
    print_info "Resetando configuração do UFW..."
    ufw --force reset
    
    print_info "Configurando políticas padrão..."
    ufw default deny incoming
    ufw default allow outgoing
    
    print_info "Permitindo SSH (porta 22)..."
    ufw allow ssh
    
    print_info "Permitindo HTTP (porta 80)..."
    ufw allow http
    
    print_info "Permitindo HTTPS (porta 443)..."
    ufw allow https
    
    # Perguntar sobre outras portas
    read -p "Deseja permitir outras portas? (s/n): " allow_other
    if [[ "$allow_other" =~ ^[SsYy]$ ]]; then
        while true; do
            read -p "Digite a porta (ou 'fim' para terminar): " port
            if [[ "$port" == "fim" ]]; then
                break
            elif [[ "$port" =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]; then
                ufw allow "$port"
                print_success "Porta $port liberada"
            else
                print_error "Porta inválida"
            fi
        done
    fi
    
    print_info "Ativando firewall..."
    ufw --force enable
    
    print_success "Firewall configurado e ativado!"
    ufw status verbose
}

configure_fail2ban() {
    print_step "Configuração do Fail2Ban..."
    
    # Instalar fail2ban se não estiver instalado
    if ! command -v fail2ban-server &> /dev/null; then
        print_info "Instalando Fail2Ban..."
        apt install -y fail2ban
    fi
    
    # Configurar jail local
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Banir por 1 hora
bantime = 3600

# Tempo de busca por tentativas (10 minutos)
findtime = 600

# Número máximo de tentativas
maxretry = 5

# Ignorar IPs locais
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[apache-auth]
enabled = true

[apache-badbots]
enabled = true

[apache-noscript]
enabled = true

[apache-overflows]
enabled = true
EOF
    
    print_info "Reiniciando serviço Fail2Ban..."
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    print_success "Fail2Ban configurado e ativado!"
    print_info "Status do Fail2Ban:"
    fail2ban-client status
}

configure_ssh() {
    print_step "Configuração do SSH..."
    
    # Backup da configuração atual
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%s)
    
    print_info "Configurando SSH com segurança aprimorada..."
    
    # Configurações de segurança
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#Protocol 2/Protocol 2/' /etc/ssh/sshd_config
    
    # Adicionar configurações extras se não existirem
    if ! grep -q "MaxAuthTries" /etc/ssh/sshd_config; then
        echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
    fi
    
    if ! grep -q "ClientAliveInterval" /etc/ssh/sshd_config; then
        echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
        echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config
    fi
    
    print_info "Testando configuração SSH..."
    if sshd -t; then
        print_success "Configuração SSH válida"
        print_info "Reiniciando serviço SSH..."
        systemctl restart ssh
        print_success "SSH reconfigurado com sucesso!"
    else
        print_error "Erro na configuração SSH. Restaurando backup..."
        cp /etc/ssh/sshd_config.backup.$(date +%s) /etc/ssh/sshd_config
        systemctl restart ssh
    fi
}

# ==================================================================================
# MÓDULO FRR
# ==================================================================================

install_frr() {
    print_step "Instalação do FRR..."
    
    print_info "Adicionando chave GPG do FRR..."
    curl -s https://deb.frrouting.org/frr/keys.gpg | tee /usr/share/keyrings/frrouting.gpg > /dev/null

    print_info "Adicionando repositório do FRR..."
    FRRVER="frr-stable"
    echo deb '[signed-by=/usr/share/keyrings/frrouting.gpg]' https://deb.frrouting.org/frr \
         $(lsb_release -s -c) $FRRVER | tee -a /etc/apt/sources.list.d/frr.list

    print_info "Instalando FRR..."
    apt update
    apt install -y frr frr-pythontools

    print_success "FRR instalado com sucesso!"
}

configure_frr() {
    print_step "Configuração do FRR..."
    
    # Solicitar subnet para anúncio BGP
    while true; do
        read -p "Digite a subnet para anúncio BGP (ex: 172.64.0.0/24): " subnet_input
        if validate_ip "$subnet_input"; then
            break
        else
            print_error "Subnet inválida. Use o formato: IP/CIDR"
        fi
    done
    
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
ip prefix-list RR-IPV4-OUT seq 15 permit ${subnet_input} le 32
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
        print_info "Subnet configurada para anúncio: $subnet_input"
    else
        print_error "Falha ao reiniciar o FRR"
        return 1
    fi
}

# ==================================================================================
# MÓDULO MANUTENÇÃO
# ==================================================================================

system_cleanup() {
    print_step "Limpeza completa do sistema..."
    
    print_info "Limpando cache do APT..."
    apt clean
    apt autoclean
    
    print_info "Removendo pacotes órfãos..."
    apt autoremove -y
    
    print_info "Limpando logs antigos (mais de 7 dias)..."
    journalctl --vacuum-time=7d
    find /var/log -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    
    print_info "Limpando arquivos temporários..."
    rm -rf /tmp/*
    rm -rf /var/tmp/*
    
    print_info "Limpando cache de usuários..."
    find /home -name ".cache" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Limpeza do Docker se estiver instalado
    if command -v docker &> /dev/null; then
        print_info "Limpando Docker..."
        docker system prune -f 2>/dev/null || true
    fi
    
    print_success "Limpeza do sistema concluída!"
    
    # Mostrar espaço em disco
    print_info "Espaço em disco após limpeza:"
    df -h /
}

show_system_info() {
    print_step "Informações do sistema..."
    
    echo
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                           INFORMAÇÕES DO SISTEMA                            ║${NC}"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    print_info "Sistema Operacional:"
    lsb_release -a 2>/dev/null | grep -E "(Description|Release)"
    
    echo
    print_info "Kernel:"
    uname -r
    
    echo
    print_info "Uptime:"
    uptime
    
    echo
    print_info "Uso de memória:"
    free -h
    
    echo
    print_info "Uso de disco:"
    df -h /
    
    echo
    print_info "Interfaces de rede:"
    ip addr show | grep -E "^[0-9]+:|inet " | grep -v 127.0.0.1
    
    echo
    print_info "Serviços ativos importantes:"
    for service in ssh docker frr fail2ban ufw; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} $service: ativo"
        else
            echo -e "  ${RED}●${NC} $service: inativo/não instalado"
        fi
    done
    
    echo
    if command -v docker &> /dev/null; then
        print_info "Containers Docker:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Nenhum container rodando"
    fi
    
    echo
}

# ==================================================================================
# MENU PRINCIPAL
# ==================================================================================

show_menu() {
    clear
    print_header
    
    echo -e "${WHITE}Selecione uma opção:${NC}"
    echo
    echo -e "${CYAN} 1)${NC}  🔄 Atualizar sistema (update/upgrade)"
    echo -e "${CYAN} 2)${NC}  📦 Instalar pacotes essenciais"
    echo -e "${CYAN} 3)${NC}  🕒 Configurar timezone"
    echo
    echo -e "${CYAN} 4)${NC}  🐳 Instalar Docker"
    echo -e "${CYAN} 5)${NC}  🧹 Limpeza do Docker"
    echo
    echo -e "${CYAN} 6)${NC}  🌐 Adicionar sub-IP em interface (+ iptables)"
    echo -e "${CYAN} 7)${NC}  📋 Listar sub-IPs configurados"
    echo -e "${CYAN} 8)${NC}  ❌ Remover sub-IP específico"
    echo -e "${CYAN} 9)${NC}  🔍 Ver regras iptables SNAT"
    echo -e "${CYAN}10)${NC}  🔍 Configurar DNS"
    echo
    echo -e "${CYAN}11)${NC}  🔒 Configurar Firewall (UFW)"
    echo -e "${CYAN}12)${NC}  🛡️  Configurar Fail2Ban"
    echo -e "${CYAN}13)${NC}  🔑 Configurar SSH"
    echo
    echo -e "${CYAN}14)${NC}  📡 Instalar FRR"
    echo -e "${CYAN}15)${NC}  ⚙️  Configurar FRR/BGP"
    echo
    echo -e "${CYAN}16)${NC}  🧹 Limpeza completa do sistema"
    echo -e "${CYAN}17)${NC}  📊 Informações do sistema"
    echo
    echo -e "${CYAN}18)${NC}  🚀 Configuração completa (recomendado)"
    echo
    echo -e "${CYAN} 0)${NC}  ❌ Sair"
    echo
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

complete_setup() {
    print_step "Iniciando configuração completa do sistema..."
    
    echo
    print_warning "Esta opção irá:"
    echo "• Atualizar o sistema"
    echo "• Instalar pacotes essenciais"
    echo "• Instalar Docker"
    echo "• Configurar Firewall"
    echo "• Configurar Fail2Ban"
    echo "• Configurar SSH"
    echo "• Instalar FRR"
    echo
    
    read -p "Confirma a configuração completa? (s/n): " confirm
    if [[ ! "$confirm" =~ ^[SsYy]$ ]]; then
        print_info "Configuração cancelada"
        return 0
    fi
    
    # Executar configurações
    system_update
    press_enter
    
    install_essential_packages
    press_enter
    
    install_docker
    press_enter
    
    configure_firewall
    press_enter
    
    configure_fail2ban
    press_enter
    
    configure_ssh
    press_enter
    
    install_frr
    press_enter
    
    print_success "═══════════════════════════════════════════════════════════════════════════════"
    print_success "                    CONFIGURAÇÃO COMPLETA FINALIZADA!                         "
    print_success "═══════════════════════════════════════════════════════════════════════════════"
    
    echo
    print_info "Próximos passos recomendados:"
    echo "• Adicionar sub-IP na interface (opção 6)"
    echo "• Listar sub-IPs configurados (opção 7)"
    echo "• Configurar FRR/BGP (opção 15)"
    echo "• Configurar DNS se necessário (opção 10)"
    echo
    
    press_enter
}

# ==================================================================================
# FUNÇÃO PRINCIPAL
# ==================================================================================

main() {
    # Verificar se é root
    check_root
    
    # Criar arquivo de log se não existir
    touch "$LOG_FILE"
    log_action "SGM v${SCRIPT_VERSION} iniciado"
    
    while true; do
        show_menu
        read -p "Digite sua opção: " option
        
        case $option in
            1)
                system_update
                press_enter
                ;;
            2)
                install_essential_packages
                press_enter
                ;;
            3)
                configure_timezone
                press_enter
                ;;
            4)
                install_docker
                press_enter
                ;;
            5)
                docker_cleanup
                press_enter
                ;;
            6)
                configure_ip_subinterface
                press_enter
                ;;
            7)
                list_sub_ips
                press_enter
                ;;
            8)
                remove_sub_ip
                press_enter
                ;;
            9)
                show_iptables_snat
                press_enter
                ;;
            10)
                configure_dns
                press_enter
                ;;
            11)
                configure_firewall
                press_enter
                ;;
            12)
                configure_fail2ban
                press_enter
                ;;
            13)
                configure_ssh
                press_enter
                ;;
            14)
                install_frr
                press_enter
                ;;
            15)
                configure_frr
                press_enter
                ;;
            16)
                system_cleanup
                press_enter
                ;;
            17)
                show_system_info
                press_enter
                ;;
            18)
                complete_setup
                ;;
            0)
                print_info "Saindo do SGM..."
                log_action "SGM finalizado"
                exit 0
                ;;
            *)
                print_error "Opção inválida!"
                sleep 2
                ;;
        esac
    done
}

# ==================================================================================
# EXECUÇÃO
# ==================================================================================

# Executar função principal
main "$@" 
