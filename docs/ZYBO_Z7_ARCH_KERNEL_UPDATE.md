# Updating the Arch Linux ARM Kernel on a Zybo Z7-20

This document describes how to repeat the kernel update process for Arch Linux
ARM on a Zybo Z7-20 using the prebuilt `linux-armv7` package, while keeping the
existing PetaLinux `BOOT.BIN` so the FSBL, U-Boot, and FPGA bitstream remain
unchanged.

## Context

- The SD card boot partition is usually mounted at `/mnt`.
- The current boot flow uses `BOOT.BIN` plus `image.ub`.
- `BOOT.BIN` contains the boot chain and FPGA bitstream. Do not replace this
  file when only updating the Linux kernel.
- `image.ub` is a U-Boot FIT image containing the kernel and device tree.
- The Arch Linux ARM root filesystem is on `/dev/mmcblk0p2`.
- The boot partition is on `/dev/mmcblk0p1`.
- The FPGA design exposes an AXI memory-mapped peripheral:

```dts
user_io@43c00000 {
	compatible = "generic-uio";
	status = "okay";
	interrupt-parent = <&intc>;
	interrupts = <0x00 0x1d 0x04>;
	reg = <0x43c00000 0x1000>;
};
```

The kernel command line must also preserve:

```text
console=ttyPS0,115200 earlyprintk uio_pdrv_genirq.of_id=generic-uio root=/dev/mmcblk0p2 rw rootwait
```

## Goal

Generate a new `/mnt/image.ub` from the Arch Linux ARM prebuilt `linux-armv7`
package, preserve the custom device tree node for the AXI peripheral, and
install the matching kernel modules into the SD card root filesystem.

## Host Dependencies

Required tools:

```bash
curl
bsdtar
dtc
fdtoverlay
fdtget
mkimage
dumpimage
depmod
ssh
```

On Arch Linux, `mkimage` and `dumpimage` are provided by `uboot-tools`; `dtc`,
`fdtoverlay`, and `fdtget` are provided by `dtc`.

## 1. Inspect the Current Boot Files

```bash
find /mnt -maxdepth 2 -type f -printf '%p\n' | sort
file /mnt/BOOT.BIN /mnt/image.ub
dumpimage -l /mnt/image.ub
```

Expected files:

```text
/mnt/BOOT.BIN
/mnt/image.ub
```

The old `image.ub` should contain at least one `kernel@0` image and one
`fdt@0` image.

Extract and decompile the old DTB to confirm the custom details:

```bash
mkdir -p build
dumpimage -T flat_dt -p 1 -o build/old.dtb /mnt/image.ub
dtc -I dtb -O dts -o build/old.dts build/old.dtb
grep -n -A10 -B5 'user_io@43c00000' build/old.dts
grep -n -A3 'bootargs' build/old.dts
```

## 2. Download the Prebuilt Kernel

Use the Arch Linux ARM `linux-armv7` package for `armv7h`. Check the official
package or mirror to find the latest available version, then adjust `KPKG` and
`KVER`.

Example used in June 2026:

```bash
KPKG=linux-armv7-7.1.1-1-armv7h.pkg.tar.xz
KVER=7.1.1-1-armv7-ARCH

curl -L -o /tmp/$KPKG http://mirror.archlinuxarm.org/armv7h/core/$KPKG
curl -L -o /tmp/$KPKG.sig http://mirror.archlinuxarm.org/armv7h/core/$KPKG.sig
```

If possible, verify the package signature with the Arch Linux ARM keyring. If
the host does not have that keyring, verify it from a trusted Arch Linux ARM
installation.

Confirm that the package contains the needed files:

```bash
bsdtar -tf /tmp/$KPKG | grep -E '^boot/zImage$|^boot/dtbs/zynq-zybo-z7\.dtb$|^usr/lib/modules/'
bsdtar -xOf /tmp/$KPKG .PKGINFO | sed -n '1,80p'
```

## 3. Extract the Kernel and Base DTB

```bash
bsdtar -xOf /tmp/$KPKG boot/zImage > build/zImage-$KVER
bsdtar -xOf /tmp/$KPKG boot/dtbs/zynq-zybo-z7.dtb > build/zynq-zybo-z7-base.dtb
```

## 4. Create the Device Tree Overlay

