#!/usr/bin/env python3
"""Called after the log writer exits, even when cloning/pulling/building fails."""
import datetime
import hashlib
import os
import pathlib
import re
import shutil
import sys

artifacts = pathlib.Path(sys.argv[1])
project = pathlib.Path(__file__).resolve().parents[1]
artifacts.mkdir(parents=True, exist_ok=True)
for path in (project / "patches").glob("*.patch"):
    shutil.copy2(path, artifacts / path.name)
shutil.copy2(project / "config/source.lock", artifacts / "source.lock")
shutil.copy2(project / "config/original-lavender_halium_defconfig", artifacts / "original-defconfig")
passed = os.environ.get("BUILD_OUTCOME") == "success" and (artifacts / "BUILD_SUCCESS").exists()
info = ["Build status: " + ("SUCCESS (static validation only)" if passed else "FAILED / INCOMPLETE"),
        "Completed UTC: " + datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "Architecture: arm64 (AArch64)",
        "Makefile base version: 4.4.156", "Upstream Debian package version label: 4.4.192",
        "Actual kernelrelease: recorded below if compilation completed",
        "Run reference: " + os.environ.get("RUN_URL", "not available"),
        "Build location: " + os.environ.get("BUILD_LOCATION", "GitHub Actions"),
        "Project commit: " + os.environ.get("GITHUB_SHA", "not available"),
        "Source/environment lock:\n" + (project / "config/source.lock").read_text(),
        "APT dependencies are recorded in dependency-versions.txt; repositories are not snapshot-pinned.",
        "Boot / real-device Docker / Wi-Fi stability: NOT TESTED"]
source_dir = pathlib.Path(os.environ.get("KERNEL_SOURCE_DIR", "/buildd/sources"))
release_header = source_dir / "out/KERNEL_OBJ/include/config/kernel.release"
if release_header.exists():
    info.append("Actual kernelrelease: " + release_header.read_text().strip())
if (artifacts / "toolchain-version.txt").exists():
    info.append("Compiler:\n" + (artifacts / "toolchain-version.txt").read_text())
if (artifacts / "final.config").exists():
    config = (artifacts / "final.config").read_text()
    required = (project / "config/docker-required.txt").read_text().splitlines()
    info.append("Resolved Docker features:")
    for symbol in required:
        if symbol and not symbol.startswith("#"):
            match = re.search(r"^CONFIG_" + re.escape(symbol) + r"=(.*)$", config, re.M)
            info.append("CONFIG_" + symbol + "=" + (match[1] if match else "n"))
info.append("SHA256 (build-info.txt and SHA256SUMS excluded to avoid self-reference):")
hashes = []
for path in sorted(artifacts.rglob("*")):
    if path.is_file() and path.name not in {"build-info.txt", "SHA256SUMS", "release-notes.md"}:
        hasher = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                hasher.update(chunk)
        digest = hasher.hexdigest()
        hashes.append(digest + "  " + path.relative_to(artifacts).as_posix())
info.extend(hashes)
(artifacts / "SHA256SUMS").write_text("\n".join(hashes) + "\n")
(artifacts / "build-info.txt").write_text("\n".join(info) + "\n")
(artifacts / "release-notes.md").write_text(
    "# lavender Droidian Docker kernel\n\n"
    "Source: 9a2af00e9e2790ed12df6218236267e9bc7cf01e (droidian branch).\n\n"
    "Source Makefile: 4.4.156; upstream package/kernelrelease label: 4.4.192.\n\n"
    "Docker features: MEMCG, MEMCG_SWAP, CFS_BANDWIDTH, CGROUP_NET_PRIO; "
    "namespaces, overlayfs, bridge/veth/NAT, seccomp retained and verified.\n\n"
    "Build UTC: " + datetime.datetime.now(datetime.timezone.utc).isoformat() + "\n\n"
    "Download files under this release's Assets; SHA256SUMS lists checksums. "
    "See build-info.txt for compiler, dependencies and run link.\n\n"
    "**Experimental: static build verification does not prove device boot, "
    "Docker runtime compatibility or Wi-Fi reconnect stability.** Back up the "
    "current boot partition and working Droidian installation. Package auto-flashing "
    "is disabled; no vbmeta disabling image is supplied. Do not change partition "
    "layout or flash an unverified image without a recovery route.\n")
print("\n".join(info[:9]))
