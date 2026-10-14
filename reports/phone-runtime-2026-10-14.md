# Lavender 定制内核刷入及 Docker 真机验证

2026-10-14 已完成定制内核刷入、首次启动和 Docker 真机测试。运行的是 `4.4.192-xiaomi-lavender`，构建时间为 2026-10-14 11:24:28 UTC。Docker 测试失败数为 **0**。

## 结果对比

| 项目 | 官方内核 | 定制内核 |
|---|---|---|
| Docker 服务、ARM64 容器 | 通过 | 通过 |
| OverlayFS 可写存储 | 通过 | 通过 |
| 容器外网、DNS、端口映射 | 配置 AppArmor 兼容策略后通过 | 通过 |
| 49 项目标内核配置 | 44 项通过、5 项缺失 | 49 项全部通过 |
| 64 MiB 内存上限、0.5 核 CPU 配额 | 不支持完整限制 | 容器内实际值检查通过 |
| CPU 配额实际节流 | 不支持 CFS 配额 | 3 秒负载测试中 32 个周期发生节流 |
| 超过内存上限时的行为 | 内存控制器缺失 | 测试容器被 cgroup OOM 终止，OOMKilled=true，退出码 137 |

Wi-Fi 在新内核启动后连接成功，SSH 自动恢复；Phosh、NetworkManager、Docker 和 containerd 服务均处于 active。尚未独立观察手机屏幕，也没有完成长时间待机、休眠及反复切换 Wi-Fi 的稳定性测试。

## 实际测试组合

- Docker 20.10.24+dfsg1
- containerd 1.6.20
- runc 1.1.5
- ARM64 `hello-world:latest`、`alpine:3.20` 和 `busybox:1.36`
- 存储驱动 overlay2，cgroup v1
- 64 MiB 内存、64 MiB memory-swap（总上限，禁止容器额外使用交换空间），CPU quota/period = 50000/100000 微秒

容器测试镜像从官方 Docker Hub 获取后，经 Mac 局域网导入手机。联网测试实际经过容器桥接 NAT，并成功访问外网和解析域名。

旧 Android 厂商内核的 AppArmor 网络策略格式与新解析器默认格式不匹配，初次测试出现 socket 权限拒绝。现已保留 Docker 20.10.24 的原有禁止规则，显式选择兼容网络 ABI 并允许 Unix socket；配置存放于 `/etc/apparmor.d/docker-lavender-compat`，Docker 启动前自动加载。实测容器配置为 `docker-default (enforce)`，未使用 privileged 或关闭整个 AppArmor。

## 刷写及回退资料

已安装同一次构建的内核及 bootimage 软件包，bootloader 实际写入的分区为 boot。镜像 SHA256：

`b21e362941e7d75c1c600de3c9e7c96039c0aa728e84083e3910733d9dd6e771`

手机 boot 分区读取出的对应镜像内容再次验证匹配此哈希。运行内核配置也与构建 final.config 逐字节一致：

`cde9d58b6bb7ffef39c6d6ead6c444d6bf4a3cce33cdfc1973e94a1213542738`

官方内核回退资料保存在用户 Mac 的本地 `outputs/droidian-installation/official-kernel-backup/`：当前 boot 分区完整 64 MiB 备份、原模块及 /boot 文件、包元数据和校验清单。手机 `/opt/lavender-kernel-switch/official-backup/` 也保留了一份。回退需要恢复匹配的模块与 boot；不要仅换回 boot 后继续使用定制模块。

SSH 密钥服务已配置开机启动，密码登录和 root SSH 登录均禁用。Docker 已配置开机启动。

## 验证范围

这次验证证明上述 Docker 20.10.24 组合正常运行。新版 Docker/containerd/runc 仍需单独验证。源代码 Makefile 基础版本为 4.4.156，运行及打包版本标签为 4.4.192；标签不代表包含该版本全部主线修复。Docker 仍提示不支持块设备 I/O 带宽/IOPS 限制以及内核 TCP 内存限制，这些属于本次目标以外的功能。

完整测试输出、限额执行证据及刷写日志保存在用户 Mac 的 `outputs/droidian-installation/custom-kernel/`，对应文件为 `runtime-console.log`、`enforcement.log` 和 `flash.log`。备份、包数据库及完整系统日志未上传此仓库。原始构建 provenance 保留原貌，真机验证通过没有修改原始编译记录。