Create `build/zybo-z7-uio-overlay.dts`:

```dts
/dts-v1/;
/plugin/;

/ {
	fragment@0 {
		target-path = "/chosen";

		__overlay__ {
			bootargs = "console=ttyPS0,115200 earlyprintk uio_pdrv_genirq.of_id=generic-uio root=/dev/mmcblk0p2 rw rootwait";
			stdout-path = "serial0:115200n8";
		};
	};

	fragment@1 {
		target-path = "/";

		__overlay__ {
			#address-cells = <0x01>;
			#size-cells = <0x01>;

			user_io@43c00000 {
				compatible = "generic-uio";
				status = "okay";
				interrupt-parent = <&intc>;
				interrupts = <0x00 0x1d 0x04>;
				reg = <0x43c00000 0x1000>;
			};
		};
	};
};
```

Compile and apply the overlay:

```bash
dtc -@ -I dts -O dtb -o build/zybo-z7-uio.dtbo build/zybo-z7-uio-overlay.dts
fdtoverlay \
  -i build/zynq-zybo-z7-base.dtb \
  -o build/zynq-zybo-z7-arch-uio.dtb \
  build/zybo-z7-uio.dtbo
```

Verify the final DTB:

```bash
fdtget -t s build/zynq-zybo-z7-arch-uio.dtb / compatible
fdtget -t s build/zynq-zybo-z7-arch-uio.dtb /chosen bootargs
fdtget -t s build/zynq-zybo-z7-arch-uio.dtb /user_io@43c00000 compatible
fdtget -t x build/zynq-zybo-z7-arch-uio.dtb /user_io@43c00000 reg
fdtget -t x build/zynq-zybo-z7-arch-uio.dtb /user_io@43c00000 interrupts
```

Expected values:

```text
compatible: digilent,zynq-zybo-z7 xlnx,zynq-7000
bootargs: console=ttyPS0,115200 earlyprintk uio_pdrv_genirq.of_id=generic-uio root=/dev/mmcblk0p2 rw rootwait
user_io compatible: generic-uio
reg: 43c00000 1000
interrupts: 0 1d 4
```

## 5. Generate the New FIT Image

Create `build/archlinuxarm-zybo-z7.its`.

Replace the `zImage-...` filename with the actual `KVER` value:

```dts
/dts-v1/;

/ {
	description = "U-Boot fitImage for Arch Linux ARM on Zybo Z7";
	#address-cells = <1>;

	images {
		kernel@0 {
			description = "Linux ARMv7 kernel";
			data = /incbin/("zImage-7.1.1-1-armv7-ARCH");
			type = "kernel";
			arch = "arm";
			os = "linux";
			compression = "none";
			load = <0x00008000>;
			entry = <0x00008000>;

			hash@1 {
				algo = "sha1";
			};
		};

		fdt@0 {
			description = "Zybo Z7 device tree with generic-uio AXI device";
			data = /incbin/("zynq-zybo-z7-arch-uio.dtb");
			type = "flat_dt";
			arch = "arm";
			compression = "none";

			hash@1 {
				algo = "sha1";
			};
		};
	};

	configurations {
		default = "conf@0";

		conf@0 {
			description = "Boot Linux kernel with FDT blob";
			kernel = "kernel@0";
			fdt = "fdt@0";
		};
	};
};
```

Generate and inspect it:

```bash
mkimage -f build/archlinuxarm-zybo-z7.its build/image.ub
dumpimage -l build/image.ub
```

Confirm:

- `Architecture: ARM`
- `OS: Linux`
- `Load Address: 0x00008000`
- `Entry Point: 0x00008000`
- A `flat_dt` image exists
- The default configuration points to both the kernel and FDT

## 6. Install to the SD Card

Mount the boot partition at `/mnt` and mount the root filesystem if it is not
already mounted.

The manual steps below assume:

- boot partition: `/mnt`
- root partition: `/dev/mmcblk0p2`
- package: `/tmp/$KPKG`
- generated FIT image: `build/image.ub`

