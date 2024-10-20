#!/bin/bash
set -e

cmd_help() {
    cat <<EOF
$0

COMMANDS:
    tun <start|stop|restart>
        Set routing to tunnel all traffic to local proxy, or use a plain SOCKS5
        proxy server, requiring manual connection from user.
    help
        Show this message and exit.
EOF
}

cmd_tun() {
    case $1 in
        start)
            start_tunneling
            echo "Successfully changed the mode to full traffic tunneling."
            ;;
        stop)
            stop_tunneling
            echo "Successfully changed the mode to proxy (default)"
            echo "Manual user connection to proxy server is required."
            ;;
        restart)
            stop_tunneling
            start_tunneling
            echo "Tunnel successfully restarted."
            ;;
        *)
            echo "Error: Invalid mode: \"$1\"."
    esac
}

start_tunneling() {
    mkdir -p /tmp/byedpi

    nohup su - byedpi -s /bin/bash -c \
"ciadpi --ip 127.0.0.1 --port 4080 \
--udp-fake=2 --oob=2 --md5sig \
--auto=torst --timeout=3" > /tmp/byedpi/ciadpi.log 2>&1 &
    nohup hev-socks5-tunnel /etc/byedpi/hev-socks5-tunnel.yaml > /tmp/byedpi/hev-socks5-tunnel.log 2>&1 &

    for ((;;)); do
        if ip tuntap list | grep -q byedpi-tun; then
            break
        fi

        echo "Waiting for tunnel interface..."
        sleep 1
    done

    user_id=$(id -u byedpi)
    nic_name=$(ip route show to default | awk '$5 != "byedpi-tun" {print $5; exit}')
    gateway_addr=$(ip route show to default | awk '$5 != "byedpi-tun" {print $3; exit}')

    ip rule add uidrange $user_id-$user_id lookup 110 pref 28000 || true
    ip route add default via $gateway_addr dev $nic_name metric 50 table 110 || true
    ip route add default via 172.20.0.1 dev byedpi-tun metric 1 || true
}

stop_tunneling() {
    user_id=$(id -u byedpi)
    nic_name=$(ip route show to default | awk '$5 != "byedpi-tun" {print $5; exit}')
    gateway_addr=$(ip route show to default | awk '$5 != "byedpi-tun" {print $3; exit}')

    ip rule del uidrange $user_id-$user_id lookup 110 pref 28000 || true
    ip route del default via "$gateway_addr" dev "$nic_name" metric 50 table 110 || true
    ip route del default via 172.20.0.1 dev byedpi-tun metric 1 || true
    killall ciadpi || true
    killall hev-socks5-tunnel || true
}

case $1 in
    help)
        cmd_help
        ;;
    tun)
        cmd_tun $2
        ;;
    *)
        echo "Invalid argument $1"
        echo "Use \"help\" command."
        exit 1
esac
