#!/usr/bin/env bash
# Run the same official container on an amd64 Linux VM, without flashing.
set -Eeuo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
buildd=${1:?Usage: build-on-linux.sh ABSOLUTE_BUILD_DIRECTORY}
[[ "$buildd" = /* ]] || { echo 'Build directory must be absolute' >&2; exit 2; }
[[ ! -e "$buildd/sources" ]] || { echo 'Use a fresh build directory to avoid stale outputs' >&2; exit 2; }
source "$project/config/source.lock"
mkdir -p "$buildd/artifacts"
docker_command=(docker)
if ! docker info >/dev/null 2>&1; then docker_command=(sudo -n docker); fi
finish() {
    code=$?
    trap - EXIT
    set +e
    sudo -n chown -R "$(id -u):$(id -g)" "$buildd"
    outcome=failure
    if (( code == 0 )) && [[ -f "$buildd/artifacts/BUILD_SUCCESS" ]]; then outcome=success; fi
    BUILD_OUTCOME="$outcome" KERNEL_SOURCE_DIR="$buildd/sources" \
        RUN_URL="${RUN_REFERENCE:-Linux VM:$buildd}" \
        GITHUB_SHA="${PROJECT_SHA:-not supplied}" BUILD_LOCATION="Linux VM" \
        python3 "$project/scripts/finalize-info.py" "$buildd/artifacts"
    finalize_code=$?
    if (( code == 0 && finalize_code != 0 )); then code=$finalize_code; fi
    printf '%s\n' "$code" > "$buildd/build.exit"
    exit "$code"
}
trap finish EXIT
(
    df -h "$buildd"
    test "$(df -PB1 "$buildd" | awk 'NR==2 {print $4}')" -ge 20000000000
    bash "$project/scripts/prepare-source.sh" "$buildd/sources"
    "${docker_command[@]}" pull "$BUILD_IMAGE"
    "${docker_command[@]}" image inspect "$BUILD_IMAGE" > "$buildd/artifacts/container-inspect.json"
    "${docker_command[@]}" run --rm --name lavender-kernel-vm-build \
        -e BUILD_JOBS="${BUILD_JOBS:-2}" \
        -v "$project:/project:ro" -v "$buildd:/buildd" \
        -w /buildd/sources "$BUILD_IMAGE" bash /project/scripts/build-in-container.sh
    test -f "$buildd/artifacts/BUILD_SUCCESS"
) 2>&1 | tee "$buildd/artifacts/build.log"