```bash
sudo mount -o remount,rw /mnt

sudo mkdir -p /tmp/zybo-root
sudo mount /dev/mmcblk0p2 /tmp/zybo-root

stamp=$(date +%Y%m%d-%H%M%S)
sudo cp -a /mnt/image.ub /mnt/image.ub.petalinux-2019.$stamp.bak
sudo cp build/image.ub /mnt/image.ub

sudo bsdtar -xpf /tmp/$KPKG -C /tmp/zybo-root "usr/lib/modules/$KVER"
sudo depmod -b /tmp/zybo-root -m /usr/lib/modules "$KVER"

sudo mkdir -p /tmp/zybo-root/etc/modprobe.d /tmp/zybo-root/etc/modules-load.d
printf 'options uio_pdrv_genirq of_id=generic-uio\n' | sudo tee /tmp/zybo-root/etc/modprobe.d/uio_pdrv_genirq.conf
printf 'uio_pdrv_genirq\n' | sudo tee /tmp/zybo-root/etc/modules-load.d/uio_pdrv_genirq.conf

sync
```

The `depmod -m /usr/lib/modules` argument matters when the mounted root tree
does not expose `/lib -> usr/lib` the same way the target system does.

## 7. Reboot and Verify

After the Zybo boots, connect over SSH:

```bash
ssh alarm@10.42.0.40
```

Check the kernel and command line:

```bash
uname -a
cat /proc/cmdline
```

Check UIO and the device tree:

```bash
ls -l /dev/uio* /dev/uio/
lsmod | grep -E '(^uio|uio_pdrv_genirq)'

tr '\0' ' ' < /proc/device-tree/user_io@43c00000/compatible; echo
tr '\0' ' ' < /proc/device-tree/user_io@43c00000/status; echo
od -An -tx4 -v /proc/device-tree/user_io@43c00000/reg
od -An -tx4 -v /proc/device-tree/user_io@43c00000/interrupts

for d in /sys/class/uio/uio*; do
  echo "$d"
  cat "$d/name"
  cat "$d/maps/map0/addr"
  cat "$d/maps/map0/size"
  readlink -f "$d/device"
done

find /sys/bus/platform/devices -maxdepth 1 -type l -name '*43c00000*' -print
readlink -f /sys/bus/platform/devices/43c00000.user_io/driver
cat /sys/bus/platform/devices/43c00000.user_io/modalias
```

Expected result:

```text
/dev/uio0
/dev/uio/user_io@43c00000 -> ../uio0
uio_pdrv_genirq loaded
map0 addr: 0x43c00000
map0 size: 0x00001000
driver: /sys/bus/platform/drivers/uio_pdrv_genirq
modalias: of:Nuser_ioT(null)Cgeneric-uio
```

Check user permissions:

```bash
id alarm
stat -c '%A %U %G %n' /dev/uio0 /dev/uio/user_io@43c00000
test -r /dev/uio0 && test -w /dev/uio0 && echo alarm-can-open-uio0
```

The `alarm` user should be a member of the `uio` group.

## 8. Common Problems

### systemd Fails to Mount `/proc`, `/sys`, or `/dev`

Symptom:

```text
systemd[1]: Failed to determine whether /proc is a mount point: Protocol driver not attached
[!!!!!!] Failed to mount early API filesystems.
```

This usually means the kernel is too old for the current userspace. Update the
kernel and matching modules using the process above.

### `/dev/uio0` Does Not Appear

Check:

```bash
cat /proc/cmdline
lsmod | grep uio
find /proc/device-tree -maxdepth 2 -name 'user_io@43c00000' -print
dmesg | grep -Ei 'uio|generic-uio|43c00000'
```

Possible causes:

- `uio_pdrv_genirq.of_id=generic-uio` is missing from `/proc/cmdline`.
- The `uio_pdrv_genirq` module is not installed for the running kernel.
- `/etc/modules-load.d/uio_pdrv_genirq.conf` is missing.
- The overlay was not applied to the final DTB.
- The AXI peripheral address or IRQ changed in the bitstream.

### Kernel Boots but Modules Are Missing

Confirm that the `uname -r` version exists under `/usr/lib/modules`:

```bash
uname -r
ls /usr/lib/modules
```

If it is missing, reinstall the matching `linux-armv7` package modules and run:

```bash
depmod -a "$(uname -r)"
```

### Filesystem Warnings in `dmesg`

If you see:

```text
EXT4-fs: warning: mounting unchecked fs, running e2fsck is recommended
FAT-fs: Volume was not properly unmounted
```

Run `fsck` on the SD card partitions while they are unmounted.
