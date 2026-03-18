#!/bin/sh

# Убираем мусорные символы Windows, если они есть
sed -i 's/\r$//' "$0" 2>/dev/null

echo "=== НАСТРОЙКА ZABORONA HELP ==="
echo "1. Standart (Обычный список)"
echo "2. Big Routes (Европа, расширенный список)"

# Цикл выбора с защитой от пустых нажатий
while true; do
    printf "Введите 1 или 2 и нажмите Enter: "
    read -r choice
    [ -z "$choice" ] && continue
    if [ "$choice" = "1" ]; then
        SERVER="srv0.vpn.zaboronahelp.pp.ua"
        echo "Выбран: Standart"
        break
    elif [ "$choice" = "2" ]; then
        SERVER="srv0bigroutes.vpn.zaboronahelp.pp.ua"
        echo "Выбран: Big Routes"
        break
    else
        echo "Ошибка: введите только цифру 1 или 2"
    fi
done

# Определение пакетного менеджера
if command -v apk >/dev/null; then
    PKG_MGR="apk add"
    opkg_update="apk update"
else
    PKG_MGR="opkg install"
    opkg_update="opkg update"
fi

echo "--- Установка компонентов ---"
$opkg_update
$PKG_MGR openvpn-openssl luci-app-openvpn luci-i18n-openvpn-ru libustream-openssl ca-bundle ca-certificates

mkdir -p /etc/openvpn
echo "--- Загрузка сертификатов ---"
wget --no-check-certificate -q "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

echo "--- Настройка сети и VPN ---"
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

echo "--- Настройка Firewall (nftables) ---"
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

echo "--- Перезапуск сервисов ---"
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
/etc/init.d/dnsmasq restart

echo "--- ОЖИДАНИЕ (20 сек) ---"
echo "Загружаем маршруты, пожалуйста подождите..."
sleep 20

# Проверка IP интерфейса
TUN_IP=$(ifconfig tun0 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)

if [ -n "$TUN_IP" ]; then
    echo "✅ СТАТУС: Туннель поднят! IP: $TUN_IP"
    echo "--- Проверка доступа к заблокированным ресурсам ---"
    # Пробуем пингануть сам сервер VPN (он всегда отвечает внутри туннеля)
    if ping -c 2 10.224.0.1 > /dev/null 2>&1; then
        echo "✅ СВЯЗЬ: Пакеты успешно ходят через Zaborona"
    else
        echo "❌ ВНИМАНИЕ: Пинг до шлюза VPN не прошел. Проверьте MTU/Firewall."
    fi
else
    echo "❌ ОШИБКА: tun0 не получил адрес. Посмотрите logread | grep openvpn"
fi
