#!/bin/bash

# Server Manager Pro - Version 2.1
# Auteur: Lefranc Jérémy
# Licence: MIT

# Configuration globale
VERSION="2.1"
CONFIG_DIR="/etc/server-manager"
LOGFILE="${CONFIG_DIR}/server_manager.log"
CONFIG_FILE="${CONFIG_DIR}/config.json"
KEYS_DIR="${CONFIG_DIR}/keys"
CRON_DIR="${CONFIG_DIR}/cron"
REPORTS_DIR="${CONFIG_DIR}/reports"
NOTIFICATION_CONFIG="${CONFIG_DIR}/notifications.json"
SSL_DIR="${CONFIG_DIR}/ssl"
SSL_KEY="${SSL_DIR}/private.key"
SSL_CERT="${SSL_DIR}/certificate.crt"
WEB_PORT=8443
TIMEOUT=30
MAX_RETRIES=3
MONITOR_INTERVAL=300
TEMP_THRESHOLD=75
SUBNET="192.168.1.0/24"

# Codes de couleur
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
BOLD='\e[1m'
NC='\e[0m'

# Vérification des dépendances
check_dependencies() {
    local deps=("nmap" "ipmitool" "jq" "curl" "openssl" "python3")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Dépendances manquantes : ${missing[*]}${NC}"
        echo "Installation avec : sudo apt-get install ${missing[*]}"
        exit 1
    fi
}

# Initialisation de l'environnement
init_environment() {
    local dirs=("$CONFIG_DIR" "$KEYS_DIR" "$CRON_DIR" "$REPORTS_DIR" "$SSL_DIR")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
        fi
    done

    # Fichiers de configuration initiaux
    [ ! -f "$CONFIG_FILE" ] && echo '{"servers":{},"users":{},"groups":{}}' > "$CONFIG_FILE"
    [ ! -f "$NOTIFICATION_CONFIG" ] && echo '{"email":{"enabled":false}}' > "$NOTIFICATION_CONFIG"

    # Génération du certificat SSL auto-signé
    if [ ! -f "$SSL_CERT" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$SSL_KEY" -out "$SSL_CERT" \
            -subj "/C=FR/ST=Paris/L=Paris/O=Server Manager/CN=localhost" 2>/dev/null
    fi
}

# Journalisation avancée
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    
    echo -e "$log_entry" >> "$LOGFILE"
    
    # Rotation des logs (10MB)
    if [ $(stat -c%s "$LOGFILE") -gt 10485760 ]; then
        mv "$LOGFILE" "${LOGFILE}.1"
        gzip "${LOGFILE}.1"
    fi
}

# Fonction de validation d'adresse IP
validate_ip() {
    local ip=$1
    [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && return 0 || return 1
}

# Gestion sécurisée des entrées utilisateur
secure_read() {
    local prompt=$1
    local var_name=$2
    local is_password=$3

    while true; do
        read -p "$prompt" "$var_name"
        if [ "$is_password" = true ]; then
            [ -n "${!var_name}" ] && break
        else
            validate_ip "${!var_name}" && break
            echo -e "${RED}Adresse IP invalide!${NC}"
        fi
    done
}

# Scanner le réseau pour interfaces de gestion
scan_network() {
    log "INFO" "Lancement du scan réseau sur $SUBNET"
    echo -e "${BLUE}Recherche d'interfaces de gestion...${NC}"
    
    local results=$(nmap -p 443,623 --open -sV "$SUBNET" | grep -i -E 'ilo|idrac|ipmi' | awk '{print $2}')
    
    if [ -n "$results" ]; then
        echo -e "${GREEN}Interfaces détectées :${NC}"
        printf "%s\n" "$results" | nl
        log "INFO" "Interfaces trouvées : $results"
    else
        echo -e "${YELLOW}Aucune interface détectée${NC}"
        log "INFO" "Aucune interface trouvée"
    fi
}

# Exécuter une commande IPMI avec gestion d'erreur
run_ipmi_command() {
    local server=$1
    local username=$2
    local password=$3
    local command=$4
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        local output=$(ipmitool -I lanplus -H "$server" -U "$username" -P "$password" "$command" 2>&1)
        local status=$?
        
        if [ $status -eq 0 ]; then
            echo "$output"
            return 0
        fi
        
        ((retries++))
        sleep 1
    done
    
    log "ERROR" "Échec commande IPMI: $command sur $server - $output"
    echo "$output"
    return 1
}

# Gestion des serveurs
manage_server() {
    local action=$1
    local server username password
    
    echo -e "${BLUE}Action sélectionnée : ${action^}${NC}"
    
    secure_read "Adresse IP du serveur: " server false
    read -p "Nom d'utilisateur IPMI: " username
    read -sp "Mot de passe IPMI: " password
    echo

    local command_result
    case "$action" in
        start)
            command_result=$(run_ipmi_command "$server" "$username" "$password" "power on")
            ;;
        stop)
            command_result=$(run_ipmi_command "$server" "$username" "$password" "power off")
            ;;
        restart)
            command_result=$(run_ipmi_command "$server" "$username" "$password" "power reset")
            ;;
        status)
            command_result=$(run_ipmi_command "$server" "$username" "$password" "power status")
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Succès: $command_result${NC}"
        log "SUCCESS" "Action $action sur $server réussie"
    else
        echo -e "${RED}Erreur: $command_result${NC}"
        log "ERROR" "Échec action $action sur $server"
    fi
}

