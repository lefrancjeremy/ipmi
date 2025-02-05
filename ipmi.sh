#!/bin/bash

# Définir le sous-réseau à scanner
SUBNET="192.168.1.0/24"
LOGFILE="server_management.log"

# Vérifier si les commandes nmap et ipmitool sont installées
if ! command -v nmap &> /dev/null || ! command -v ipmitool &> /dev/null; then
    echo -e "\e[31mErreur : Les commandes nmap et/ou ipmitool ne sont pas installées.\e[0m"
    exit 1
fi

# Fonction pour démarrer un serveur
start_server() {
    local SERVER=$1
    local USERNAME=$2
    local PASSWORD=$3
    
    # Essayer de démarrer le serveur
    ipmitool -I lanplus -H "$SERVER" -U "$USERNAME" -P "$PASSWORD" power on &>> "$LOGFILE"
    local RESULT=$?
    
    # Vérifier si la commande a réussi
    if [ $RESULT -eq 0 ]; then
        echo -e "\e[32mLe serveur à l'adresse IP $SERVER a été démarré avec succès.\e[0m"
    else
        echo -e "\e[31mÉchec de la connexion au serveur à l'adresse IP $SERVER.\e[0m" | tee -a "$LOGFILE"
        return 1
    fi
}

# Scanner le réseau pour détecter les iLO
scan_ilo() {
    echo "Scanning for iLO interfaces in the subnet $SUBNET..."
    ILO_ADDRESSES=$(nmap -p 443 --open -sV $SUBNET | grep -i "ilo" | awk '{print $2}')
    
    # Vérifier si des iLO ont été trouvés
    if [ -z "$ILO_ADDRESSES" ]; then
        echo -e "\e[33mAucune interface iLO trouvée dans le sous-réseau $SUBNET.\e[0m"
        return 1
    fi
    
    echo -e "\nInterfaces iLO détectées :"
    echo "$ILO_ADDRESSES" | nl
    return 0
}

# Afficher le menu
show_menu() {
    echo -e "\n=== Menu de gestion des serveurs ==="
    echo "1. Scanner le réseau pour détecter les iLO"
    echo "2. Démarrer un serveur"
    echo "3. Arrêter un serveur"
    echo "4. Redémarrer un serveur"
    echo "5. Vérifier l'état d'un serveur"
    echo "6. Quitter"
    echo -n "Choisissez une option [1-6]: "
}

# Arrêter un serveur
stop_server() {
    local SERVER=$1
    local USERNAME=$2
    local PASSWORD=$3
    
    ipmitool -I lanplus -H "$SERVER" -U "$USERNAME" -P "$PASSWORD" power off &>> "$LOGFILE"
    if [ $? -eq 0 ]; then
        echo -e "\e[32mLe serveur à l'adresse IP $SERVER a été arrêté avec succès.\e[0m"
    else
        echo -e "\e[31mÉchec de l'arrêt du serveur à l'adresse IP $SERVER.\e[0m" | tee -a "$LOGFILE"
        return 1
    fi
}

# Redémarrer un serveur
restart_server() {
    local SERVER=$1
    local USERNAME=$2
    local PASSWORD=$3
    
    stop_server "$SERVER" "$USERNAME" "$PASSWORD"
    sleep 5  # Attendre 5 secondes avant de redémarrer
    start_server "$SERVER" "$USERNAME" "$PASSWORD"
}

# Vérifier l'état d'un serveur
check_server_status() {
    local SERVER=$1
    local USERNAME=$2
    local PASSWORD=$3
    
    STATUS=$(ipmitool -I lanplus -H "$SERVER" -U "$USERNAME" -P "$PASSWORD" power status 2>> "$LOGFILE")
    if [ $? -eq 0 ]; then
        echo -e "\e[32mÉtat du serveur $SERVER : $STATUS\e[0m"
    else
        echo -e "\e[31mImpossible de récupérer l'état du serveur $SERVER.\e[0m" | tee -a "$LOGFILE"
        return 1
    fi
}

# Boucle principale
while true; do
    show_menu
    read -r CHOICE

    case $CHOICE in
        1)
            scan_ilo
            ;;
        2)
            echo -n "Adresse IP du serveur: "
            read -r SERVER
            echo -n "Nom d'utilisateur: "
            read -r USERNAME
            echo -n "Mot de passe: "
            read -rs PASSWORD
            echo
            start_server "$SERVER" "$USERNAME" "$PASSWORD"
            ;;
        3)
            echo -n "Adresse IP du serveur: "
            read -r SERVER
            echo -n "Nom d'utilisateur: "
            read -r USERNAME
            echo -n "Mot de passe: "
            read -rs PASSWORD
            echo
            stop_server "$SERVER" "$USERNAME" "$PASSWORD"
            ;;
        4)
            echo -n "Adresse IP du serveur: "
            read -r SERVER
            echo -n "Nom d'utilisateur: "
            read -r USERNAME
            echo -n "Mot de passe: "
            read -rs PASSWORD
            echo
            restart_server "$SERVER" "$USERNAME" "$PASSWORD"
            ;;
        5)
            echo -n "Adresse IP du serveur: "
            read -r SERVER
            echo -n "Nom d'utilisateur: "
            read -r USERNAME
            echo -n "Mot de passe: "
            read -rs PASSWORD
            echo
            check_server_status "$SERVER" "$USERNAME" "$PASSWORD"
            ;;
        6)
            echo "Au revoir!"
            exit 0
            ;;
        *)
            echo -e "\e[31mOption invalide\e[0m"
            ;;
    esac
done
