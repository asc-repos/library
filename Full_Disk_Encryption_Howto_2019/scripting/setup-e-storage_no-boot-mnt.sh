#!/bin/bash

##
#  License: Creative Cummons Attribution-ShareAlike 3.0 Unported
#           https://creativecommons.org/licenses/by-sa/3.0/legalcode
#  (c) https://help.ubuntu.com/community/Full_Disk_Encryption_Howto_2019
#
#  Article customization in case of no separated FS at '/boot' and with
#  another already preinstalled OS instance.
#
#  Initial partitions layout example:
#   Number  Start (sector)    End (sector)  Size       Code  Name
#      1            2048          534527   260.0 MiB   EF00  EFI system partition
#      2          534528          796671   128.0 MiB   0C01  Vendor reserved ...
#      3          796672       123676671   58.6 GiB    0700  Basic data partition
#
#  Caution: be ready it may close shell on non zero return code under
#  certain usage circumstances.

PS4="+:\$( basename \"\${0}\" ):\${LINENO}: "
set -xeu

export DEV="$( whiptail \
                    --separate-output \
                    --notags \
                    --radiolist \
                    "Select block device:" \
                    12 25 5 \
                    /dev/sda        "SATA, first "   OFF \
                    /dev/nvme0n1    "NVME, first "   OFF \
                        3>&2 2>&1 1>&3 )"
test -n "${DEV}"

export DM="${DEV##*/}"
export DEVP="${DEV}$( if [[ "$DEV" =~ "nvme" ]]; then echo "p"; fi )"
export DM="${DM}$( if [[ "$DM" =~ "nvme" ]]; then echo "p"; fi )"

export n_prt_efi=1
export n_prt_grub=2
export n_prt_rootfs=5

export phys_lv_name="${DM}${n_prt_rootfs}_crypt"  # XXX - It's also name for DM crypted item.
export dev_for_encrypt="${DEVP}${n_prt_rootfs}"

###
##
#

function print_layouts {
    set -eu

    set +x

    echo
    lsblk

    echo
    sgdisk --print $DEV

    local -a known_var_names=(
                            n_prt_efi
                            n_prt_grub
                            n_prt_rootfs
                            phys_lv_name
                            dev_for_encrypt
                            )
    echo
    for v_name in "${known_var_names[@]}" ; do
        echo "${v_name} = ${!v_name}"
    done
    echo
    set -x
}

function pre_install {
    set -xeu

    if sgdisk --print $DEV | awk '{print $6}' | egrep -i "^EF00$" ; then  # If there is no other OS on the storage. Speculative.
        declare -r is_have_efi="true"
    else
        declare -r is_have_efi="false"
    fi

    if [ "${is_have_efi}" == "false" ] ; then
        sgdisk --new=${n_prt_efi}:0:+1024M $DEV
    fi
    sgdisk --new=${n_prt_grub}:0:+2M $DEV
    #sgdisk --new=${n_prt_rootfs}:0:0 $DEV
    sgdisk --new=${n_prt_rootfs}:0:+1664G $DEV

    if [ "${is_have_efi}" == "false" ] ; then
        sgdisk --typecode=${n_prt_efi}:ef00 $DEV
    fi
    sgdisk \
        --typecode=${n_prt_grub}:ef02 \
        --typecode=${n_prt_rootfs}:8301 \
        $DEV


    if [ "${is_have_efi}" == "false" ] ; then
        sgdisk --change-name=${n_prt_efi}:efi-sp $DEV
    fi
    sgdisk \
        --change-name=${n_prt_grub}:grub-prt \
        --change-name=${n_prt_rootfs}:luks-root \
        $DEV

    #sgdisk --hybrid 1:2:3 $DEV

    partprobe $DEV

    sgdisk --print $DEV

    if [ "${is_have_efi}" == "false" ] ; then
        while [ ! -e "${DEVP}${n_prt_efi}" ] ; do
            echo "INFO:$( basename "${0}" ):${LINENO}: Waiting for partition(s) to be populated by system - '${DEVP}${n_prt_efi}'." >&2
            sleep 1
        done
        mkfs.vfat -F 32 -n EFI-SP ${DEVP}${n_prt_efi}
        #mkfs.vfat -F 16 -n EFI-SP ${DEVP}${n_prt_efi}
    fi

    if true ; then
        wipefs -a $DEVP${n_prt_rootfs}
    
        cryptsetup luksFormat --batch-mode --type=luks1 ${dev_for_encrypt}
        cryptsetup open ${dev_for_encrypt} ${phys_lv_name}
    
        pvcreate /dev/mapper/${phys_lv_name}
        vgcreate osvg /dev/mapper/${phys_lv_name}
        lvcreate -l 100%FREE -n rootlv osvg
    fi
}


