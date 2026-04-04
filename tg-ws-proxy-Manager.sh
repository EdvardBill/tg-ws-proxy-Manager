#!/bin/sh

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
RED="\033[1;31m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"
NC="\033[0m"
GIT_URL="https://github.com/Flowseal/tg-ws-proxy/archive/refs/heads/master.zip"
ENTWARE_PREFIX="/opt"
INIT_DIR="$ENTWARE_PREFIX/etc/init.d"
BIN_DIR="$ENTWARE_PREFIX/bin"
LIB_DIR="$ENTWARE_PREFIX/lib"
ROOT_DIR="$ENTWARE_PREFIX/root"
mkdir -p "$ROOT_DIR"
if [ ! -d "$ENTWARE_PREFIX" ]; then
    echo -e "\n${RED}Entware не установлен.${NC}"
    echo -e "${YELLOW}Установите Entware перед использованием этого скрипта.${NC}"
    exit 1
fi
OPKG="$ENTWARE_PREFIX/bin/opkg"
UPDATE="$OPKG update"
INSTALL="$OPKG install --force-reinstall"
LAN_IP=$(nvram get lan_ipaddr 2>/dev/null | cut -d/ -f1)
[ -z "$LAN_IP" ] && LAN_IP="192.168.1.1"
PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }
install_tg_ws() {
    if [ "$(df -m "$ENTWARE_PREFIX" 2>/dev/null | awk 'NR==2 {print $4+0}')" -lt 40 ]; then
        echo -e "\n${RED}Недостаточно свободного места в $ENTWARE_PREFIX.${NC}"
        PAUSE
        return 1
    fi
    echo -e "\n${MAGENTA}Обновляем пакеты Entware.${NC}"
    $UPDATE
    echo -e "${MAGENTA}Устанавливаем необходимые пакеты.${NC}"
    $INSTALL python3 python3-pip python3-psutil python3-cryptography unzip cron
    echo -e "${MAGENTA}Скачиваем и распаковываем tg-ws-proxy.${NC}"
    rm -rf "$ROOT_DIR/tg-ws-proxy"
    cd "$ROOT_DIR" || exit 1
    if ! wget -O tg-ws-proxy.zip "$GIT_URL"; then
        echo -e "\n${RED}Ошибка скачивания архива.${NC}\n"
        PAUSE
        return 1
    fi
    if ! unzip tg-ws-proxy.zip >/dev/null 2>&1; then
        echo -e "\n${RED}Ошибка распаковки.${NC}\n"
        PAUSE
        return 1
    fi
    mv tg-ws-proxy-main tg-ws-proxy
    rm -f tg-ws-proxy.zip
    cd "$ROOT_DIR/tg-ws-proxy" || exit 1
    echo -e "${MAGENTA}Устанавливаем tg-ws-proxy.${NC}"
    pip install --root-user-action=ignore --no-deps --disable-pip-version-check --timeout 2 --retries 1 -e .
    cat << 'EOF' > "$INIT_DIR/S99tg-ws-proxy"
#!/bin/sh

ENABLED=yes
PROCS=tg-ws-proxy
ARGS="--host 0.0.0.0"
DESC="tg-ws-proxy"
PIDFILE="/var/run/tg-ws-proxy.pid"

start() {
    echo "Starting $DESC..."
    start-stop-daemon -S -b -m -p $PIDFILE -x /opt/bin/$PROCS -- $ARGS
    sleep 2
    if pidof $PROCS >/dev/null 2>&1; then
        echo "$DESC started successfully"
    else
        echo "Failed to start $DESC"
        return 1
    fi
}

stop() {
    echo "Stopping $DESC..."
    start-stop-daemon -K -p $PIDFILE
    rm -f $PIDFILE
    sleep 1
}

restart() {
    stop
    sleep 2
    start
}

check() {
    if pidof $PROCS >/dev/null 2>&1; then
        echo "$DESC is running"
        return 0
    else
        echo "$DESC is not running"
        return 1
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    check) check ;;
    *) echo "Usage: $0 {start|stop|restart|check}" ;;
esac
EOF
    
    chmod +x "$INIT_DIR/S99tg-ws-proxy"
    mkdir -p "$ENTWARE_PREFIX/var/log"
    cat << 'EOF' > "$ENTWARE_PREFIX/bin/tg-ws-proxy-monitor.sh"
#!/bin/sh
LOG_FILE="/opt/var/log/tg-ws-proxy-monitor.log"
MAX_LOG_SIZE=1048576

if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null) -gt $MAX_LOG_SIZE ]; then
    mv "$LOG_FILE" "$LOG_FILE.old"
fi

if ! pidof tg-ws-proxy >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): tg-ws-proxy не запущен, перезапускаем..." >> "$LOG_FILE"
    /opt/etc/init.d/S99tg-ws-proxy start >> "$LOG_FILE" 2>&1
