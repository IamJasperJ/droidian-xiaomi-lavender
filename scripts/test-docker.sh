#!/usr/bin/env bash
# Run on the actual Droidian phone after booting the candidate kernel.
set -uo pipefail
if (( EUID != 0 )); then
    echo 'Run with sudo bash scripts/test-docker.sh [LOG_DIRECTORY]' >&2
    exit 2
fi
log_dir=${1:-"docker-test-$(date -u +%Y%m%dT%H%M%SZ)"}
mkdir -p "$log_dir"
log_dir=$(cd "$log_dir" && pwd)
exec > >(tee "$log_dir/test.log") 2>&1
failures=0
run_id="lavender-test-$$"
alpine=${ALPINE_IMAGE:-alpine:latest}
hello=${HELLO_IMAGE:-hello-world:latest}
http=${HTTP_IMAGE:-busybox:1.36}
started=$(date -u +%FT%TZ)
check() {
    local label=$1
    shift
    echo "===== $label ====="
    if timeout 180 "$@"; then echo "PASS: $label"; else
        echo "FAIL: $label"; failures=$((failures + 1))
    fi
}
collect_logs() {
    dmesg -T > "$log_dir/dmesg-after.log" 2>&1 || true
    journalctl -b --since "$started" --no-pager > "$log_dir/journal-after.log" 2>&1 || true
    journalctl -b -u docker -u containerd --no-pager > "$log_dir/docker-daemon.log" 2>&1 || true
    if command -v docker >/dev/null; then
        docker rm -f "$run_id-port" >/dev/null 2>&1 || true
    fi
}
trap collect_logs EXIT
check 'uname' uname -a
check 'cgroups' cat /proc/cgroups
check 'namespaces' ls -l /proc/self/ns
check 'filesystems' cat /proc/filesystems
check 'cgroup mounts' findmnt -t cgroup,cgroup2
dmesg -T > "$log_dir/dmesg-before.log" 2>&1 || true
if [[ -f /proc/config.gz ]]; then
    zcat /proc/config.gz > "$log_dir/running.config"
elif [[ -f "/boot/config-$(uname -r)" ]]; then
    cp "/boot/config-$(uname -r)" "$log_dir/running.config"
fi
if [[ -f "$log_dir/running.config" ]]; then
    check 'running kernel Docker config' python3 "$(dirname "$0")/verify-config.py" "$log_dir/running.config"
else
    echo 'No running kernel config available: kernel configuration validation remains incomplete.'
    failures=$((failures + 1))
fi
if ! command -v docker >/dev/null; then
    echo 'Docker is not installed. Install an explicitly selected compatible Engine/containerd/runc stack.'
    exit 1
fi
# This script is for the phone's local Engine, not a remote Docker context.
endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)
if [[ -n ${DOCKER_HOST:-} && ${DOCKER_HOST} != unix://* ]] || [[ "$endpoint" != unix://* ]]; then
    echo "Refusing non-local Docker endpoint: $endpoint"
    exit 2
fi
modprobe br_netfilter || failures=$((failures + 1))
if ! docker info >/dev/null 2>&1; then
    check 'start Docker daemon' systemctl start docker
fi
check 'Docker version' docker version
check 'Docker info' docker info
docker info > "$log_dir/docker-info.txt" 2>&1 || true
docker version > "$log_dir/docker-version.txt" 2>&1 || true
containerd --version 2>&1 || true
runc --version 2>&1 || true
iptables --version 2>&1 || true
check 'hello-world' docker run --rm --pull=missing "$hello"
check 'ARM64 container architecture' bash -c 'test "$(docker run --rm "$1" uname -m)" = aarch64' _ "$alpine"
check 'bridge NAT connectivity' docker run --rm "$alpine" ping -c 3 -W 5 1.1.1.1
check 'container DNS' docker run --rm "$alpine" nslookup example.com
check 'memory and CPU limits observed inside container' docker run --rm \
    --memory 64m --memory-swap 64m --cpus 0.5 "$alpine" sh -ec \
    'test "$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)" = 67108864
     test "$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)" = 50000
     test "$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)" = 100000'
check 'container writable layer' docker run --rm "$alpine" sh -ec 'echo storage-ok >/tmp/lavender-check; test "$(cat /tmp/lavender-check)" = storage-ok'
driver=$(docker info --format '{{.Driver}}' 2>/dev/null || true)
echo "Actual storage driver: $driver"
case "$driver" in
    overlay2|overlayfs) echo 'Overlay storage reported; see docker-info.txt for backing filesystem and snapshotter details.' ;;
    *) echo 'Overlay storage not confirmed. vfs can diagnose compatibility but has high storage overhead.'
       failures=$((failures + 1)) ;;
esac
check 'launch local-only port mapping' docker run -d --name "$run_id-port" \
    -p 127.0.0.1::8080 "$http" sh -ec \
    'mkdir -p /www; echo lavender-port-ok >/www/index.html; exec httpd -f -p 8080 -h /www'
port=$(docker inspect --format '{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}' "$run_id-port" 2>/dev/null || true)
if [[ "$port" =~ ^[0-9]+$ ]]; then
    check 'published port HTTP response' python3 - "$port" <<'PYHTTP'
import sys
import time
import urllib.error
import urllib.request

for attempt in range(6):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/", timeout=5) as response:
            body = response.read()
        if body.strip() != b"lavender-port-ok":
            raise RuntimeError(f"Unexpected published-port response: {body!r}")
        break
    except urllib.error.URLError:
        if attempt == 5:
            raise
        time.sleep(1)
PYHTTP
else
    echo 'FAIL: no mapped port'; failures=$((failures + 1))
fi
docker image inspect "$hello" "$alpine" "$http" > "$log_dir/test-image-inspect.json" 2>&1 || true
echo "Failures: $failures"
echo "Logs: $log_dir"
echo 'Wi-Fi switching is a separate manual device test; follow README.md and keep dmesg/journal logs.'
(( failures == 0 ))
