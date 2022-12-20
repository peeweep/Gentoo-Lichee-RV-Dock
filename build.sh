#!/bin/bash

# clean rootfs
if [ -d gentoo ] ; then 
  sudo rm -rfv gentoo
fi
sudo mkdir -pv gentoo

# rootfs way1: build by crossdev
# sudo PORTAGE_CONFIGROOT=/usr/riscv64-unknown-linux-gnu eselect profile set default/linux/riscv/20.0/rv64gc/lp64d/systemd
# sudo riscv64-unknown-linux-gnu-emerge --ask `cat world `

# rootfs way2: use stage3 (for quick test)
if [ ! -f ./stage3-rv64_lp64d-systemd-20221216T100220Z.tar.xz ] ; then
  # wget https://mirror.init7.net/gentoo/releases/riscv/autobuilds/current-stage3-rv64_lp64d-systemd/stage3-rv64_lp64d-systemd-20221216T100220Z.tar.xz
  wget https://mirrors.bfsu.edu.cn/gentoo/releases/riscv/autobuilds/current-stage3-rv64_lp64d-systemd/stage3-rv64_lp64d-systemd-20221216T100220Z.tar.xz
fi
pushd gentoo
  sudo tar xpvf ../stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
  sudo sed -i -e "s/^root:[^:]\+:/root:`openssl passwd -1 -salt root licheerv`:/" ./etc/shadow
popd



mkdir -pv build
pushd build

CROSS="CROSS_COMPILE=riscv64-unknown-linux-gnu-"

# build opensbi
git clone --depth 1 https://github.com/riscv-software-src/opensbi
pushd opensbi
make $CROSS PLATFORM=generic FW_PIC=y FW_OPTIONS=0x2 # build/opensbi/build/platform/generic/firmware/fw_dynamic.bin
popd

# build kernel
git clone --depth 1 --branch d1/all https://github.com/smaeul/linux

pushd linux
git checkout b466df9
#  make defconfig
cp ../../kernel/update_kernel_config.sh .
./update_kernel_config.sh defconfig
make ARCH=riscv $CROSS O=../linux-build defconfig
popd

make ARCH=riscv $CROSS -C linux-build -j $(nproc) # build/linux-build/arch/riscv/boot/Image.gz
sudo make ARCH=riscv $CROSS -C linux-build INSTALL_MOD_PATH=../gentoo modules_install

# Build u-boot
git clone --depth 1 --branch d1-wip https://github.com/smaeul/u-boot.git

pushd u-boot
cp -v ../../kernel/update_uboot_config.sh .
./update_uboot_config.sh lichee_rv_dock_defconfig
make $CROSS lichee_rv_dock_defconfig
make $CROSS -j $(nproc) all OPENSBI=../opensbi/build/platform/generic/firmware/fw_dynamic.bin # build/u-boot/arch/riscv/dts/sun20i-d1-lichee-rv-dock.dtb
popd

./u-boot/tools/mkimage -T script -C none -O linux -A riscv -d ../config/bootscr_lichee_rv_dock.txt boot.scr

popd

sudo ./create_image.sh output