function setup_grub_trap_while_install {
    set -eu
    set +x
    local chars="/-\|"
    local idx=0
    echo -n "INFO:$( basename "${0}" ):${LINENO}: Waiting for Grub to appear... " >&2
    while [ ! -d /target/etc/default/grub.d ]; do echo -n "${chars:$(( ${idx}%${#chars} )):1}" ; sleep 0.5 ; idx=$(( idx + 1 )) ; echo -en "\b" ; done; echo "!" ; set -x ; echo "GRUB_ENABLE_CRYPTODISK=y" > /target/etc/default/grub.d/local.cfg
}

function umount_special_fs {
    set -xeu
    if [ -d "/target" ] ; then
        for n in proc sys dev etc/resolv.conf; do
            if mountpoint /target/$n ; then
                mount --make-rslave /target/$n
                umount -R /target/$n
           fi
        done
    fi
}

function disassemble_chroot {
    set -xeu
    if mountpoint /target ; then
        umount_special_fs
        umount /target
    fi
}

function assemble_partitions {
    set -xeu

    if ! dmsetup status ${phys_lv_name} ; then
        cryptsetup open ${dev_for_encrypt} ${phys_lv_name}
    fi
    set +x
    while [ ! -e /dev/mapper/osvg-rootlv ] ; do
        echo "INFO:$( basename "${0}" ):${LINENO}: Waiting for LV to wake up - '/dev/mapper/osvg-rootlv'." >&2
        sleep 1
    done
    set -x
}

function assemble_chroot {
    set -xeu

    assemble_partitions
    
    if [ ! -d "/target" ] ; then
        mkdir /target
    fi
    if ! mountpoint /target ; then
        mount /dev/mapper/osvg-rootlv /target
    fi
    for n in proc sys dev etc/resolv.conf; do
        if [ ! -e /target/$n ] ; then
            if [ -f /$n ] ; then
                mkdir -p "$( dirname /target/$n )"
                touch /target/$n
            else
                mkdir /target/$n
            fi
        fi
        if ! mountpoint /target/$n ; then
            mount --rbind /$n /target/$n
        fi
    done
}

function post_install {
    set -xeu

    assemble_chroot

    chroot /target mount -a
    chroot /target apt install -y cryptsetup-initramfs
    if [ ! -e "/target/etc/luks/boot_os.keyfile" ] ; then
        chroot /target mkdir -p /etc/luks
        chroot /target dd if=/dev/urandom of=/etc/luks/boot_os.keyfile bs=512 count=1
        chroot /target chmod u=rx,go-rwx /etc/luks
        chroot /target chmod u=r,go-rwx /etc/luks/boot_os.keyfile
        chroot /target cryptsetup luksAddKey "${dev_for_encrypt}" /etc/luks/boot_os.keyfile
    fi
    if ! grep "KEYFILE_PATTERN=/etc/luks/*\.keyfile"  /target/etc/cryptsetup-initramfs/conf-hook ; then
        chroot /target bash -c "echo >> /etc/cryptsetup-initramfs/conf-hook"
        chroot /target bash -c "echo KEYFILE_PATTERN=/etc/luks/*.keyfile >> /etc/cryptsetup-initramfs/conf-hook"
        chroot /target bash -c "echo UMASK=0077 >> /etc/initramfs-tools/initramfs.conf"
    fi
    if ! grep "$(blkid -s UUID -o value ${dev_for_encrypt})"  /target/etc/crypttab ; then
        chroot /target bash -c "echo '${phys_lv_name} UUID=$(blkid -s UUID -o value ${dev_for_encrypt}) /etc/luks/boot_os.keyfile luks,discard' >> /etc/crypttab"
    fi

    chroot /target update-initramfs -u -k all
}

###
##  Actual activity start is below.
#

declare -r action="$( whiptail \
    --separate-output \
    --notags \
    --radiolist \
    "Select action:" \
    17 58 10 \
    print_layouts                   "list layout " OFF \
    pre_install                     "new install - 1 - create partitions "          OFF \
    setup_grub_trap_while_install   "new install - 2 - catch Grub and set it up "   OFF \
    post_install                    "new install - 3 - set up FS unlock "           OFF \
    assemble_partitions             "provision - 1  - pick up LUKS and LVM "    OFF \
    assemble_chroot                 "provision - 2a - assemble chroot "         OFF \
    umount_special_fs               "provision - 2b - unmount special FS "      OFF \
    disassemble_chroot              "provision - 3  - disassemble chroot "       OFF \
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
test -b "${DEV}"

"${action}"

set +x
echo "INFO:$( basename "${0}" ):${LINENO}: Job done." >&2
