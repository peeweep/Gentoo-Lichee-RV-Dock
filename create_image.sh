#!/bin/bash
#
# Author. Tim Molteno tim@molteno.net
# (C) 2022.
# http://www.orangepi.org/Docs/Makingabootable.html

# Make Image the first parameter of this script is the directory containing all the files needed
# This is done to allow the script to be run outside of Docker for testing.
OUTPORT=$1

mkdir -pv ${OUTPORT}

KERNEL_TAG="d1/all"
KERNEL_TAG="$(echo ${KERNEL_TAG} | tr '/' '_')"
IMG_NAME="lichee_rv_dock_kernel_${KERNEL_TAG}.img"
IMG=${OUTPORT}/${IMG_NAME}

echo "Creating Blank Image ${IMG}"

dd if=/dev/zero of=${IMG} bs=1M count=5000

# Setup Loopback device
LOOP=`losetup -f --show ${IMG} | cut -d'/' -f3`
LOOPDEV=/dev/${LOOP}
echo "Partitioning loopback device ${LOOPDEV}"


# dd if=/dev/zero of=${LOOPDEV} bs=1M count=200
parted -s -a optimal -- ${LOOPDEV} mklabel gpt
parted -s -a optimal -- ${LOOPDEV} mkpart primary ext2 40MiB 100MiB
parted -s -a optimal -- ${LOOPDEV} mkpart primary ext4 100MiB -1GiB
parted -s -a optimal -- ${LOOPDEV} mkpart primary linux-swap -1GiB 100%

kpartx -av ${LOOPDEV} # kaprtx in multipath-tools

mkfs.ext2 /dev/mapper/${LOOP}p1
mkfs.ext4 /dev/mapper/${LOOP}p2
mkswap /dev/mapper/${LOOP}p3

# Burn U-boot
echo "Burning u-boot to ${LOOPDEV}"

# Copy files https://linux-sunxi.org/Allwinner_Nezha
dd if=build/u-boot/u-boot-sunxi-with-spl.bin of=${LOOPDEV} bs=1024 seek=128

# Copy Files, first the boot partition
echo "Mounting  partitions ${LOOPDEV}"
BOOTPOINT="boot"

mkdir -p ${BOOTPOINT}
mount /dev/mapper/${LOOP}p1 ${BOOTPOINT}

# Boot partition
cp build/linux-build/arch/riscv/boot/Image.gz "${BOOTPOINT}/"

# install U-Boot
cp build/boot.scr "${BOOTPOINT}/"
cp build/u-boot/arch/riscv/dts/sun20i-d1-lichee-rv-dock.dtb "${BOOTPOINT}/"

umount ${BOOTPOINT}
rm -rf ${BOOTPOINT}


# Now create the root partition
MNTPOINT="rootfs"
mkdir -p ${MNTPOINT}
mount /dev/mapper/${LOOP}p2 ${MNTPOINT}

# Copy the rootfs
cp -a gentoo/* ${MNTPOINT}


# Set up fstab
cat >> "${MNTPOINT}/etc/fstab" <<EOF
# <device>        <dir>        <type>        <options>            <dump> <pass>
/dev/mmcblk0p1    /boot        ext2          rw,defaults,noatime  1      1
/dev/mmcblk0p2    /            ext4          rw,defaults,noatime  1      1
/dev/mmcblk0p3    none         swap          sw                   0      0
EOF

# Clean Up
echo "Cleaning Up..."
umount ${MNTPOINT}
rm -rf ${MNTPOINT}

kpartx -d ${LOOPDEV}
losetup -d ${LOOPDEV}

# Now compress the image
echo "Compressing the image: ${IMG}"

(cd ${OUTPORT}; xz -T0 ../${IMG})
