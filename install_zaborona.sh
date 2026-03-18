#!/bin/sh

# 1. Проверка и установка драйверов (критично для появления tun0)
if command -v apk >/dev/null; then
    apk update
    apk add kmod-tun openvpn-openssl luci-app-openvpn ca-bundle ca-certificates
else
    opkg update
    opkg install kmod-tun openvpn-openssl luci-app-openvpn ca-bundle ca-certificates
fi

# 2. Создание папок и загрузка сертификатов
mkdir -p /etc/openvpn
wget --no-check-certificate -q "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

# 3. Настройка сети (UCI)
# Удаляем старое, если было
uci -q delete network.zaborona_help
uci -q delete openvpn.zaborona_help

# Создаем интерфейс
uci set network.zaborona_help=interface
uci set network.zaborona_help.proto='none'
uci set network.zaborona_help.device='tun0'

# Настройка VPN (Выбрана Европа/Big Routes)
uci set openvpn.zaborona_help=openvpn
uci set openvpn.zaborona_help.client='1'
uci set openvpn.zaborona_help.enabled='1'
uci set openvpn.zaborona_help.dev='tun0'
uci set openvpn.zaborona_help.proto='udp'
uci set openvpn.zaborona_help.remote='srv0bigroutes.vpn.zaboronahelp.pp.ua 1194'
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

# 4. Настройка Firewall (nftables/fw4)
# Привязываем устройство tun0 напрямую к зоне WAN
WAN_NAME=$(uci show firewall | grep ".name='wan'" | head -n 1 | cut -d'[' -f2 | cut -d']' -f1)
[ -z "$WAN_NAME" ] && WAN_NAME=1

uci del_list firewall.@zone[$WAN_NAME].device='tun0'
uci add_list firewall.@zone[$WAN_NAME].device='tun0'
uci set firewall.@zone[$WAN_NAME].mtu_fix='1'
uci set firewall.@zone[$WAN_NAME].masq='1'
uci commit firewall

# 5. DNS (Анти-блокировка)
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='208.67.222.222'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci commit dhcp

# 6. Перезапуск сервисов
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
/etc/init.d/dnsmasq restart

echo "--- Настройка завершена. Ожидаем поднятия tun0 ---"
sleep 60
ifconfig tun0