fi
EOF
    chmod +x "$ENTWARE_PREFIX/bin/tg-ws-proxy-monitor.sh"
    mkdir -p "$ENTWARE_PREFIX/var/spool/cron/crontabs"
    sed -i '/tg-ws-proxy-monitor/d' "$ENTWARE_PREFIX/var/spool/cron/crontabs/root" 2>/dev/null
    echo "*/1 * * * * $ENTWARE_PREFIX/bin/tg-ws-proxy-monitor.sh" >> "$ENTWARE_PREFIX/var/spool/cron/crontabs/root"
    if ! pidof crond >/dev/null 2>&1; then
        crond -c "$ENTWARE_PREFIX/var/spool/cron/crontabs"
    fi
    "$INIT_DIR/S99tg-ws-proxy" start
    echo -e "\n${GREEN}Установка завершена.${NC}"
    echo -e "${YELLOW}Сервис установлен в: $INIT_DIR/S99tg-ws-proxy${NC}"
    echo -e "${YELLOW}Настроен автоматический мониторинг (проверка каждую минуту)${NC}"
    echo -e "${YELLOW}Лог мониторинга: $ENTWARE_PREFIX/var/log/tg-ws-proxy-monitor.log${NC}"
    echo -e "${YELLOW}Для управления используйте: $INIT_DIR/S99tg-ws-proxy {start|stop|restart|check}${NC}"
    PAUSE
}
delete_tg_ws() {
    echo -e "\n${MAGENTA}Удаляем tg-ws-proxy.${NC}"
    echo -e "${CYAN}Удаляем задачу из cron.${NC}"
    sed -i '/tg-ws-proxy-monitor/d' "$ENTWARE_PREFIX/var/spool/cron/crontabs/root" 2>/dev/null
    echo -e "${CYAN}Останавливаем сервис.${NC}"
    if [ -f "$INIT_DIR/S99tg-ws-proxy" ]; then
        "$INIT_DIR/S99tg-ws-proxy" stop >/dev/null 2>&1
    fi
    echo -e "${CYAN}Удаляем init.d скрипт.${NC}"
    rm -f "$INIT_DIR/S99tg-ws-proxy" >/dev/null 2>&1
    echo -e "${CYAN}Удаляем tg-ws-proxy.${NC}"
    rm -rf "$ROOT_DIR/tg-ws-proxy" >/dev/null 2>&1
    echo -e "${CYAN}Удаляем пакеты Python.${NC}"
    python3 -m pip uninstall -y tg-ws-proxy >/dev/null 2>&1
    pip uninstall -y tg-ws-proxy >/dev/null 2>&1
    echo -e "${CYAN}Удаляем установленные пакеты.${NC}"
    $OPKG remove --autoremove python3 python3-pip python3-psutil python3-cryptography unzip >/dev/null 2>&1
    echo -e "${CYAN}Очищаем временные файлы.${NC}"
    rm -rf "$ROOT_DIR/.cache/pip" >/dev/null 2>&1
    rm -rf "$ROOT_DIR/.local/lib/python3"* >/dev/null 2>&1
    rm -f "$BIN_DIR/tg-ws-proxy"* >/dev/null 2>&1
    echo -e "\n${GREEN}Удаление завершено.${NC}"
    PAUSE
}
menu() {
    clear
    echo -e "╔═════════════════════════════════╗"
    echo -e "║ ${BLUE}tg-ws-proxy Manager для Padavan${NC} ║"
    echo -e "╚═════════════════════════════════╝"
    echo -e "                          ${DGRAY}by save55${NC}\n"
    if pidof "tg-ws-proxy" >/dev/null 2>&1; then
        echo -e "${YELLOW}Статус tg-ws-proxy:  ${GREEN}ЗАПУЩЕН${NC}"
        PORT=$(netstat -lnpt 2>/dev/null | grep tg-ws-proxy | awk '{print $4}' | cut -d: -f2 | head -1)
        echo -e "${YELLOW}Адрес SOCKS5: ${NC}$LAN_IP:${PORT:-1080}"
    elif [ -d "$ROOT_DIR/tg-ws-proxy" ] || python3 -m pip show tg-ws-proxy >/dev/null 2>&1; then
        echo -e "${YELLOW}Статус tg-ws-proxy: ${RED}НЕ ЗАПУЩЕН${NC}"
        echo -e "${CYAN}Для запуска выполните: $INIT_DIR/S99tg-ws-proxy start${NC}"
    else
        echo -e "${YELLOW}Статус tg-ws-proxy: ${RED}НЕ УСТАНОВЛЕН${NC}"
    fi
    echo -e "\n${CYAN}1) ${GREEN}Установить${NC}"
    echo -e "${CYAN}2) ${GREEN}Удалить${NC}"
    echo -e "${CYAN}3) ${GREEN}Запустить${NC}"
    echo -e "${CYAN}4) ${GREEN}Остановить${NC}"
    echo -e "${CYAN}5) ${GREEN}Проверить статус${NC}"
    echo -e "${CYAN}Enter) ${GREEN}Выход${NC}\n"
    echo -en "${YELLOW}Выберите пункт: ${NC}"
    read choice
    case "$choice" in 
        1) install_tg_ws ;;
        2) delete_tg_ws ;;
        3) 
            if [ -f "$INIT_DIR/S99tg-ws-proxy" ]; then
                "$INIT_DIR/S99tg-ws-proxy" start
            else
                echo -e "${RED}Сервис не установлен.${NC}"
                PAUSE
            fi
            ;;
        4)
            if [ -f "$INIT_DIR/S99tg-ws-proxy" ]; then
                "$INIT_DIR/S99tg-ws-proxy" stop
            else
                echo -e "${RED}Сервис не установлен.${NC}"
                PAUSE
            fi
            ;;
        5)
            if [ -f "$INIT_DIR/S99tg-ws-proxy" ]; then
                "$INIT_DIR/S99tg-ws-proxy" check
            else
                echo -e "${RED}Сервис не установлен.${NC}"
            fi
            PAUSE
            ;;
        *) echo; exit 0 ;;
    esac
}
while true; do menu; done
