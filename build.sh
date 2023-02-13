#!/bin/bash

git submodule update --init

# clean rootfs
sudo rm -rf gentoo build output
sudo mkdir -pv gentoo

# rootfs way1: build by crossdev
# sudo PORTAGE_CONFIGROOT=/usr/riscv64-unknown-linux-gnu eselect profile set default/linux/riscv/20.0/rv64gc/lp64d/systemd
# sudo riscv64-unknown-linux-gnu-emerge --ask `cat world `

# rootfs way2: use stage3 (for quick test)
if [ ! -f ./stage3-*.tar.xz ]; then
  export download_url_prefix=https://distfiles.gentoo.org/releases/riscv/autobuilds
  export latest_stage3_path=$(curl -sSL ${download_url_prefix}/latest-stage3.txt | grep stage3-rv64_lp64d-systemd | awk '{ print $1 }' | head -n 1)
  wget ${download_url_prefix}/${latest_stage3_path}
fi
pushd gentoo
sudo tar xpf ../stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
sudo sed -i -e "s/^root:[^:]\+:/root:$(openssl passwd -1 -salt root licheerv):/" ./etc/shadow
sudo rm -rf ./var/db/repos/gentoo
popd

mkdir -pv build
pushd build

CROSS="CROSS_COMPILE=riscv64-unknown-linux-gnu-"

# build opensbi
git clone ../kernel/opensbi opensbi
pushd opensbi
make $CROSS PLATFORM=generic FW_PIC=y FW_OPTIONS=0x2 # build/opensbi/build/platform/generic/firmware/fw_dynamic.bin
popd

# build kernel

build_smaeul_kernel() {
  git clone ../kernel/smaeul-linux linux

  pushd linux
  cp ../../kernel/update_kernel_config.sh .
  ./update_kernel_config.sh defconfig
  make ARCH=riscv $CROSS O=../linux-build defconfig
  popd

  make ARCH=riscv $CROSS -C linux-build -j $(nproc) # build/linux-build/arch/riscv/boot/Image.gz
  sudo make ARCH=riscv $CROSS -C linux-build INSTALL_MOD_PATH=../../gentoo modules_install
}

build_thead_kernel() {
  toolchain_tarball="Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.1-20220906.tar.gz"
  if [ ! -f ../${toolchain_tarball} ]; then
    pushd ..
    wget https://occ-oss-prod.oss-cn-hangzhou.aliyuncs.com/resource//1663142514282/Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.1-20220906.tar.gz
    popd
  fi
  tar xf ../${toolchain_tarball}

  local PATH=$(realpath ./Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.1/bin):$PATH
  git clone ../kernel/thead-linux linux

  pushd linux
  cp ../../kernel/update_kernel_config.sh .
  ./update_kernel_config.sh vector_0_7_defconfig
  make ARCH=riscv $CROSS O=../linux-build vector_0_7_defconfig
  popd

  make ARCH=riscv $CROSS -C linux-build -j $(nproc) # build/linux-build/arch/riscv/boot/Image.gz
  sudo make ARCH=riscv $CROSS -C linux-build INSTALL_MOD_PATH=../../gentoo modules_install
}

build_smaeul_kernel

# Build u-boot
git clone ../kernel/smaeul-uboot u-boot
pushd u-boot
cp -v ../../kernel/update_uboot_config.sh .
./update_uboot_config.sh lichee_rv_dock_defconfig
make $CROSS lichee_rv_dock_defconfig
make $CROSS -j $(nproc) all OPENSBI=../opensbi/build/platform/generic/firmware/fw_dynamic.bin # build/u-boot/arch/riscv/dts/sun20i-d1-lichee-rv-dock.dtb
popd

./u-boot/tools/mkimage -T script -C none -O linux -A riscv -d ../config/bootscr_lichee_rv_dock.txt boot.scr

popd

sudo ./create_image.sh output
