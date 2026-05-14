#!/bin/bash

# ══════════════════════════════════════════════════════════════
#   DARKZSAID VPS MANAGER - INSTALLER
#   Ubuntu / Debian
# ══════════════════════════════════════════════════════════════

set -o pipefail

# URL del archivo principal que se descargará y ejecutará
URL="https://raw.githubusercontent.com/stevenjosecarcamo-star/STEVEN/main/carrasco"

# Ruta temporal donde se guardará el archivo descargado
FILE="/tmp/darkzsaid_main"

# Tiempo máximo de descarga
WGET_TIMEOUT="25"

# ══════════════════════════════════════════════════════════════
#   COLORES
# ══════════════════════════════════════════════════════════════

RESET="\e[0m"
BOLD="\e[1m"

R="\e[31m"
G="\e[32m"
Y="\e[33m"
C="\e[36m"
W="\e[37m"

LINEA="${C}══════════════════════════════════════════════════════════════${RESET}"

# ══════════════════════════════════════════════════════════════
#   FUNCIONES VISUALES
# ══════════════════════════════════════════════════════════════

_center() {
    local text="$1"
    local width=60
    local len=${#text}
    local spaces=$(( (width - len) / 2 ))

    if [[ $spaces -lt 0 ]]; then
        spaces=0
    fi

    printf "%*s%s\n" "$spaces" "" "$text"
}

_titulo() {
    clear
    echo -e "$LINEA"
    _center "${BOLD}${C}⚔️ DARKZSAID VPS MANAGER ⚔️${RESET}"
    echo -e "$LINEA"
    echo ""
    echo -e "${BOLD}${W}$1${RESET}"
    echo ""
}

_info() {
    echo -e "${C}[INFO]${RESET} $1"
}

_ok() {
    echo -e "${G}[OK]${RESET} $1"
}

_warn() {
    echo -e "${Y}[AVISO]${RESET} $1"
}

_error() {
    echo -e "${R}[ERROR]${RESET} $1"
}

status_row() {
    local estado="$1"
    local nombre="$2"
    local detalle="$3"

    if [[ "$estado" == "1" ]]; then
        echo -e " ${G}✔${RESET} ${BOLD}$nombre:${RESET} $detalle"
    else
        echo -e " ${R}✘${RESET} ${BOLD}$nombre:${RESET} $detalle"
    fi
}

progress_bar() {
    local texto="$1"
    local segundos="$2"

    echo -ne "${C}$texto${RESET} "

    for ((i=1; i<=segundos; i++)); do
        echo -ne "▓"
        sleep 1
    done

    echo -e " ${G}OK${RESET}"
}

spinner_run() {
    local mensaje="$1"
    shift

    echo -ne "${C}$mensaje${RESET} "

    "$@" >/tmp/darkzsaid_install.log 2>&1 &
    local pid=$!

    local spin='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % 4 ))
        echo -ne "\r${C}$mensaje${RESET} ${spin:$i:1}"
        sleep 0.2
    done

    wait "$pid"
    local code=$?

    if [[ "$code" -eq 0 ]]; then
        echo -e "\r${C}$mensaje${RESET} ${G}✔${RESET}"
    else
        echo -e "\r${C}$mensaje${RESET} ${R}✘${RESET}"
    fi

    return "$code"
}

# ══════════════════════════════════════════════════════════════
#   VALIDACIONES
# ══════════════════════════════════════════════════════════════

detect_distro() {
    _titulo "VERIFICANDO SISTEMA"

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO="$ID"
        VERSION="$VERSION_ID"
    else
        _error "No se pudo detectar la distribución."
        exit 1
    fi

    case "$DISTRO" in
        ubuntu|debian)
            status_row 1 "Sistema" "$PRETTY_NAME"
            ;;
        *)
            status_row 0 "Sistema" "$PRETTY_NAME"
            _error "Este instalador solo es compatible con Ubuntu o Debian."
            exit 1
            ;;
    esac
}

anim_boot() {
    echo ""
    progress_bar "Iniciando instalador" 2
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        _error "Debes ejecutar este instalador como root."
        echo ""
        echo "Usa:"
        echo "sudo bash install.sh"
        echo ""
        exit 1
    fi

    status_row 1 "Permisos" "root detectado"
}

check_lock() {
    _titulo "VERIFICANDO APT"

    local locks=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
    )

    for lock in "${locks[@]}"; do
        if fuser "$lock" >/dev/null 2>&1; then
            _warn "APT está ocupado con: $lock"
            _warn "Esperando unos segundos..."
            sleep 8
        fi
    done

    status_row 1 "APT" "sin bloqueos graves"
}

# ══════════════════════════════════════════════════════════════
#   PAQUETES Y DEPENDENCIAS
# ══════════════════════════════════════════════════════════════

repair_sources() {
    _titulo "REPARANDO PAQUETES"

    spinner_run "Reparando paquetes pendientes" bash -c "
        dpkg --configure -a &&
        apt-get install -f -y
    "

    if [[ "$?" -ne 0 ]]; then
        _warn "No se pudo reparar todo automáticamente, pero se continuará."
    fi

    status_row 1 "Paquetes" "verificados"
}

