#!/bin/sh

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
RED="\033[1;31m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"
NC="\033[0m"
GIT_URL="https://github.com/valnesfjord/tg-ws-proxy-rs/archive/refs/heads/master.zip"
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
    if ! opkg list-installed | grep -q cron; then
        $INSTALL cron
    fi
    if ! opkg list-installed | grep -q unzip; then
        $INSTALL unzip
    fi
    echo -e "${MAGENTA}Скачиваем и распаковываем tg-ws-proxy-rs.${NC}"
    rm -rf "$ROOT_DIR/tg-ws-proxy-rs"
    cd "$ROOT_DIR" || exit 1
    if ! wget -O tg-ws-proxy-rs.zip "$GIT_URL"; then
        echo -e "\n${RED}Ошибка скачивания архива.${NC}\n"
        PAUSE
        return 1
    fi
    if ! unzip tg-ws-proxy-rs.zip >/dev/null 2>&1; then
        echo -e "\n${RED}Ошибка распаковки.${NC}\n"
        PAUSE
        return 1
    fi
    mv tg-ws-proxy-rs-main tg-ws-proxy-rs
    rm -f tg-ws-proxy-rs.zip
    cd "$ROOT_DIR/tg-ws-proxy-rs" || exit 1
    if [ -f "$ROOT_DIR/tg-ws-proxy-rs/target/release/tg-ws-proxy-rs" ]; then
        cp "$ROOT_DIR/tg-ws-proxy-rs/target/release/tg-ws-proxy-rs" "$BIN_DIR/"
    elif [ -f "$ROOT_DIR/tg-ws-proxy-rs/tg-ws-proxy-rs" ]; then
        cp "$ROOT_DIR/tg-ws-proxy-rs/tg-ws-proxy-rs" "$BIN_DIR/"
    else
        echo -e "\n${RED}Бинарный файл tg-ws-proxy-rs не найден в архиве.${NC}"
        echo -e "${YELLOW}Возможно, требуется предварительная компиляция.${NC}"
        PAUSE
        return 1
    fi
    chmod +x "$BIN_DIR/tg-ws-proxy-rs"
    cat << 'EOF' > "$INIT_DIR/S99tg-ws-proxy-rs"
#!/bin/sh

ENABLED=yes
PROCS=tg-ws-proxy-rs
ARGS="--host 0.0.0.0"
DESC="tg-ws-proxy-rs"
PIDFILE="/var/run/tg-ws-proxy-rs.pid"

start() {
    echo "Starting $DESC..."
    start-stop-daemon -S -b -m -p $PIDFILE -x /opt/bin/$PROCS -- $ARGS
    sleep 2
    if pidof $PROCS >/dev/null 2>&1; then
        echo "$DESC started successfully"
        return 0
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
    
    chmod +x "$INIT_DIR/S99tg-ws-proxy-rs"
    mkdir -p "$ENTWARE_PREFIX/var/log"
    chmod 755 "$ENTWARE_PREFIX/var/log"
    
    cat << 'EOF' > "$ENTWARE_PREFIX/bin/tg-ws-proxy-rs-monitor.sh"
#!/bin/sh

LOG_DIR="/opt/var/log"
LOG_FILE="$LOG_DIR/tg-ws-proxy-rs-monitor.log"
MAX_LOG_SIZE=1048576  # 1MB

if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"
fi

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || wc -c < "$LOG_FILE" 2>/dev/null)
    if [ -n "$LOG_SIZE" ] && [ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
    fi
fi

if ! pidof tg-ws-proxy-rs >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): tg-ws-proxy-rs не запущен, перезапускаем..." >> "$LOG_FILE"
    /opt/etc/init.d/S99tg-ws-proxy-rs start >> "$LOG_FILE" 2>&1
