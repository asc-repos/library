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

PS4="+:\$( basename \"\${0}\" ):\${LINENO}: "
set -xeu

lsblk

export DEV="/dev/sda"  # /dev/sda  /dev/nvme0n1
#export DEV="/dev/nvme0n1"  # /dev/sda  /dev/nvme0n1

export DM="${DEV##*/}"
export DEVP="${DEV}$( if [[ "$DEV" =~ "nvme" ]]; then echo "p"; fi )"
export DM="${DM}$( if [[ "$DM" =~ "nvme" ]]; then echo "p"; fi )"

export n_prt_grub=5
export n_prt_rootfs=6

declare -r phys_lv_name="${DM}${n_prt_rootfs}_crypt"
declare -r dev_for_encrypt="${DEVP}${n_prt_rootfs}"

###
##  Actions-functions, one per installation stage.
#

function pre_install {
    set -xeu
    sgdisk --new=${n_prt_grub}:0:+2M $DEV  # GRUB
    sgdisk --new=${n_prt_rootfs}:0:0 $DEV  # Root FS
    sgdisk --typecode=${n_prt_grub}:ef02 --typecode=${n_prt_rootfs}:8301 $DEV
    sgdisk --change-name=${n_prt_grub}:GRUB --change-name=${n_prt_rootfs}:rootfs $DEV

    #sgdisk --hybrid 1:2:3 $DEV

    sgdisk --print $DEV

    wipefs -a $DEVP${n_prt_rootfs}

    cryptsetup luksFormat --batch-mode --type=luks1 ${dev_for_encrypt}
    cryptsetup open ${dev_for_encrypt} ${phys_lv_name}

    pvcreate /dev/mapper/${phys_lv_name}
    vgcreate ubuntu-vg /dev/mapper/${phys_lv_name}
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
    chroot /target cryptsetup luksAddKey "${dev_for_encrypt}" /etc/luks/boot_os.keyfile

    chroot /target bash -c "echo '${phys_lv_name} UUID=$(blkid -s UUID -o value ${dev_for_encrypt}) /etc/luks/boot_os.keyfile luks,discard' >> /etc/crypttab"

    chroot /target update-initramfs -u -k all
}

###
##
#

declare -r action="$( whiptail \
    --separate-output \
    --notags \
    --radiolist \
    "Select action:" \
    25 75 15 \
    pre_install                     "1 - create partitions "        OFF \
    setup_grub_trap_while_install   "2 - catch Grub and set it up " OFF \
    post_install                    "3 - attach FS unlock "         OFF \
        3>&2 2>&1 1>&3 )"  # This variable contains name of a function to be called later. Here is selector of an action to be called in sync. with external set up process.

test -n "${action}"
set | egrep --quiet "^${action} ()"  # Check whether the function declared.

if ! whiptail --yesno --defaultno "Execute '${action}' ?" 8 78 ; then
    set +x
    echo "INFO:$( basename "${0}" ):${LINENO}: Do nothing. User canceled." >&2
    exit 0
fi

###
##
#

test -e "${DEV}"
sgdisk --print $DEV

"${action}"

set +x
echo "INFO:$( basename "${0}" ):${LINENO}: Job done." >&2
