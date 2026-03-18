#!/bin/sh

# 1. Определяем пакетный менеджер (opkg или apk)
if command -v apk >/dev/null; then
    PKG_MGR="apk add"
    opkg_update="apk update"
else
    PKG_MGR="opkg install"
    opkg_update="opkg update"
fi

echo "--- Использование менеджера: $PKG_MGR ---"
$opkg_update

# 2. Установка необходимых компонентов
$PKG_MGR openvpn-openssl luci-app-openvpn luci-i18n-openvpn-ru libustream-openssl ca-bundle

# 3. Скачивание сертификатов
mkdir -p /etc/openvpn
echo "--- Скачивание сертификатов Zaborona ---"
wget --no-check-certificate "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key

# 4. Настройка сетевого интерфейса (стандарт 25.x)
echo "--- Настройка сети ---"
uci delete network.zaborona_help
uci set network.zaborona_help=interface
uci set network.zaborona_help.proto='none'
uci set network.zaborona_help.device='tun0'
uci set network.zaborona_help.auto='1'
uci commit network

# 5. Настройка OpenVPN клиента
echo "--- Настройка OpenVPN ---"
uci delete openvpn.zaborona_help
uci set openvpn.zaborona_help=openvpn
uci set openvpn.zaborona_help.client='1'
uci set openvpn.zaborona_help.enabled='1'
uci set openvpn.zaborona_help.dev='tun0'
uci set openvpn.zaborona_help.proto='tcp-client'
uci set openvpn.zaborona_help.remote='srv0.vpn.zaboronahelp.pp.ua 1194'
uci set openvpn.zaborona_help.resolv_retry='infinite'
uci set openvpn.zaborona_help.nobind='1'
uci set openvpn.zaborona_help.persist_key='1'
uci set openvpn.zaborona_help.persist_tun='1'
uci set openvpn.zaborona_help.remote_cert_tls='server'
uci set openvpn.zaborona_help.auth='sha1'
uci set openvpn.zaborona_help.cipher='AES-128-CBC'
# Добавляем data_ciphers для новых версий OpenVPN
uci set openvpn.zaborona_help.data_ciphers='AES-128-GCM:AES-128-CBC'
uci set openvpn.zaborona_help.ca='/etc/openvpn/ca.crt'
uci set openvpn.zaborona_help.cert='/etc/openvpn/zaborona-help.crt'
uci set openvpn.zaborona_help.key='/etc/openvpn/zaborona-help.key'
uci set openvpn.zaborona_help.verb='3'
uci set openvpn.zaborona_help.pull_filter='ignore ifconfig-ipv6'
uci add_list openvpn.zaborona_help.pull_filter='ignore route-ipv6'
uci commit openvpn

# 6. Настройка Firewall (nftables / fw4)
echo "--- Настройка Firewall ---"
# Добавляем интерфейс в зону WAN (обычно индекс 1)
uci add_list firewall.@zone[1].network='zaborona_help'
uci commit firewall

# 7. Принудительная установка DNS (OpenDNS для Zaborona)
echo "--- Настройка DNS ---"
uci del dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='208.67.222.222'
uci add_list dhcp.@dnsmasq[0].server='208.67.220.220'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci commit dhcp

echo "--- Перезагрузка сервисов ---"
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
/etc/init.d/dnsmasq restart

echo "--- Готово! Проверь интерфейс tun0 командой ifconfig ---"