fi
EOF
    
    chmod +x "$ENTWARE_PREFIX/bin/tg-ws-proxy-rs-monitor.sh"
    mkdir -p "$ENTWARE_PREFIX/var/spool/cron/crontabs"
    killall crond 2>/dev/null
    sed -i '/tg-ws-proxy-rs-monitor/d' "$ENTWARE_PREFIX/var/spool/cron/crontabs/root" 2>/dev/null
    echo "*/1 * * * * $ENTWARE_PREFIX/bin/tg-ws-proxy-rs-monitor.sh" >> "$ENTWARE_PREFIX/var/spool/cron/crontabs/root"
    chmod 600 "$ENTWARE_PREFIX/var/spool/cron/crontabs/root"
    crond -c "$ENTWARE_PREFIX/var/spool/cron/crontabs"
    "$INIT_DIR/S99tg-ws-proxy-rs" start 
    echo -e "\n${GREEN}Установка завершена.${NC}"
    echo -e "${YELLOW}Сервис установлен в: $INIT_DIR/S99tg-ws-proxy-rs${NC}"
    echo -e "${YELLOW}Бинарный файл: $BIN_DIR/tg-ws-proxy-rs${NC}"
    echo -e "${YELLOW}Настроен автоматический мониторинг (проверка каждую минуту)${NC}"
    echo -e "${YELLOW}Лог мониторинга: $ENTWARE_PREFIX/var/log/tg-ws-proxy-rs-monitor.log${NC}"
    if [ -f "$ENTWARE_PREFIX/var/log/tg-ws-proxy-rs-monitor.log" ]; then
        echo -e "${GREEN}Лог-файл успешно создан${NC}"
    else
        echo -e "${RED}ВНИМАНИЕ: Лог-файл не создан. Проверьте права.${NC}"
        touch "$ENTWARE_PREFIX/var/log/tg-ws-proxy-rs-monitor.log"
        chmod 644 "$ENTWARE_PREFIX/var/log/tg-ws-proxy-rs-monitor.log"
    fi
    echo -e "${YELLOW}Для управления используйте: $INIT_DIR/S99tg-ws-proxy-rs {start|stop|restart|check}${NC}"
    PAUSE
}
delete_tg_ws() {
    echo -e "\n${MAGENTA}Удаляем tg-ws-proxy-rs.${NC}"
    echo -e "${CYAN}Удаляем задачу из cron.${NC}"
    sed -i '/tg-ws-proxy-rs-monitor/d' "$ENTWARE_PREFIX/var/spool/cron/crontabs/root" 2>/dev/null
    echo -e "${CYAN}Останавливаем сервис.${NC}"
    if [ -f "$INIT_DIR/S99tg-ws-proxy-rs" ]; then
        "$INIT_DIR/S99tg-ws-proxy-rs" stop >/dev/null 2>&1
    fi
    echo -e "${CYAN}Удаляем init.d скрипт.${NC}"
    rm -f "$INIT_DIR/S99tg-ws-proxy-rs" >/dev/null 2>&1
    echo -e "${CYAN}Удаляем бинарный файл.${NC}"
    rm -f "$BIN_DIR/tg-ws-proxy-rs" >/dev/null 2>&1
    echo -e "${CYAN}Удаляем исходники.${NC}"
    rm -rf "$ROOT_DIR/tg-ws-proxy-rs" >/dev/null 2>&1
    echo -e "${CYAN}Очищаем временные файлы.${NC}"
    rm -f "$ROOT_DIR/tg-ws-proxy-rs.zip" >/dev/null 2>&1
    echo -e "\n${GREEN}Удаление завершено.${NC}"
    PAUSE
}
check_monitor_status() {
    echo -e "\n${CYAN}=== Диагностика мониторинга ===${NC}"
    if [ -d "$ENTWARE_PREFIX/var/log" ]; then
        echo -e "${GREEN}✓ Директория логов существует: $ENTWARE_PREFIX/var/log${NC}"
        ls -la "$ENTWARE_PREFIX/var/log" | grep tg-ws-proxy-rs
    else
        echo -e "${RED}✗ Директория логов НЕ существует${NC}"
        mkdir -p "$ENTWARE_PREFIX/var/log"
        echo -e "${YELLOW}Директория создана${NC}"
    fi
    if [ -f "$ENTWARE_PREFIX/bin/tg-ws-proxy-rs-monitor.sh" ]; then
        echo -e "${GREEN}✓ Скрипт мониторинга существует${NC}"
        chmod +x "$ENTWARE_PREFIX/bin/tg-ws-proxy-rs-monitor.sh"
    else
        echo -e "${RED}✗ Скрипт мониторинга НЕ существует${NC}"
    fi
    if [ -f "$ENTWARE_PREFIX/var/spool/cron/crontabs/root" ]; then
        echo -e "${GREEN}✓ Cron задача существует${NC}"
        cat "$ENTWARE_PREFIX/var/spool/cron/crontabs/root" | grep tg-ws-proxy-rs
    else
        echo -e "${RED}✗ Cron задача НЕ существует${NC}"
    fi
    if pidof crond >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Cron запущен (PID: $(pidof crond))${NC}"
    else
        echo -e "${RED}✗ Cron НЕ запущен${NC}"
        crond -c "$ENTWARE_PREFIX/var/spool/cron/crontabs"
        echo -e "${YELLOW}Cron запущен${NC}"
    fi
    echo -e "\n${YELLOW}Запускаем мониторинг вручную...${NC}"
    sh "$ENTWARE_PREFIX/bin/tg-ws-proxy-rs-monitor.sh"
    if [ -f "$ENTWARE_PREFIX/var/log/tg-ws-proxy-rs-monitor.log" ]; then
        echo -e "${GREEN}✓ Лог-файл создан успешно${NC}"
        echo -e "${CYAN}Содержимое лога:${NC}"
        cat "$ENTWARE_PREFIX/var/log/tg-ws-proxy-rs-monitor.log"
    else
        echo -e "${RED}✗ Лог-файл НЕ создался${NC}"
        touch "$ENTWARE_PREFIX/var/log/tg-ws-proxy-rs-monitor.log"
        chmod 644 "$ENTWARE_PREFIX/var/log/tg-ws-proxy-rs-monitor.log"
        echo -e "${YELLOW}Лог создан вручную${NC}"
    fi
    PAUSE
}

