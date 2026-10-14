# Droidian Docker kernel · Xiaomi lavender

为 Xiaomi Redmi Note 7（`lavender`、Snapdragon 660、ARM64）启用真正 Docker Engine 所需的内核配置。完整编译只在 **GitHub Actions / Ubuntu 24.04** 中运行，使用官方 Droidian amd64 构建容器、Android GCC 4.9 和 Debian 打包流程。

本项目保留 Android 厂商内核、Qualcomm WLAN 驱动、设备树、固件路径和原有硬件配置。未使用 postmarketOS 的主线 ath10k 方案。配置保留不等于已经证明 Wi-Fi 重连稳定。

## 源码和可复现性

- 上游：<https://github.com/droidian-devices/linux-android-xiaomi-lavender>
- 来源分支：`droidian`
- 固定提交：`9a2af00e9e2790ed12df6218236267e9bc7cf01e`
- Defconfig：`arch/arm64/configs/lavender_halium_defconfig`
- **实际 Makefile 基础版本：4.4.156**。
- **上游 Debian 打包版本标签：4.4.192**；官方打包规则以它设置 `KERNELRELEASE`。不能据此声称源码已包含 4.4.192 的全部修复。本项目暂保留该标签，构建信息同时记录两者和生成的实际 kernelrelease。
- 构建镜像：`quay.io/droidian/build-essential:trixie-amd64` 对应的固定 digest，见 `config/source.lock`。
- `original-lavender_halium_defconfig` 保存固定提交的原配置。

每次构建从指定分支获取源码，再检出固定 SHA。更新上游时必须重新检查补丁、Kconfig、设备打包配置和原配置校验，不能只修改 SHA。容器 digest 和源码固定；APT 仓库内容仍可变化，所以产物包含 `dependency-versions.txt`、实际编译器版本、构建容器信息和打包规则副本。当前尚不能保证不同日期得到逐字节一致的二进制文件。