apt_update_upgrade() {
    _titulo "INSTALANDO DEPENDENCIAS"

    spinner_run "Actualizando lista de paquetes" bash -c "
        apt-get update -y
    "

    if [[ "$?" -ne 0 ]]; then
        _error "No se pudo ejecutar apt update."
        echo ""
        cat /tmp/darkzsaid_install.log 2>/dev/null
        echo ""
        exit 1
    fi

    spinner_run "Instalando herramientas necesarias" bash -c "
        apt-get install -y wget curl ca-certificates gnupg lsb-release iptables
    "

    if [[ "$?" -ne 0 ]]; then
        _error "No se pudieron instalar las dependencias."
        echo ""
        cat /tmp/darkzsaid_install.log 2>/dev/null
        echo ""
        exit 1
    fi

    status_row 1 "Dependencias" "instaladas"
}

# ══════════════════════════════════════════════════════════════
#   CONFIGURAR PUERTOS
# ══════════════════════════════════════════════════════════════

disable_firewall() {
    _titulo "CONFIGURANDO PUERTOS"

    _warn "Se desactivarán reglas de firewall para evitar bloqueos durante la instalación."
    sleep 2

    bash -c '
        command -v ufw >/dev/null 2>&1 && ufw --force disable >/dev/null 2>&1 || true

        command -v systemctl >/dev/null 2>&1 && {
            systemctl stop firewalld >/dev/null 2>&1 || true
            systemctl disable firewalld >/dev/null 2>&1 || true
        }

        command -v iptables >/dev/null 2>&1 && {
            iptables -F || true
            iptables -X || true
            iptables -Z || true

            iptables -t nat -F || true
            iptables -t nat -X || true

            iptables -t mangle -F || true
            iptables -t mangle -X || true

            iptables -P INPUT ACCEPT || true
            iptables -P FORWARD ACCEPT || true
            iptables -P OUTPUT ACCEPT || true
        }

        command -v ip6tables >/dev/null 2>&1 && {
            ip6tables -F || true
            ip6tables -X || true
            ip6tables -Z || true

            ip6tables -t mangle -F || true
            ip6tables -t mangle -X || true

            ip6tables -P INPUT ACCEPT || true
            ip6tables -P FORWARD ACCEPT || true
            ip6tables -P OUTPUT ACCEPT || true
        }

        command -v nft >/dev/null 2>&1 && nft flush ruleset >/dev/null 2>&1 || true
    '

    status_row 1 "Puertos" "abiertos"
}

# ══════════════════════════════════════════════════════════════
#   DESCARGAR Y EJECUTAR ARCHIVO PRINCIPAL
# ══════════════════════════════════════════════════════════════

run_binary() {
    _titulo "DESCARGA E INSTALACIÓN"

    rm -f "$FILE"

    local SUCCESS=0

    for i in 1 2 3; do
        spinner_run "Descargando archivo principal intento $i" bash -c "
            if command -v wget >/dev/null 2>&1; then
                wget -q --timeout='$WGET_TIMEOUT' --tries=2 -O '$FILE' '$URL'
            elif command -v curl >/dev/null 2>&1; then
                curl -fsSL --max-time '$WGET_TIMEOUT' --retry 2 -o '$FILE' '$URL'
            else
                exit 1
            fi

            test -s '$FILE'
        "

        if [[ "$?" -eq 0 && -s "$FILE" ]]; then
            SUCCESS=1
            break
        fi

        if [[ "$i" -lt 3 ]]; then
            sleep 2
        fi
    done

    if [[ "$SUCCESS" -ne 1 || ! -s "$FILE" ]]; then
        echo ""
        _error "No se pudo descargar el archivo principal después de 3 intentos."
        echo ""
        cat /tmp/darkzsaid_install.log 2>/dev/null
        echo ""
        exit 1
    fi

    chmod +x "$FILE"

    status_row 1 "Archivo principal" "descargado y listo"
    progress_bar "Preparando ejecución" 2

    echo ""
    echo -e "$LINEA"
    _center "${G}${BOLD}INICIANDO INSTALADOR PRINCIPAL${RESET}"
    echo -e "$LINEA"
    echo ""

    "$FILE"
    local EXIT_CODE=$?

    if [[ "$EXIT_CODE" -ne 0 ]]; then
        echo ""
        _error "El instalador principal terminó con código $EXIT_CODE"
        echo ""
        exit "$EXIT_CODE"
    fi
}

clean_temp() {
    rm -f /tmp/darkzsaid_install.log >/dev/null 2>&1 || true
}

# ══════════════════════════════════════════════════════════════
#   FLUJO PRINCIPAL
# ══════════════════════════════════════════════════════════════

main() {
    detect_distro
    anim_boot
    check_root
    check_lock
    repair_sources
    apt_update_upgrade
    disable_firewall
    run_binary
    clean_temp

    echo ""
    echo -e "$LINEA"
    _center "${G}${BOLD}✔ INSTALACIÓN COMPLETADA EXITOSAMENTE${RESET}"
    echo -e "$LINEA"
    echo ""
}

main "$@"