menu() {
    clear
    echo -e "╔══════════════════════════════════════╗"
    echo -e "║ ${BLUE}tg-ws-proxy-rs Manager для Padavan${NC} ║"
    echo -e "╚══════════════════════════════════════╝"
    echo -e "                          ${DGRAY}by save55${NC}\n"
    if pidof "tg-ws-proxy-rs" >/dev/null 2>&1; then
        echo -e "${YELLOW}Статус tg-ws-proxy-rs:  ${GREEN}ЗАПУЩЕН${NC}"
        PORT=$(netstat -lnpt 2>/dev/null | grep tg-ws-proxy-rs | awk '{print $4}' | cut -d: -f2 | head -1)
        echo -e "${YELLOW}Адрес SOCKS5: ${NC}$LAN_IP:${PORT:-1080}"
    elif [ -d "$ROOT_DIR/tg-ws-proxy-rs" ] || [ -f "$BIN_DIR/tg-ws-proxy-rs" ]; then
        echo -e "${YELLOW}Статус tg-ws-proxy-rs: ${RED}НЕ ЗАПУЩЕН${NC}"
        echo -e "${CYAN}Для запуска выполните: $INIT_DIR/S99tg-ws-proxy-rs start${NC}"
    else
        echo -e "${YELLOW}Статус tg-ws-proxy-rs: ${RED}НЕ УСТАНОВЛЕН${NC}"
    fi
    echo -e "\n${CYAN}1) ${GREEN}Установить${NC}"
    echo -e "${CYAN}2) ${GREEN}Удалить${NC}"
    echo -e "${CYAN}3) ${GREEN}Запустить${NC}"
    echo -e "${CYAN}4) ${GREEN}Остановить${NC}"
    echo -e "${CYAN}5) ${GREEN}Проверить статус${NC}"
    echo -e "${CYAN}6) ${GREEN}Диагностика мониторинга${NC}"
    echo -e "${CYAN}Enter) ${GREEN}Выход${NC}\n"
    echo -en "${YELLOW}Выберите пункт: ${NC}"
    read choice
    case "$choice" in 
        1) install_tg_ws ;;
        2) delete_tg_ws ;;
        3) 
            if [ -f "$INIT_DIR/S99tg-ws-proxy-rs" ]; then
                "$INIT_DIR/S99tg-ws-proxy-rs" start
            else
                echo -e "${RED}Сервис не установлен.${NC}"
                PAUSE
            fi
            ;;
        4)
            if [ -f "$INIT_DIR/S99tg-ws-proxy-rs" ]; then
                "$INIT_DIR/S99tg-ws-proxy-rs" stop
            else
                echo -e "${RED}Сервис не установлен.${NC}"
                PAUSE
            fi
            ;;
        5)
            if [ -f "$INIT_DIR/S99tg-ws-proxy-rs" ]; then
                "$INIT_DIR/S99tg-ws-proxy-rs" check
            else
                echo -e "${RED}Сервис не установлен.${NC}"
            fi
            PAUSE
            ;;
        6) check_monitor_status ;;
        *) echo; exit 0 ;;
    esac
}

while true; do menu; done
