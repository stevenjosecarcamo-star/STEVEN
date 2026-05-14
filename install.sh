}
        command -v ip6tables &>/dev/null && {
            ip6tables -F; ip6tables -X; ip6tables -Z
            ip6tables -t mangle -F; ip6tables -t mangle -X
            ip6tables -P INPUT ACCEPT; ip6tables -P FORWARD ACCEPT; ip6tables -P OUTPUT ACCEPT
        }
        command -v nft &>/dev/null && nft flush ruleset 2>/dev/null; true'

    status_row 1 "Puertos" "abiertos"
}

# ══════════════════════════════════════════════════════════════
#   DESCARGAR Y EJECUTAR BINARIO
# ══════════════════════════════════════════════════════════════
run_binary() {
    _titulo "DESCARGA E INSTALACION"

    local SUCCESS=0
    for i in 1 2 3; do
        spinner_run "Descargando binario (intento $i)" \
            bash -c "if command -v wget &>/dev/null; then
                wget -q --timeout=$WGET_TIMEOUT --tries=2 -O '$FILE' '$URL' && [ -s '$FILE' ]
            elif command -v curl &>/dev/null; then
                curl -fsSL --max-time $WGET_TIMEOUT --retry 2 -o '$FILE' '$URL' && [ -s '$FILE' ]
            else exit 1; fi"
        if [[ $? -eq 0 ]] && [[ -s "$FILE" ]]; then
            SUCCESS=1; break
        fi
        [[ $i -lt 3 ]] && sleep 2
    done

    if [[ "$SUCCESS" -ne 1 ]] || [[ ! -s "$FILE" ]]; then
        echo ""
        _error "No se pudo descargar el binario tras 3 intentos"
        echo ""; exit 1
    fi

    chmod +x "$FILE"
    status_row 1 "Binario" "descargado y listo"
    progress_bar "Preparando ejecucion" 2

    echo ""
    "$FILE"
    local EXIT_CODE=$?
    if [[ "$EXIT_CODE" -ne 0 ]]; then
        echo ""
        _error "El instalador terminó con código $EXIT_CODE"
        echo ""; exit "$EXIT_CODE"
    fi
}

# ══════════════════════════════════════════════════════════════
#   FLUJO PRINCIPAL
# ══════════════════════════════════════════════════════════════
detect_distro
anim_boot
check_root
check_lock

repair_sources
apt_update_upgrade
disable_firewall
run_binary

echo ""
echo -e "$LINEA"
_center "${G}${BOLD}✔  Instalación completada exitosamente${RESET}"
echo -e "$LINEA"
echo ""
