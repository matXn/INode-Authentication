#!/bin/sh
# ============================================================
#  zzz 802.1X Client - Network Connectivity Checker
#  Used by the auto-reconnect watchdog mechanism.
#  This script performs a single connectivity check cycle.
# ============================================================

CONFIG_FILE="${1:-/etc/config.ini}"
LOG_TAG="zzz-checker"

log_msg() {
	logger -t "$LOG_TAG" "$1"
}

# Read configuration
get_config_value() {
	local key="$1"
	local section="$2"
	awk -v key="$key" -v section="$section" '
		{sub(/\r$/, "")}
		/^\[/{inside=($0 == "[" section "]"); next}
		inside && $0 ~ "^" key "[[:space:]]*=" {
			sub(/^[^=]*=[[:space:]]*/, ""); gsub(/\r/, ""); print; exit
		}' "$CONFIG_FILE" 2>/dev/null
}

# Get gateway IP
get_gateway() {
	local gw_cfg="$(get_config_value 'gateway_ip' 'watchdog')"
	if [ -n "$gw_cfg" ]; then
		echo "$gw_cfg"
		return
	fi
	local gw
	gw="$(ip -4 route show default dev "$device" 2>/dev/null | awk 'NR==1{print $3}')"
	if [ -n "$gw" ]; then
		echo "$gw"
	else
		log_msg "WARNING: No default route found, will fall back to public DNS check"
	fi
}

# Main check function: returns 0 if connected, 1 if disconnected
main() {
	# Check config exists
	if [ ! -f "$CONFIG_FILE" ]; then
		log_msg "ERROR: Config file not found at $CONFIG_FILE"
		exit 1
	fi

	local device="$(get_config_value 'device' 'auth')"

	if [ -z "$device" ]; then
		log_msg "ERROR: No device specified in config"
		exit 1
	fi

	# Check if interface exists
	if [ ! -d "/sys/class/net/$device" ]; then
		log_msg "WARNING: Interface $device does not exist"
		exit 1
	fi

	local gw_ip="$(get_gateway)"
	local gateway_ok=1

	# Test 1: Ping gateway with specific interface
	if [ -n "$gw_ip" ]; then
		if ping -c 1 -W 3 -I "$device" "$gw_ip" >/dev/null 2>&1; then
			gateway_ok=0
			log_msg "Gateway $gw_ip reachable via $device; checking external connectivity"
		else
			log_msg "FAIL: Gateway $gw_ip unreachable via $device"
		fi
	fi

	# Test 2: Check carrier/link state
	local carrier_file="/sys/class/net/$device/carrier"
	if [ -f "$carrier_file" ]; then
		local carrier_state="$(cat "$carrier_file" 2>/dev/null)"
		if [ "$carrier_state" != "1" ]; then
			log_msg "FAIL: No link on $device (carrier=$carrier_state)"
			exit 1
		fi
	fi

	# An explicit probe target is authoritative (e.g. networks blocking public ICMP).
	local probe_ip="$(get_config_value 'gateway_ip' 'watchdog')"
	if [ -n "$probe_ip" ]; then
		exit "$gateway_ok"
	fi

	# A reachable gateway alone does not establish external connectivity.
	if ping -c 1 -W 3 -I "$device" 223.5.5.5 >/dev/null 2>&1; then
		log_msg "OK: DNS (223.5.5.5) reachable via $device"
		exit 0
	elif ping -c 1 -W 3 -I "$device" 114.114.114.114 >/dev/null 2>&1; then
		log_msg "OK: DNS (114.114.114.114) reachable via $device"
		exit 0
	else
		log_msg "FAIL: All connectivity tests failed on $device"
		exit 1
	fi
}

# Run main
main "$@"
