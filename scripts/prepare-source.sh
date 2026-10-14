#!/usr/bin/env bash
set -Eeuo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
source "$project/config/source.lock"
source_dir=${1:?Usage: prepare-source.sh SOURCE_DIR}
git clone --no-checkout --depth 1 --branch "$SOURCE_BRANCH" "$SOURCE_URL" "$source_dir"
if ! git -C "$source_dir" cat-file -e "$SOURCE_SHA^{commit}" 2>/dev/null; then
    git -C "$source_dir" fetch --depth 1 origin "$SOURCE_SHA"
fi
git -C "$source_dir" checkout --detach "$SOURCE_SHA"
test "$(git -C "$source_dir" rev-parse HEAD)" = "$SOURCE_SHA"
# A named local feature branch gives releng its supported changelog context.
git -C "$source_dir" checkout -b feature/docker-kernel
cmp "$source_dir/arch/arm64/configs/lavender_halium_defconfig" \
    "$project/config/original-lavender_halium_defconfig"
for patch in docker-kernel-config.patch packaging-safety.patch; do
    git -C "$source_dir" apply --check "$project/patches/$patch"
    git -C "$source_dir" apply "$project/patches/$patch"
done
git -C "$source_dir" diff --check
git -C "$source_dir" diff --stat
