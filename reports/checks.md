# Checks and CI attempts

Source pinned to 9a2af00e9e2790ed12df6218236267e9bc7cf01e.

- Local: both patches passed git apply --check and application against original pinned files.
- Local: all Bash scripts passed bash -n; Python helpers passed syntax compilation.
- Local: required symbols exist in source Kconfig and patched defconfig contains intended values. This is not a resolved .config result.
- Local: boot parser accepts synthetic gzip ARM64-header + appended FDT + cpio header and rejects damaged Android header, truncated image and wrong layout. Synthetic fixtures are not bootable device artifacts.
- CI #1 / 38546797416: failed before kernel compilation due to stale official-container Droidian keyring and expired optional Mobian signing key. Failure artifacts uploaded; release skipped.
- CI #2 / 38547959812: new Droidian keyring accepted and production package indices fetched. Failed before kernel compilation because optional Mobian deb822 source remained enabled. Failure artifacts uploaded; release skipped.
- Full original CI #2 job log: ci-run-38547959812-build.raw.log. SHA256 a3332e8da3c322efd89f0ca0bacef0c7850d9b3e10903d0fdd91986cd9704a45. Downloaded unchanged via GitHub View raw logs and supplied to Hermes for read-only verification.
- CI #3 / 38549986563: APT signature repair passed; dependency resolution failed at mk-build-deps because the previous command incorrectly requested an arm64 cross-build-deps package for amd64 Android host tools. The installation mode was corrected to match official releng (native host dependencies plus explicit :arm64 initramfs). Kernel compilation had not started.
- Full original CI #3 job log: ci-run-38549986563-build.raw.log. SHA256 21b161468649f3d73b9ac6f533a42508b60c98e298fb7cb7b61bac35c2231764. Saved unchanged and supplied to Hermes.
- CI #4 / 38551094126: dispatched at commit 6ec2df1 with release=false; result pending. Hermes is monitoring.
- Follow-up fixes: handle optional Mobian .sources entries, remove unused Android Clang dependency while keeping Android GCC 4.9, preserve chosen job count through CPU affinity, compare actual boot payload against compiled Image.gz + original merged DTB and official initramfs.

Linux vm130_complie has resolved baseline and modified defconfigs with ARCH=arm64 Kconfig using host GCC. All required Docker symbols resolved as intended. Effective differences: CFS_BANDWIDTH, CGROUP_NET_PRIO, MEMCG, MEMCG_SWAP, MEMCG_SWAP_ENABLED, PAGE_COUNTER, CGROUP_WRITEBACK. CGROUP_WRITEBACK is a hidden default-y symbol requiring MEMCG && the original BLK_CGROUP; the allowlist was corrected after inspecting init/Kconfig:1213. No wireless driver configuration difference was observed in this comparison. Exact official Android GCC resolution remains a separate CI check.

No successful ARM64 kernel build, .deb or boot.img has been reported yet. Real phone boot, Docker runtime and Wi-Fi switching remain untested.