参考：[Droidian 官方内核编译文档](https://docs.droidian.org/porting-guide/kernel-compilation/)、[官方打包工具](https://github.com/droidian/linux-packaging-snippets)。镜像 registry 已核对为 amd64；实际工具链安装和完整编译由 Actions 验证。

## 配置补丁

`patches/docker-kernel-config.patch` 启用：

| 配置 | 用途 / 依赖 |
| --- | --- |
| `CONFIG_MEMCG=y` | 内存限制，处于 CGROUPS 菜单下，自动选择 PAGE_COUNTER 和 EVENTFD；与原有 BLK_CGROUP 共同使隐藏的 CGROUP_WRITEBACK 默认启用 |
| `CONFIG_MEMCG_SWAP=y` | 内存加 swap 限制，需要 MEMCG 和原有 SWAP |
| `CONFIG_MEMCG_SWAP_ENABLED=y` | 默认启动 swap 记账；原启动参数没有关闭它 |
| `CONFIG_CFS_BANDWIDTH=y` | CPU quota，需要原有 FAIR_GROUP_SCHED / CGROUP_SCHED |
| `CONFIG_CGROUP_NET_PRIO=y` | 网络优先级 cgroup，需要原有 CGROUPS；按项目要求开启 |

原配置已启用 cgroup v1 所需控制器、Linux namespaces、USER_NS、OverlayFS、EXT4、tmpfs ACL/xattr、veth、bridge、IPv4 conntrack/NAT/masquerade、iptables、seccomp、keys 和消息队列。`BRIDGE_NETFILTER=m` 保持为模块，构建验证要求包内存在 `br_netfilter.ko`。完整强制检查项列在 `config/docker-required.txt`。

CI 先做 `git apply --check`，再用真实内核 Kconfig 解析原配置与修改后的配置；检查最终 `.config`，并拒绝超出上述配置及 MEMCG 自动依赖的变化。构建完成后再次检查配置，防止实际打包构建使用了另一套配置。修改源码中的无线驱动、设备树或固件不在本项目补丁范围内。

`patches/packaging-safety.patch` 独立处理打包：

- `FLASH_ENABLED=0`：生成的包不自动刷写手机。
- `DEVICE_VBMETA_REQUIRED=0`：不生成原规则中关闭验证的 vbmeta 镜像，不改变手机现有验证设置。
- 设置 `CLANG_CUSTOM=1` 并从 Build-Depends 去除未使用的 Android Clang 6；当前 snippets 不再自动加入未指定版本的 Clang 包。该设备始终使用原有 Android GCC 4.9，避免未使用的旧 Clang 引入 Trixie 已移除的 libtinfo5 依赖。

## 使用 GitHub Actions

1. 打开本仓库 **Actions → Build lavender Droidian Docker kernel → Run workflow**。
2. 第一次运行保持 `release=false`，默认并行任务为 2。可选择 1–4，内存不足时降低并行度。
3. 工作流使用 `ubuntu-24.04`，要求至少 20 GB 可用空间，最长 180 分钟。
4. CI 获取锁定的源码、检查补丁、拉取官方 digest 镜像、按设备配置生成 `debian/control` 并按官方 releng 方式安装 amd64 宿主 Build-Depends，以及显式标记 `:arm64` 的目标 initramfs。Android GCC/Python 工具包本身是 amd64，不能把它们误当成 arm64 包安装。
5. 在 `/buildd/sources` 执行 `RELENG_HOST_ARCH=arm64 releng-build-package`。不替换为新 GCC/Clang，不隐藏依赖安装或编译错误。
6. 构建和静态检查都成功才写入 `BUILD_SUCCESS`。命令失败会让 Actions 失败，尽可能保留诊断文件。

Ubuntu 24.04 是 runner；内核打包在官方 Trixie 容器中完成，避免直接用 Ubuntu 工具链编译旧 Android 内核。首次 CI 已发现固定官方镜像中的 Droidian 仓库公钥过旧，以及一个可选 Mobian 源的签名过期。`prepare-apt.sh` 用官方 keyring 仓库的固定提交更新容器密钥，并仅在构建容器内停用过期的可选 Mobian 源；保留 APT 签名验证。密钥来源、SHA256 和 fingerprint 见 `config/keyring-provenance.txt`，原始与有效源列表随 artifact 保存。依赖不存在、官方镜像不可用或旧源码与新宿主工具不兼容时，工作流明确失败；需要针对日志修复后重跑。

`release=true` 时，只有 build job 成功，独立 release job 才获得 `contents: write` 权限，创建带 run 编号的 **prerelease**，避免覆盖旧版本。Release 列出源码/打包版本、功能、时间及安装风险；下载文件位于该版本的 **Assets**。默认运行不发布 Release。

## 构建产物

在完成的 Actions run 底部 **Artifacts** 下载 `lavender-droidian-docker-kernel-N`，有效期为 30 天。失败 run 的同名 artifact 可能只有日志或部分产物，必须先检查 Actions 状态和 `build-info.txt`。

成功构建应包含：

- `linux-*.deb`：实际 ARM64 内核、模块、headers、bootimage 及元包。
- `boot.img`：来自官方设备打包规则，并与 bootimage `.deb` 中的镜像逐字节比对。
- `Image.gz` 和 `vmlinux`：检查 ARM64 Image 魔数 / AArch64 ELF 架构。
- `final.config`、`baseline.config`、`prebuild.config`、原 defconfig 和验证日志。
- Docker 和打包补丁、`build.log`、`build-info.txt`、`SHA256SUMS`。
- 编译器、依赖版本、容器、生成的 Debian 控制文件和实际 snippets。

`boot.img` 保留设备现有 v1 header、4096 page size、load offsets、启动命令行、Halium initramfs 和原 DTB/DTBO 合并流程。检查 header、大小、ARM64 payload、追加 DTB、initramfs 格式和 cgroup v1 参数。静态格式检查仍不能证明它在你的手机上成功启动；真机测试是独立阶段。脚本不凭空制作替代 boot.img，也不运行刷机命令。

下载解压后可执行 `sha256sum --check SHA256SUMS`。校验表不包含自身、build-info 和 release 文案，以避免自引用。

## 安装和恢复

首先确认设备确为 `lavender`，现有 Droidian 可以正常启动，记录 Android/vendor 固件版本。保存原 boot 分区备份、原 `.deb` 和系统备份，并在尝试新内核前验证你能进入现有 recovery / bootloader。备份必须来自自己的设备或完全匹配的已知可用镜像。

安装包已关闭自动刷写；仅安装 `.deb` 不代表 boot 分区已经更新。内核文件、模块和 boot 镜像必须来自同一次构建。具体安装路径应按你当前 Droidian 版本、启动方式和设备恢复流程核对，避免先破坏当前可用模块。不要更改分区布局、WLAN 固件或验证设置。

需要恢复时，用已验证的 recovery / bootloader 恢复原 boot 镜像，并恢复匹配的内核模块和软件包。无法确认备份和恢复路线时，应先停留在下载与检查阶段。此项目不自动刷写、不提供未经实机验证的刷机承诺。

## Docker 真机测试

Linux 4.4.156 是旧厂商内核。启用配置不能保证现代 Docker Engine / containerd / runc 的所有版本兼容。官方 [overlay2 文档](https://docs.docker.com/engine/storage/drivers/overlayfs-driver/)要求相应内核支持；4.4 的 overlay2 支持和厂商 backport 行为仍需实测。较新的 runtime 可能依赖旧内核缺少的 syscall、seccomp 行为或新 mount API。

不要直接装最新版并宣称兼容。优先核对当前 Droidian 仓库可用的 ARM64 Docker 组合，记录确切 Engine、containerd、runc 和 iptables 版本，实机测试通过后再固定。没有在本项目中指定一个未经测试的“保证兼容”版本。该源码配置以 cgroup v1 为目标，原 cmdline 已有 `systemd.unified_cgroup_hierarchy=0`，不强改为 v2。

本树启用了传统 iptables/NAT，但不应假定具备完整 nftables 支持。若 Docker 报 nf_tables/规则安装错误，先记录 `iptables --version`、Docker daemon 与内核日志，再核对 iptables legacy 后端和 Droidian 网络服务；不要盲目修改系统防火墙。检查 IPv4 forwarding、cgroup memory/cpu 挂载和 ext4 backing filesystem。`vfs` 可以临时诊断 overlay 不兼容，但占用更多存储，不能算 overlay2 测试通过。

内核成功启动并安装选定的 Docker stack 后，运行：

```bash
sudo bash scripts/test-docker.sh
```

前置工具：bash、coreutils/timeout、python3、kmod、util-linux/findmnt、curl、systemd/journalctl、Docker。脚本只连接本地 unix socket；检查 kernel config、控制器和 namespace，必要时启动已安装的 Docker service，运行 hello-world、ARM64 Alpine、NAT/DNS、内存/CPU 限额、存储写入、实际 storage driver 和 loopback 端口映射。资源测试读取容器内真实 cgroup 限额；它验证配置生效，不是长时压力测试。脚本返回非零表示未通过项，保存日志和镜像 ID/digest，退出时删除自己的端口测试容器。

默认镜像按请求使用 `alpine:latest`，它可能因新用户空间与旧内核不兼容而失败。需要复现时将已通过的 ARM64 镜像 digest 写入 `ALPINE_IMAGE` / `HELLO_IMAGE` 环境变量；不能把不同镜像的结果混称为同一次验证。

## Wi-Fi 切换实机验证

GitHub Actions 无法操作手机 WLAN，不能完成以下测试。先测原 Droidian 内核建立基线，再用同一固件、网络和手机测试候选内核。

1. 手机保持可用恢复路径。通过 USB 或本地终端记录日志，避免依赖被测 Wi-Fi 的 SSH 会话。
2. 分别开启 `sudo dmesg -wT | tee wifi-dmesg.log` 和 `sudo journalctl -b -f -o short-precise | tee wifi-journal.log`。
3. 使用 Droidian 现有 Wi-Fi 界面连接 A，切换 B，再切换 A；断开并重新连接；重启路由器后重新连接。建议每个序列重复至少 20 次，记录时间、SSID、结果和恢复方式。
4. 启动一个持续容器网络测试：`sudo docker run --rm alpine:latest sh -c 'while :; do date; ping -c 1 -W 3 1.1.1.1; sleep 2; done'`，运行期间重复上述切换。
5. 切换造成的短暂丢包可单独记录；重点检查重新连接后网络是否恢复，以及是否出现 `failed to remove key from hardware (-110)`、`remoteproc: crash detected`、WLAN subsystem restart 或必须重启手机的情况。
6. 出现崩溃时保留完整日志、内核 commit、固件、Docker 版本和切换次序，停止压力测试并恢复已知可用内核。成功也只代表该测试设备/固件/网络组合下的结果。

## 验证阶段与已知问题

| 阶段 | 通过依据 |
| --- | --- |
| 编译与配置 | Actions 绿色，最终 config 验证通过 |
| Debian 包与 boot 格式 | 模块/架构/payload 验证及 BUILD_SUCCESS |
| 手机启动 | 真机引导成功，匹配的模块可加载 |
| Docker | 本机 Engine、ARM64 容器、NAT、资源和存储测试通过 |
| Wi-Fi 稳定性 | 真机多次切换日志无崩溃，能恢复连接 |

已知限制：源码/打包版本不一致；旧 Android GCC 和 Droidian APT 依赖可能失效；依赖仓库没有快照固定；旧内核与现代 runtime 的兼容性待验证；构建成功不等于 boot 可启动或 Wi-Fi 稳定。macOS 默认大小写不敏感文件系统会让此源码中的大小写文件名冲突，不用于完整内核编译。

本项目的实际检查记录位于 `reports/`。Actions run 的最终状态、完整日志和产物是编译结果的依据；没有对应成功 run 时，不能将项目文件完成称为内核编译成功。
