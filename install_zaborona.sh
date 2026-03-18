#!/bin/sh

# 1. Секция выбора сервера с принудительным чтением из терминала
# Мы открываем дескриптор 3 для терминала и читаем из него
exec 3<&0
exec 0</dev/tty

echo "=== ВЫБОР СЕРВЕРА ZABORONA HELP ==="
echo "1. Основные серверы (Standart)"
echo "2. Европа (Big Routes)"

while true; do
    printf "Введите 1 или 2 и нажмите Enter: "
    read -r choice
    case "$choice" in
        1)
            SERVER="srv0.vpn.zaboronahelp.pp.ua"
            echo "Выбран: Standart"
            break
            ;;
        2)
            SERVER="srv0bigroutes.vpn.zaboronahelp.pp.ua"
            echo "Выбран: Big Routes"
            break
            ;;
        *)
            echo "Ошибка: введите 1 или 2"
            ;;
    esac
done

# Возвращаем стандартный ввод обратно
exec 0<&3
exec 3<&-

# 2. Установка пакетов
if command -v apk >/dev/null; then
    PKG="apk add"
    apk update
else
    PKG="opkg install"
    opkg update
fi

echo "--- Установка компонентов ---"
$PKG openvpn-openssl luci-app-openvpn ca-bundle ca-certificates libustream-openssl

# 3. Загрузка сертификатов
mkdir -p /etc/openvpn
wget --no-check-certificate -q "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

# 4. Настройка UCI
echo "--- Конфигурация OpenWrt ---"
uci -q delete network.zaborona_help
uci set network.zaborona_help=interface
uci set network.zaborona_help.proto='none'
uci set network.zaborona_help.device='tun0'

uci -q delete openvpn.zaborona_help
uci set openvpn.zaborona_help=openvpn
uci set openvpn.zaborona_help.client='1'
uci set openvpn.zaborona_help.enabled='1'
uci set openvpn.zaborona_help.dev='tun0'
uci set openvpn.zaborona_help.proto='udp'
uci set openvpn.zaborona_help.remote="$SERVER 1194"
uci set openvpn.zaborona_help.resolv_retry='infinite'
uci set openvpn.zaborona_help.nobind='1'
uci set openvpn.zaborona_help.persist_key='1'
uci set openvpn.zaborona_help.persist_tun='1'
uci set openvpn.zaborona_help.remote_cert_tls='server'
uci set openvpn.zaborona_help.auth='sha1'
uci set openvpn.zaborona_help.cipher='AES-128-CBC'
uci set openvpn.zaborona_help.data_ciphers='AES-128-GCM:AES-128-CBC'
uci set openvpn.zaborona_help.ca='/etc/openvpn/ca.crt'
uci set openvpn.zaborona_help.cert='/etc/openvpn/zaborona-help.crt'
uci set openvpn.zaborona_help.key='/etc/openvpn/zaborona-help.key'
uci set openvpn.zaborona_help.verb='3'
uci set openvpn.zaborona_help.mssfix='1300' 
uci commit

# 5. Firewall и DNS
WAN_ZONE=$(uci show firewall | grep ".name='wan'" | cut -d'[' -f2 | cut -d']' -f1)
[ -z "$WAN_ZONE" ] && WAN_ZONE=1
uci add_list firewall.@zone[$WAN_ZONE].network='zaborona_help'
uci set firewall.@zone[$WAN_ZONE].mtu_fix='1'
uci commit firewall

uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='208.67.222.222'
uci add_list dhcp.@dnsmasq[0].server='208.67.220.220'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].strictorder='1'
uci commit dhcp

# 6. Перезапуск и проверка
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
/etc/init.d/dnsmasq restart

echo "--- Ожидание поднятия (30 сек) ---"
sleep 30

TUN_IP=$(ifconfig tun0 2>/dev/null | grep 'inet ' | awk '{print $2}' | sed 's/addr://')

if [ -n "$TUN_IP" ]; then
    echo "✅ УСПЕХ: IP туннеля $TUN_IP"
    ping -c 2 10.224.0.1
else
    echo "❌ ОШИБКА: tun0 не поднялся."
fi
