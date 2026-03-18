#!/bin/sh

# 1. Ждем, пока пролетит вставленный текст, и чистим буфер
echo "Подготовка... Подождите 3 секунды..."
sleep 3
while read -t 1 -n 10000; do :; done 2>/dev/null

echo "======================================="
echo "       НАСТРОЙКА ZABORONA HELP         "
echo "======================================="
echo "1) Основные серверы (Стандарт)"
echo "2) Европа (Большой список маршрутов)"
echo "---------------------------------------"

# 2. Упорный цикл выбора
while true; do
    printf "Введите 1 или 2 и нажмите ENTER: "
    read -r choice
    case "$choice" in
        1)
            SERVER="srv0.vpn.zaboronahelp.pp.ua"
            echo "Выбрано: Стандарт"
            break
            ;;
        2)
            SERVER="srv0bigroutes.vpn.zaboronahelp.pp.ua"
            echo "Выбрано: Европа (Big Routes)"
            break
            ;;
        *)
            echo "Неверный ввод. Пожалуйста, введите только цифру 1 или 2."
            ;;
    esac
done

# 3. Установка пакетов
if command -v apk >/dev/null; then
    PKG="apk add"
    $PKG openvpn-openssl luci-app-openvpn ca-bundle ca-certificates libustream-openssl
else
    opkg update
    PKG="opkg install"
    $PKG openvpn-openssl luci-app-openvpn ca-bundle ca-certificates libustream-openssl
fi

# 4. Сертификаты и Конфиг
mkdir -p /etc/openvpn
wget --no-check-certificate -q "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

# 5. UCI Настройки (Сеть + VPN + Firewall)
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

# Привязка к WAN зоне
WAN_ZONE=$(uci show firewall | grep ".name='wan'" | cut -d'[' -f2 | cut -d']' -f1)
[ -z "$WAN_ZONE" ] && WAN_ZONE=1
uci add_list firewall.@zone[$WAN_ZONE].network='zaborona_help'
uci set firewall.@zone[$WAN_ZONE].mtu_fix='1'
uci commit firewall

# DNS (OpenDNS)
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='208.67.222.222'
uci add_list dhcp.@dnsmasq[0].server='208.67.220.220'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].strictorder='1'
uci commit dhcp

# 6. Рестарт
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
/etc/init.d/dnsmasq restart

echo "--- Ждем 30 секунд (загрузка маршрутов) ---"
sleep 30

# 7. Финальная проверка
TUN_IP=$(ifconfig tun0 2>/dev/null | grep 'inet ' | awk '{print $2}' | sed 's/addr://')

if [ -n "$TUN_IP" ]; then
    echo "✅ ГОТОВО! IP туннеля: $TUN_IP"
    echo "Тестируем шлюз (10.224.0.1)..."
    if ping -c 2 10.224.0.1 > /dev/null 2>&1; then
        echo "✅ СВЯЗЬ ОК!"
    else
        echo "⚠️  Туннель есть, но пинг не идет. Пробуем nftables fix..."
        nft add rule inet fw4 forward tcp flags syn tcp option maxseg size set 1300 2>/dev/null
    fi
else
    echo "❌ ОШИБКА: tun0 не поднялся."
fi
EOF
sh /root/setup_vpn.sh