# Surveillance de la température
monitor_temperature() {
    local server username password
    
    secure_read "Adresse IP du serveur: " server false
    read -p "Nom d'utilisateur IPMI: " username
    read -sp "Mot de passe IPMI: " password
    echo

    log "INFO" "Surveillance température sur $server"
    local temp_data=$(run_ipmi_command "$server" "$username" "$password" "sdr type temperature")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Températures actuelles :${NC}"
        echo "$temp_data"
        
        local critical_temp=$(echo "$temp_data" | grep -iE 'critical' | awk '{print $NF}' | sort -nr | head -1)
        if [ -n "$critical_temp" ] && [ "${critical_temp//[^0-9]/}" -ge $TEMP_THRESHOLD ]; then
            echo -e "${RED}ALERTE: Température critique détectée!${NC}"
            send_notification "Alerte Température" "Température critique sur $server: $critical_temp°C" "CRITICAL"
        fi
    else
        echo -e "${RED}Erreur: $temp_data${NC}"
    fi
}

# Interface web sécurisée
start_web_interface() {
    if pgrep -f "python3 -m http.server $WEB_PORT" >/dev/null; then
        echo -e "${YELLOW}Interface web déjà active${NC}"
        return
    fi

    nohup python3 -m http.server $WEB_PORT --directory "$CONFIG_DIR" --bind 127.0.0.1 >/dev/null 2>&1 &
    echo -e "${GREEN}Interface web disponible sur https://localhost:$WEB_PORT${NC}"
    log "INFO" "Interface web démarrée"
}

# Menu principal
show_menu() {
    clear
    echo -e "${BLUE}=== Server Manager Pro v$VERSION ===${NC}"
    echo -e "${BOLD}1. Scanner le réseau"
    echo "2. Démarrer serveur"
    echo "3. Arrêter serveur"
    echo "4. Redémarrer serveur"
    echo "5. État serveur"
    echo -e "\n${BOLD}6. Surveillance température"
    echo "7. Événements système"
    echo "8. Générer rapport"
    echo "9. Configurer notifications"
    echo "10. Interface web"
    echo -e "\n${RED}11. Quitter${NC}"
    echo -n "Choix [1-11]: "
}

# Point d'entrée principal
main() {
    # Vérification des privilèges root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Exécuter en tant que root!${NC}"
        exit 1
    fi

    check_dependencies
    init_environment

    while true; do
        show_menu
        read choice
        
        case $choice in
            1) scan_network ;;
            2) manage_server "start" ;;
            3) manage_server "stop" ;;
            4) manage_server "restart" ;;
            5) manage_server "status" ;;
            6) monitor_temperature ;;
            7) show_system_events ;;
            8) generate_report ;;
            9) configure_notifications ;;
            10) start_web_interface ;;
            11)
                echo -e "${GREEN}Arrêt du programme...${NC}"
                pkill -f "python3 -m http.server $WEB_PORT"
                exit 0
                ;;
            *)
                echo -e "${RED}Option invalide!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Démarrage
trap "echo -e '\n${RED}Interruption! Arrêt du programme...${NC}'; pkill -f 'python3 -m http.server $WEB_PORT'; exit 1" SIGINT
main "$@"
