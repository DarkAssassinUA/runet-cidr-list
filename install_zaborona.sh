cat << 'EOF' > /root/setup_vpn.sh
#!/bin/sh
sed -i 's/\r$//' "$0"

echo "=== ВЫБОР СЕРВЕРА ZABORONA ==="
echo "1 - Standart (Обычный)"
echo "2 - Big Routes (Европа)"

# Очищаем буфер перед чтением
while read -t 1 -n 10000; do :; done

while true; do
    printf "Введите 1 или 2 и нажмите Enter: "
    read choice
    case "$choice" in
        1) SERVER="srv0.vpn.zaboronahelp.pp.ua"; break ;;
        2) SERVER="srv0bigroutes.vpn.zaboronahelp.pp.ua"; break ;;
        *) echo "Ошибка! Жду 1 или 2." ;;
    esac
done

if command -v apk >/dev/null; then
    PKG="apk add"
    UP="apk update"
else
    PKG="opkg install"
    UP="opkg update"
fi

$UP
$PKG openvpn-openssl luci-app-openvpn luci-i18n-openvpn-ru libustream-openssl ca-bundle ca-certificates

mkdir -p /etc/openvpn
wget --no-check-certificate -q "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

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

/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
/etc/init.d/dnsmasq restart

echo "--- Ждем 25 секунд (загрузка маршрутов на Mango) ---"
sleep 25

TUN_IP=$(ifconfig tun0 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
if [ -z "$TUN_IP" ]; then TUN_IP=$(ifconfig tun0 2>/dev/null | grep 'inet ' | awk '{print $2}' | sed 's/addr://'); fi

if [ -n "$TUN_IP" ]; then
    echo "✅ ОК! IP получен: $TUN_IP"
    echo "Тестируем шлюз Zaborona (10.224.0.1)..."
    if ping -c 2 10.224.0.1 > /dev/null 2>&1; then
        echo "✅ СВЯЗЬ ЕСТЬ! Все пакеты проходят."
    else
        echo "❌ ТУННЕЛЬ ЕСТЬ, НО ПАКЕТЫ НЕ ИДУТ. Пробуем исправить MTU..."
        nft add rule inet fw4 forward tcp flags syn tcp option maxseg size set 1300 2>/dev/null
    fi
else
    echo "❌ ОШИБКА: tun0 не поднялся. Проверь логи: logread | grep openvpn"
fi
EOF
sh /root/setup_vpn.sh
