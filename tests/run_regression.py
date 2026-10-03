"""Run in Linux/WSL: python3 tests/run_regression.py.

Uses GCC and an existing Lua 5.4 shared library. All system operations are mocked.
"""
import ctypes
import ctypes.util
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run_lua():
    lua = ctypes.CDLL(ctypes.util.find_library("lua5.4"))
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                             ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    lua.luaL_openlibs(state)
    code = ("PROJECT_ROOT = [[" + str(ROOT) + "]]; dofile([[" +
            str(ROOT / "tests/luci_config_test.lua") + "]])").encode()
    try:
        result = lua.luaL_loadstring(state, code)
        if not result:
            result = lua.lua_pcallk(state, 0, 0, 0, 0, None)
        if result:
            raise AssertionError(lua.lua_tolstring(state, -1, None).decode())
    finally:
        lua.lua_close(state)


def run_config(tmp):
    exe = tmp / "config-test"
    source = ROOT / "zzz-client-source"
    subprocess.run(["gcc", "-D_GNU_SOURCE", "-std=gnu2x", "-Wall", "-Wextra",
                    "-fsanitize=address,undefined", "-g", "-I", str(source / "include"),
                    str(ROOT / "tests/config_test.c"), str(source / "src/utils/config.c"),
                    str(source / "src/utils/ini.c"), "-o", str(exe)], check=True)
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0")
    for password, expected in [(r"p\x20\x5Cx41\x3B\x20end\x20", b"p \\x41; end "),
                               (r"trailing\x", b"trailing\\x"),
                               (r"trailing\xA", b"trailing\\xA")]:
        config = tmp / "config.ini"
        config.write_text("[auth]\ndevice=wan\nusername=user\npassword=" + password + "\n")
        result = subprocess.run([str(exe), str(config)], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == expected.hex(), result.stdout
    for text in ["[auth]\ndevice=wan\nusername=user\n",
                 "[auth]\ndevice=wan\npassword=test\n",
                 "[auth]\ndevice=\nusername=user\npassword=test\n",
                 "[auth]\ndevice=wan\nusername=user\npassword=test\nbroken-line\n"]:
        config.write_text(text)
        result = subprocess.run([str(exe), str(config)], env=env, capture_output=True, text=True)
        assert result.returncode != 0
        assert "Sanitizer" not in result.stderr, result.stderr
    print("PASS: C config round-trip, truncated escapes, missing fields, malformed INI")


def shell(script, tmp, **variables):
    env = dict(os.environ, TEST_TMP=str(tmp), **{k: str(v) for k, v in variables.items()})
    result = subprocess.run(["sh", "-c", script], env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout


def run_shell(tmp):
    scripts = ROOT / "luci-app-zzz/files/etc"
    for path in [scripts / "init.d/zzz", scripts / "zzz/watchdog.sh",
                 scripts / "zzz/check_network.sh"]:
        subprocess.run(["sh", "-n", str(path)], check=True)

    # Source the production watchdog with main deferred; fake check/sleep/reconnect.
    watchdog = (scripts / "zzz/watchdog.sh").read_text().rsplit('main "$@"', 1)[0]
    watchdog = watchdog.replace("/etc/init.d/${SERVICE_NAME} reconnect", "reconnect")
    watchdog = watchdog.replace("STATUS_FILE=/var/run/zzz-connectivity",
                                'STATUS_FILE="$TEST_TMP/status"')
    checker = tmp / "check"
    checker.write_text("#!/bin/sh\nexit 1\n")
    checker.chmod(0o700)
    config = tmp / "watchdog.ini"
    config.write_text("[other]\nenabled=0\nmax_retries=0\n[watchdog]\nenabled=1\n"
                      "interval=1\nretry_delay=1\nmax_retries=2\n")
    shell(watchdog + """
CONFIG_FILE="$TEST_TMP/watchdog.ini"
CHECK_SCRIPT="$TEST_TMP/check"
log_msg() { :; }
reconnect() { echo reconnect >> "$TEST_TMP/reconnects"; }
sleep() { ticks=$((${ticks:-0} + 1)); [ "$ticks" -lt 7 ] || exit 0; }
main
""", tmp)
    assert (tmp / "reconnects").read_text().splitlines() == ["reconnect", "reconnect"]
    assert (tmp / "status").read_text().strip() == "retry_limit"
    print("PASS: watchdog section isolation and finite retry limit without self-restart")

    checker_source = (scripts / "zzz/check_network.sh").read_text().rsplit('main "$@"', 1)[0]
    checker_source = checker_source.replace("/sys/class/net/", str(tmp / "net") + "/")
    (tmp / "net/wan").mkdir(parents=True)
    (tmp / "net/wan/carrier").write_text("1\n")
    config.write_text("[auth]\ndevice=wan\n[watchdog]\n")
    mocks = """
CONFIG_FILE="$TEST_TMP/watchdog.ini"
log_msg() { :; }
ip() { echo "default via 192.0.2.1 dev wan"; }
ping() { for last do :; done; [ "$last" = "192.0.2.1" ]; }
main
"""
    result = subprocess.run(["sh", "-c", checker_source + mocks],
                            env=dict(os.environ, TEST_TMP=str(tmp)), capture_output=True)
    assert result.returncode == 1, "Reachable gateway must not imply internet access"
    config.write_text("[auth]\ndevice=wan\n[watchdog]\ngateway_ip=192.0.2.1\n")
    shell(checker_source + mocks, tmp)
    print("PASS: reachable gateway vs external connectivity; explicit probe override")

    init = (scripts / "init.d/zzz").read_text().split("# Legacy start/stop")[0]
    init = init.replace("/proc/sys/net/ipv6/conf/", str(tmp / "ipv6") + "/")
    init = init.replace("IPV6_STATE=/var/run/zzz-ipv6.state", 'IPV6_STATE="$TEST_TMP/ipv6.state"')
    init = init.replace('[ -x /sbin/procd ]', '[ 1 = 1 ]')
    for key, value in {"all": "0", "default": "1", "wan": "0", "eth0.1": "1"}.items():
        directory = tmp / "ipv6" / key
        directory.mkdir(parents=True)
        (directory / "disable_ipv6").write_text(value + "\n")
    shell("""
extra_command() { :; }
""" + init + """
log_msg() { :; }
nft() {
    case "$1" in
        list) [ -f "$TEST_TMP/ttl" ];;
        delete) rm -f "$TEST_TMP/ttl";;
        -f) cat >/dev/null; touch "$TEST_TMP/ttl";;
    esac
}
iptables() { return 1; }
sysctl() {
    setting="$2"
    key="${setting%=*}"; value="${setting##*=}"
    key="${key#net.ipv6.conf.}"; key="${key#net/ipv6/conf/}"
    key="${key%.disable_ipv6}"; key="${key%/disable_ipv6}"
    printf '%s\n' "$value" > "$TEST_TMP/ipv6/$key/disable_ipv6"
    if [ "$key" = all ]; then
        for path in "$TEST_TMP"/ipv6/*/disable_ipv6; do
            case "$path" in */default/*) continue;; esac
            printf '%s\n' "$value" > "$path"
        done
    fi
}
procd_send_signal() { [ "$1:$2:$3" = "zzz:zzz:TERM" ]; }
FIX_TTL=1
DISABLE_IPV6=1
apply_anti_detection || exit 1
[ -f "$TEST_TMP/ttl" ] || exit 2
FIX_TTL=0
DISABLE_IPV6=0
remove_anti_detection || exit 3
[ ! -f "$TEST_TMP/ttl" ] || exit 4
[ ! -f "$TEST_TMP/ipv6.state" ] || exit 5
reconnect || exit 6
""", tmp)
    for key, value in {"all": "0", "default": "1", "wan": "0", "eth0.1": "1"}.items():
        assert (tmp / "ipv6" / key / "disable_ipv6").read_text().strip() == value
    print("PASS: client-only reconnect, owned TTL cleanup, exact IPv6 restoration")


if __name__ == "__main__":
    run_lua()
    with tempfile.TemporaryDirectory(prefix="inode-regression-") as directory:
        tmp = Path(directory)
        run_config(tmp)
        run_shell(tmp)
    print("All regression checks passed.")
