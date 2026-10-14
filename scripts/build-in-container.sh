#!/usr/bin/env bash
# Only invoked by the GitHub Actions runner in the official amd64 container.
set -Eeuo pipefail
cd /buildd/sources
artifacts=/buildd/artifacts
mkdir -p "$artifacts"
finish() {
    code=$?
    trap - EXIT
    set +e
    if [[ -f out/KERNEL_OBJ/.config ]]; then
        cp out/KERNEL_OBJ/.config "$artifacts/final.config"
    fi
    dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$artifacts/dependency-versions.txt"
    python3 /project/scripts/collect-artifacts.py /buildd /project "$code"
    collect_code=$?
    if (( code == 0 && collect_code != 0 )); then code=$collect_code; fi
    exit "$code"
}
trap finish EXIT
date -u +%FT%TZ > "$artifacts/build-started.txt"
df -h /buildd
test "$(dpkg --print-architecture)" = amd64
command -v releng-build-package
apt-get update
apt-get install -y --no-install-recommends linux-packaging-snippets python3 file
cp debian/control "$artifacts/original-debian-control"
rm debian/control
debian/rules debian/control
cp debian/control "$artifacts/generated-debian-control"
mk-build-deps --install --remove --host-arch arm64 --build-arch amd64 \
    --tool 'apt-get -y --no-install-recommends' debian/control
dpkg-checkbuilddeps -a arm64
aarch64-linux-android-gcc-4.9 --version > "$artifacts/toolchain-version.txt"
cp /usr/share/linux-packaging-snippets/kernel-snippet.mk "$artifacts/kernel-snippet.mk"
cp "$(command -v releng-build-package)" "$artifacts/releng-build-package"
export PATH="/usr/lib/llvm-android-6.0-4691093/bin:$PWD/debian/path-override:$PATH"
debian/rules path-override-prepare
# Resolve both configs with the exact same compiler and source. Fail if
# any driver or other unrelated symbol changes after dependency resolution.
mkdir -p /buildd/baseline-config
make ARCH=arm64 O=/buildd/baseline-config CROSS_COMPILE=aarch64-linux-android- \
    CC=aarch64-linux-android-gcc-4.9 defconfig \
    KBUILD_DEFCONFIG=/project/config/original-lavender_halium_defconfig
make ARCH=arm64 O=/buildd/baseline-config CROSS_COMPILE=aarch64-linux-android- \
    CC=aarch64-linux-android-gcc-4.9 olddefconfig
cp /buildd/baseline-config/.config "$artifacts/baseline.config"
debian/rules out/KERNEL_OBJ/.config
make ARCH=arm64 O=out/KERNEL_OBJ CROSS_COMPILE=aarch64-linux-android- \
    CC=aarch64-linux-android-gcc-4.9 olddefconfig
python3 /project/scripts/verify-config.py out/KERNEL_OBJ/.config \
    --baseline "$artifacts/baseline.config" --source "$PWD" | tee "$artifacts/config-verification.log"
cp out/KERNEL_OBJ/.config "$artifacts/prebuild.config"
export DEB_BUILD_OPTIONS="parallel=${BUILD_JOBS:-2}"
RELENG_HOST_ARCH=arm64 releng-build-package
python3 /project/scripts/verify-config.py out/KERNEL_OBJ/.config \
    --baseline "$artifacts/baseline.config" | tee "$artifacts/final-config-verification.log"
cmp out/KERNEL_OBJ/.config "$artifacts/prebuild.config"
