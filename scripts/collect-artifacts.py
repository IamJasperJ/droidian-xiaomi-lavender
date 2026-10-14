#!/usr/bin/env python3
"""Collect actual Droidian outputs; successful build requires all validations."""
import gzip
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib


def check_elf(path):
    data = path.read_bytes()[:20]
    if data[:4] != b"\x7fELF" or data[4:6] != b"\x02\x01" or struct.unpack_from("<H", data, 18)[0] != 183:
        raise ValueError(f"Not little-endian AArch64 ELF: {path}")


def check_boot(path):
    data = path.read_bytes()
    if data[:8] != b"ANDROID!" or len(data) < 1648:
        raise ValueError("Invalid Android boot header")
    kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr, tags_addr, page, version = struct.unpack_from("<9I", data, 8)
    if (kernel_addr, ramdisk_addr, second_addr, tags_addr, page, version) != (0x8000, 0x1000000, 0xf00000, 0x100, 4096, 1):
        raise ValueError("Boot layout does not match pinned lavender kernel-info.mk")
    round_page = lambda size: (size + page - 1) // page * page
    recovery_size = struct.unpack_from("<I", data, 1632)[0]
    recovery_offset = struct.unpack_from("<Q", data, 1636)[0]
    header_size = struct.unpack_from("<I", data, 1644)[0]
    if header_size != 1648 or kernel_size == 0 or ramdisk_size == 0:
        raise ValueError("Missing kernel/initramfs or invalid v1 header size")
    minimum = page + round_page(kernel_size) + round_page(ramdisk_size) + round_page(second_size)
    if len(data) < minimum:
        raise ValueError("Truncated Android boot image")
    if recovery_size and (recovery_offset < minimum or recovery_offset + recovery_size > len(data)):
        raise ValueError("Truncated recovery DTBO")
    kernel = data[page:page + kernel_size]
    compressed = zlib.decompressobj(16 + zlib.MAX_WBITS)
    image = compressed.decompress(kernel) + compressed.flush()
    if not compressed.eof or image[56:60] != b"ARM\x64":
        raise ValueError("Boot kernel payload is not an ARM64 Image")
    # Official packaging concatenates Image.gz and the merged DTB. Validate
    # the appended FDT instead of treating it as another gzip member.
    dtb = compressed.unused_data
    if len(dtb) < 40 or dtb[:4] != b"\xd0\x0d\xfe\xed":
        raise ValueError("Boot kernel payload has no appended lavender DTB")
    dtb_size = struct.unpack_from(">I", dtb, 4)[0]
    if not 40 <= dtb_size <= len(dtb):
        raise ValueError("Truncated appended DTB")
    ramdisk_offset = page + round_page(kernel_size)
    ramdisk = gzip.decompress(data[ramdisk_offset:ramdisk_offset + ramdisk_size])
    if ramdisk[:6] not in (b"070701", b"070702"):
        raise ValueError("Boot initramfs is not gzip-compressed newc cpio")
    cmdline = data[64:576].split(b"\0")[0] + data[608:1632].split(b"\0")[0]
    if b"systemd.unified_cgroup_hierarchy=0" not in cmdline:
        raise ValueError("cgroup v1 boot argument missing")
    print(f"PASS boot header/layout, ARM64 payload and real initramfs: {path.name}")


def main():
    buildd, project, status = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), int(sys.argv[3])
    dest = buildd / "artifacts"
    dest.mkdir(exist_ok=True)
    kernel = buildd / "sources"
    obj = kernel / "out/KERNEL_OBJ"
    for patch in (project / "patches").glob("*.patch"):
        shutil.copy2(patch, dest / patch.name)
    shutil.copy2(project / "config/source.lock", dest / "source.lock")
    packages = sorted(buildd.glob("*.deb"))
    for deb in packages:
        shutil.copy2(deb, dest / deb.name)
    for name in (".config", "vmlinux", "boot.img"):
        path = obj / name
        if path.is_file():
            shutil.copy2(path, dest / ("final.config" if name == ".config" else name))
    image = obj / "arch/arm64/boot/Image.gz"
    if image.is_file():
        shutil.copy2(image, dest / "Image.gz")
    if status != 0:
        print(f"Build failed ({status}); partial outputs collected, no success marker")
        return status
    subprocess.run([sys.executable, str(project / "scripts/verify-config.py"), str(dest / "final.config"),
                    "--baseline", str(dest / "baseline.config")], check=True)
    check_elf(obj / "vmlinux")
    if gzip.decompress(image.read_bytes())[56:60] != b"ARM\x64":
        raise ValueError("Image.gz is not ARM64")
    modules = list(obj.rglob("*.ko"))
    if not modules:
        raise ValueError("BRIDGE_NETFILTER=m but no modules generated")
    for module in modules:
        check_elf(module)
    packaged_image = packaged_boot = packaged_modules = False
    for deb in packages:
        arch = subprocess.check_output(["dpkg-deb", "-f", str(deb), "Architecture"], text=True).strip()
        if arch != "arm64":
            raise ValueError(f"Wrong .deb architecture: {deb.name}: {arch}")
        name = subprocess.check_output(["dpkg-deb", "-f", str(deb), "Package"], text=True).strip()
        with tempfile.TemporaryDirectory() as tmp:
            extract = pathlib.Path(tmp) / "files"
            control = pathlib.Path(tmp) / "control"
            subprocess.run(["dpkg-deb", "-x", str(deb), str(extract)], check=True)
            subprocess.run(["dpkg-deb", "-e", str(deb), str(control)], check=True)
            if name.startswith("linux-image-4."):
                if not list((extract / "boot").glob("*")):
                    raise ValueError("Kernel package has no /boot payload")
                ko = list(extract.rglob("*.ko"))
                if not ko:
                    raise ValueError("Kernel package contains no modules")
                for module in ko:
                    check_elf(module)
                if not any(p.name == "br_netfilter.ko" for p in ko):
                    raise ValueError("br_netfilter module missing from package")
                packaged_image = packaged_modules = True
            if name.startswith("linux-bootimage-4."):
                boots = list((extract / "boot").glob("boot.img-*"))
                if len(boots) != 1:
                    raise ValueError("Boot package has no unique real boot.img")
                check_boot(boots[0])
                if boots[0].read_bytes() != (obj / "boot.img").read_bytes():
                    raise ValueError("Packaged boot image differs from build output")
                configs = list((extract / "lib/flash-bootimage").glob("*.conf"))
                if not configs or any("FLASH_ENABLED=no" not in p.read_text() for p in configs):
                    raise ValueError("Package auto-flashing is not disabled")
                for hook in control.glob("*"):
                    if hook.is_file() and "flash-bootimage" in hook.read_text(errors="replace"):
                        raise ValueError("Package control hook can invoke flashing")
                if list(extract.rglob("vbmeta.img*")):
                    raise ValueError("Unexpected vbmeta image")
                packaged_boot = True
    if not (packaged_image and packaged_boot and packaged_modules):
        raise ValueError("Required kernel, boot or module package payload missing")
    check_boot(dest / "boot.img")
    (dest / "BUILD_SUCCESS").write_text("Kernel, config, modules, .deb and boot image static validation passed.\nDevice boot/Wi-Fi/Docker not tested.\n")
    print("PASS: all required build artifacts validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
