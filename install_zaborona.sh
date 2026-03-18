#!/bin/sh

# Убираем возможные невидимые символы Windows, если они попали в файл
sed -i 's/\r$//' "$0"

echo "=== ВЫБОР СЕРВЕРА ZABORONA ==="
echo "1 - Standart (Обычный список)"
echo "2 - Big Routes (Европа, много маршрутов)"
echo "Пожалуйста, введите цифру и нажмите ENTER:"

# Используем цикл, пока не будет введено 1 или 2
while true; do
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
            echo "Ошибка! Введите только 1 или 2:"
            ;;
    esac
done

# Дальше идет основная часть установки
if command -v apk >/dev/null
then
    PKG_MGR="apk add"
    opkg_update="apk update"
else
    PKG_MGR="opkg install"
    opkg_update="opkg update"
fi

echo "--- Установка пакетов ---"
$opkg_update
$PKG_MGR openvpn-openssl luci-app-openvpn luci-i18n-openvpn-ru libustream-openssl ca-bundle ca-certificates

mkdir -p /etc/openvpn
echo "--- Загрузка сертификатов ---"
wget --no-check-certificate "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

echo "--- Настройка Network ---"
uci -q delete network.zaborona_help
uci set network.zaborona_help=interface
uci set network.zaborona_help.proto='none'
uci set network.zaborona_help.device='tun0'
uci commit network

echo "--- Настройка OpenVPN ---"
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
uci commit openvpn

echo "--- Настройка Firewall ---"
WAN_ZONE=$(uci show firewall | grep ".name='wan'" | cut -d'[' -f2 | cut -d']' -f1)
[ -z "$WAN_ZONE" ] && WAN_ZONE=1

uci add_list firewall.@zone[$WAN_ZONE].network='zaborona_help'
uci set firewall.@zone[$WAN_ZONE].mtu_fix='1'
uci commit firewall

echo "--- Настройка DNS ---"
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='208.67.222.222'
uci add_list dhcp.@dnsmasq[0].server='208.67.220.220'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].strictorder='1'
uci commit dhcp

echo "--- Рестарт сервисов ---"
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
/etc/init.d/dnsmasq restart

echo "--- Ожидание 15 сек ---"
sleep 15

TUN_IP=$(ifconfig tun0 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)

if [ -n "$TUN_IP" ]
then
    echo "STATUS: OK. IP: $TUN_IP"
    ping -I tun0 -c 3 8.8.8.8
else
    echo "STATUS: FAIL. tun0 not found"
fi
