#!/bin/sh
# 1. Установка пакетов
apk update
apk add openvpn-openssl luci-app-openvpn ca-bundle ca-certificates

# 2. Сертификаты
mkdir -p /etc/openvpn
wget --no-check-certificate -q "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate -q "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

# 3. Чистый конфиг сети (создаем само устройство)
uci set network.zaborona_help=interface
uci set network.zaborona_help.proto='none'
uci set network.zaborona_help.device='tun0'

# 4. Конфиг VPN (Европа/Big Routes)
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

# 5. Привязка к файрволу (чтобы сайты открывались)
WAN_ZONE=$(uci show firewall | grep ".name='wan'" | cut -d'[' -f2 | cut -d']' -f1)
[ -z "$WAN_ZONE" ] && WAN_ZONE=1
uci add_list firewall.@zone[$WAN_ZONE].network='zaborona_help'
uci commit firewall

/etc/init.d/network restart
/etc/init.d/openvpn restart
EOF
