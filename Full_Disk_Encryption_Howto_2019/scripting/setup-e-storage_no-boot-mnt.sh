#!/bin/bash

##
#  License: Creative Cummons Attribution-ShareAlike 3.0 Unported
#           https://creativecommons.org/licenses/by-sa/3.0/legalcode
#  (c) https://help.ubuntu.com/community/Full_Disk_Encryption_Howto_2019
#
#  Article customization in case of no separated FS at '/boot' and with
#  another already preinstalled OS instance.
#
#  Initial partitions layout:
#   Number  Start (sector)    End (sector)  Size       Code  Name
#      1            2048          534527   260.0 MiB   EF00  EFI system partition
#      2          534528          796671   128.0 MiB   0C01  Vendor reserved ...
#      3          796672       123676671   58.6 GiB    0700  Basic data partition
#
#  Caution: be ready it may close shell on non zero return code under
#  certain usage circumstances.


lsblk

export DEV="/dev/sda"
export DM="${DEV##*/}"
export DEVP="${DEV}$( if [[ "$DEV" =~ "nvme" ]]; then echo "p"; fi )"
export DM="${DM}$( if [[ "$DM" =~ "nvme" ]]; then echo "p"; fi )"

export n_prt_grub=5
export n_prt_rootfs=6

sgdisk --print $DEV




function pre_install {
    set -xeu
    sgdisk --new=${n_prt_grub}:0:+2M $DEV  # GRUB
    sgdisk --new=${n_prt_rootfs}:0:0 $DEV  # Root FS
    sgdisk --typecode=${n_prt_grub}:ef02 --typecode=${n_prt_rootfs}:8301 $DEV
    sgdisk --change-name=${n_prt_grub}:GRUB --change-name=${n_prt_rootfs}:rootfs $DEV

    #sgdisk --hybrid 1:2:3 $DEV

    sgdisk --print $DEV

    wipefs -a $DEVP${n_prt_rootfs}

    cryptsetup luksFormat --batch-mode --type=luks1 ${DEVP}${n_prt_rootfs}
    cryptsetup open ${DEVP}${n_prt_rootfs} ${DM}${n_prt_rootfs}_crypt

    pvcreate /dev/mapper/${DM}${n_prt_rootfs}_crypt
    vgcreate ubuntu-vg /dev/mapper/${DM}${n_prt_rootfs}_crypt
    lvcreate -l 80%FREE -n root ubuntu-vg
}


function setup_grub_trap_while_install {
    set -xeu
    while [ ! -d /target/etc/default/grub.d ]; do sleep 1; done; echo "GRUB_ENABLE_CRYPTODISK=y" > /target/etc/default/grub.d/local.cfg
}


function post_install {
    set -xeu
    if ! mountpoint /target ; then
        mount /dev/mapper/ubuntu--vg-root /target
    fi

    for n in proc sys dev etc/resolv.conf; do
        if ! mountpoint /target/$n ; then
            mount --rbind /$n /target/$n
        fi
    done

    chroot /target mount -a
    chroot /target apt install -y cryptsetup-initramfs
    chroot /target bash -c "echo KEYFILE_PATTERN=/etc/luks/*.keyfile >> /etc/cryptsetup-initramfs/conf-hook"
    chroot /target bash -c "echo UMASK=0077 >> /etc/initramfs-tools/initramfs.conf"
    chroot /target mkdir -p /etc/luks
    chroot /target dd if=/dev/urandom of=/etc/luks/boot_os.keyfile bs=512 count=1
    chroot /target chmod u=rx,go-rwx /etc/luks
    chroot /target chmod u=r,go-rwx /etc/luks/boot_os.keyfile
    chroot /target cryptsetup luksAddKey "${DEVP}${n_prt_rootfs}" /etc/luks/boot_os.keyfile

    chroot /target bash -c "echo '${DM}${n_prt_rootfs}_crypt UUID=$(blkid -s UUID -o value ${DEVP}${n_prt_rootfs}) /etc/luks/boot_os.keyfile luks,discard' >> /etc/crypttab"

    chroot /target update-initramfs -u -k all
}


