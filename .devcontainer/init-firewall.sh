#!/bin/bash
# Egress firewall, run as root at every container start (post-start.sh). Safe to re-run.
#
# Allowed: GitHub (its published IP ranges), the base domains below and the project's
# .devcontainer-domains, each with its subdomains. The build copied the project list from your
# clone to /etc/claude-dev/project-domains, so a change only takes effect after a rebuild.
# No IPv6 egress at all.
#
# DNS goes through a local dnsmasq that answers only for allowed domains and adds every
# address it returns to the allowlist. So DNS cannot carry data out, and CDN hosts that
# rotate addresses keep working. Only root (dnsmasq, this script) can reach the upstream
# resolver. The firewall is closed while this script runs; only root has egress meanwhile.
set -euo pipefail
IFS=$'\n\t'

CONF=/etc/claude-dev
PROJECT_DOMAINS=$CONF/project-domains
UPSTREAM_FILE=$CONF/upstream-dns
DNSMASQ_CONF=$CONF/dnsmasq.conf
BASE_DOMAINS=(
    "api.anthropic.com"
    "registry.npmjs.org"
    "conda.anaconda.org"
    "pypi.org"
    "files.pythonhosted.org"
)
# Resolved, but not added to the allowlist: GitHub's addresses come from its meta API.
GITHUB_DOMAINS=("github.com" "githubusercontent.com")

# 1. Upstream resolvers: Docker's, read on the first run and saved, since afterwards
#    resolv.conf points at dnsmasq.
if ! grep -qFx "nameserver 127.0.0.1" /etc/resolv.conf; then
    awk '$1 == "nameserver" && $2 ~ /^[0-9.]+$/ {print $2}' /etc/resolv.conf > "$UPSTREAM_FILE"
fi
mapfile -t UPSTREAMS < "$UPSTREAM_FILE"
[ ${#UPSTREAMS[@]} -gt 0 ] || { echo "ERROR: no IPv4 upstream DNS server in $UPSTREAM_FILE"; exit 1; }

DOMAINS=("${BASE_DOMAINS[@]}")
if [ -f "$PROJECT_DOMAINS" ]; then
    while read -r line || [ -n "$line" ]; do
        line=${line%%#*}
        line=$(echo "$line" | tr -d '[:space:]')
        [ -z "$line" ] && continue
        [[ $line =~ ^[A-Za-z0-9.-]+$ ]] || { echo "ERROR: bad domain in .devcontainer-domains: $line"; exit 1; }
        DOMAINS+=("$line")
    done < "$PROJECT_DOMAINS"
fi

# 2. Close everything, keeping Docker's internal DNS NAT rules (user-defined networks).
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
if [ -n "$DOCKER_DNS_RULES" ]; then
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi
# IPv6: loopback only. dnsmasq returns no AAAA records, but literal addresses would get out.
if [ -e /proc/net/if_inet6 ]; then
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
    ip6tables -F
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
fi

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
# DNS: anyone may ask dnsmasq on 127.0.0.1; only root may ask anyone else. Matching the
# original destination port also catches Docker's NATed 127.0.0.11 resolver.
for p in udp tcp; do
    iptables -A OUTPUT -p "$p" -m conntrack --ctorigdst 127.0.0.1 --ctorigdstport 53 -j ACCEPT
    iptables -A OUTPUT -p "$p" -m conntrack --ctorigdstport 53 -m owner --uid-owner 0 -j ACCEPT
    iptables -A OUTPUT -p "$p" -m conntrack --ctorigdstport 53 -j REJECT
done
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner 0 -j ACCEPT    # setup only, removed in step 5

# 3. dnsmasq: forwards allowed domains only and adds their addresses to the ipset.
ipset destroy allowed-domains 2>/dev/null || true
ipset create allowed-domains hash:net
{
    echo "no-resolv"
    echo "no-hosts"
    echo "listen-address=127.0.0.1"
    echo "bind-interfaces"
    echo "user=root"
    echo "filter-AAAA"
    echo "pid-file=/run/claude-dnsmasq.pid"
    for d in "${DOMAINS[@]}" "${GITHUB_DOMAINS[@]}"; do
        for u in "${UPSTREAMS[@]}"; do echo "server=/$d/$u"; done
    done
    for d in "${DOMAINS[@]}"; do echo "ipset=/$d/allowed-domains"; done
} > "$DNSMASQ_CONF"
pkill -x dnsmasq 2>/dev/null || true
for _ in $(seq 50); do pgrep -x dnsmasq >/dev/null || break; sleep 0.1; done
dnsmasq --conf-file="$DNSMASQ_CONF"
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "dnsmasq: ${#DOMAINS[@]} allowed domains, upstream ${UPSTREAMS[*]}"

# 4. GitHub publishes its IP ranges.
gh_ranges=$(curl -s --connect-timeout 10 https://api.github.com/meta || true)
if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
    echo "ERROR: failed to fetch GitHub IP ranges"
    exit 1
fi
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    ipset add -exist allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | grep -v ':' | aggregate -q)

# 5. Host network (the Docker bridge), the allowlist, and the end of root's setup egress.
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: failed to detect host IP"
    exit 1
fi
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -D OUTPUT -m owner --uid-owner 0 -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# 6. Verify, as the unprivileged user.
as_node() { runuser -u node -- "$@"; }
fail() { echo "ERROR: firewall verification failed: $*"; exit 1; }
if as_node curl -s --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    fail "example.com reachable"
fi
[ -z "$(as_node dig +short +time=2 +tries=1 example.com 2>/dev/null | grep -E '^[0-9.]+$' || true)" ] \
    || fail "dnsmasq resolved example.com"
[ -z "$(as_node dig +short +time=2 +tries=1 "@${UPSTREAMS[0]}" example.com 2>/dev/null | grep -E '^[0-9.]+$' || true)" ] \
    || fail "upstream DNS reachable directly"
as_node curl -s --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1 || fail "api.github.com unreachable"
as_node curl -s --connect-timeout 5 -o /dev/null https://api.anthropic.com 2>&1 || fail "api.anthropic.com unreachable"
echo "Firewall verified: example.com blocked, direct DNS blocked, GitHub and Anthropic reachable"
