#!/bin/sh

CONFIG_FILE="${1:-/etc/config.ini}"
CHECK_SCRIPT="${2:-/etc/zzz/check_network.sh}"
LOG_TAG="zzz-watchdog"
SERVICE_NAME="zzz"
STATUS_FILE=/var/run/zzz-connectivity

log_msg() {
	logger -t "$LOG_TAG" "$1"
}

get_cfg() {
	local key="$1"
	awk -v key="$key" '
		{sub(/\r$/, "")}
		/^\[watchdog\]/{inside=1; next} /^\[/{inside=0}
		inside && $0 ~ "^" key "[[:space:]]*=" {
			sub(/^[^=]*=[[:space:]]*/, ""); gsub(/\r/, ""); print; exit
		}' "$CONFIG_FILE" 2>/dev/null
}

main() {
	if [ ! -x "$CHECK_SCRIPT" ]; then
		log_msg "ERROR: check script not executable: $CHECK_SCRIPT"
		exit 1
	fi

	local interval max_retries retry_delay enabled
	interval="$(get_cfg 'interval')"
	max_retries="$(get_cfg 'max_retries')"
	retry_delay="$(get_cfg 'retry_delay')"
	enabled="$(get_cfg 'enabled')"

	[ -z "$interval" ] && interval=30
	[ -z "$max_retries" ] && max_retries=-1
	[ -z "$retry_delay" ] && retry_delay=10
	[ -z "$enabled" ] && enabled=0

	case "$interval" in ''|*[!0-9]*) interval=30;; esac
	case "$retry_delay" in ''|*[!0-9]*) retry_delay=10;; esac
	case "$max_retries" in -1) ;; ''|*[!0-9]*) max_retries=-1;; esac
	[ "$interval" -ge 1 ] 2>/dev/null || interval=30
	[ "$retry_delay" -ge 1 ] 2>/dev/null || retry_delay=10
	[ "$interval" -le 86400 ] 2>/dev/null || interval=30
	[ "$retry_delay" -le 86400 ] 2>/dev/null || retry_delay=10
	[ "$max_retries" -le 100000 ] 2>/dev/null || max_retries=-1

	if [ "$enabled" != "1" ]; then
		log_msg "Watchdog disabled in config, exiting"
		exit 0
	fi

	local fail_count=0
	local retry_count=0

	log_msg "Watchdog started (interval=${interval}s, max_retries=${max_retries}, retry_delay=${retry_delay}s)"
	printf '%s\n' checking > "$STATUS_FILE"

	while true; do
		if "$CHECK_SCRIPT" "$CONFIG_FILE" >/dev/null 2>&1; then
			printf '%s\n' online > "$STATUS_FILE"
			[ "$fail_count" -gt 0 ] && log_msg "Network recovered"
			fail_count=0
			retry_count=0
			sleep "$interval"
			continue
		fi

		fail_count=$((fail_count + 1))
		printf '%s\n' offline > "$STATUS_FILE"
		log_msg "Connectivity check failed (consecutive=${fail_count})"

		if [ "$fail_count" -lt 2 ]; then
			sleep "$interval"
			continue
		fi

		if [ "$max_retries" -ge 0 ] && [ "$retry_count" -ge "$max_retries" ]; then
			printf '%s\n' retry_limit > "$STATUS_FILE"
			log_msg "Max retries reached (${max_retries}), skip restart and keep monitoring"
			sleep "$interval"
			continue
		fi

		log_msg "Restarting authentication client (retry $((retry_count + 1)))"
		retry_count=$((retry_count + 1))
		# Signal only the client instance; this watchdog and its counters survive.
		if ! /etc/init.d/${SERVICE_NAME} reconnect >/dev/null 2>&1; then
			log_msg "ERROR: Could not request authentication reconnect"
		fi
		fail_count=0
		sleep "$retry_delay"
	done
}

main "$@"
