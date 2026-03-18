#!/bin/sh

# 1. Блок выбора сервера (устойчивый к конвейеру)
echo "=== ВЫБОР СЕРВЕРА ZABORONA HELP ==="
echo "1. Основные серверы (Standart)"
echo "2. Европа (Big Routes)"

# Пытаемся принудительно открыть терминал для ввода
for tty in /dev/tty /dev/console /proc/self/fd/0; do
    [ -c "$tty" ] && TERMINAL="$tty" && break
done

while true; do
    printf "Введите 1 или 2 и нажмите Enter: "
    # Читаем напрямую из найденного терминала
    read -r choice < "$TERMINAL"
    
    case "$choice" in
        1) SERVER="srv0.vpn.zaboronahelp.pp.ua"; break ;;
        2) SERVER="srv0bigroutes.vpn.zaboronahelp.pp.ua"; break ;;
        *) echo "Ошибка! Введите только 1 или 2." ;;
    esac
done

# 2. Установка (автоматика для 25.12)
if command -v apk >/dev/null; then
    apk update && apk add openvpn-openssl luci-app-openvpn ca-bundle ca-certificates libustream-openssl
else
    opkg update && opkg install openvpn-openssl luci-app-openvpn ca-bundle ca-certificates libustream-openssl
fi

# 3. Настройка (UCI)
mkdir -p /etc/openvpn
wget --no-check-certificate -q "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

# Применяем конфигурацию
uci -q batch <<EOC
delete network.zaborona_help
set network.zaborona_help=interface
set network.zaborona_help.proto='none'
set network.zaborona_help.device='tun0'
delete openvpn.zaborona_help
set openvpn.zaborona_help=openvpn
set openvpn.zaborona_help.client='1'
set openvpn.zaborona_help.enabled='1'
set openvpn.zaborona_help.dev='tun0'
set openvpn.zaborona_help.proto='udp'
set openvpn.zaborona_help.remote='$SERVER 1194'
set openvpn.zaborona_help.resolv_retry='infinite'
set openvpn.zaborona_help.nobind='1'
set openvpn.zaborona_help.persist_key='1'
set openvpn.zaborona_help.persist_tun='1'
set openvpn.zaborona_help.remote_cert_tls='server'
set openvpn.zaborona_help.auth='sha1'
set openvpn.zaborona_help.cipher='AES-128-CBC'
set openvpn.zaborona_help.data_ciphers='AES-128-GCM:AES-128-CBC'
set openvpn.zaborona_help.ca='/etc/openvpn/ca.crt'
set openvpn.zaborona_help.cert='/etc/openvpn/zaborona-help.crt'
set openvpn.zaborona_help.key='/etc/openvpn/zaborona-help.key'
set openvpn.zaborona_help.verb='3'
set openvpn.zaborona_help.mssfix='1300'
commit
EOC

# Настройка Firewall (поиск зоны WAN)
WAN_ZONE=$(uci show firewall | grep ".name='wan'" | cut -d'[' -f2 | cut -d']' -f1)
[ -z "$WAN_ZONE" ] && WAN_ZONE=1
uci add_list firewall.@zone[$WAN_ZONE].network='zaborona_help'
uci set firewall.@zone[$WAN_ZONE].mtu_fix='1'
uci commit firewall

# DNS
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='208.67.222.222'
uci add_list dhcp.@dnsmasq[0].server='208.67.220.220'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].strictorder='1'
uci commit dhcp

/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
/etc/init.d/dnsmasq restart

echo "--- Ждем 30 секунд (загрузка маршрутов на Mango) ---"
sleep 30

# Проверка
TUN_IP=$(ifconfig tun0 2>/dev/null | grep 'inet ' | awk '{print $2}' | sed 's/addr://')
if [ -n "$TUN_IP" ]; then
    echo "✅ ОК! IP: $TUN_IP"
    ping -c 2 10.224.0.1
else
    echo "❌ Ошибка: туннель не поднялся."
fi
