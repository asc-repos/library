# [Full_Disk_Encryption_Howto_2019 - Community Help Wiki](https://help.ubuntu.com/community/Full_Disk_Encryption_Howto_2019)

Further support may be available from Freenode IRC channel #ubuntu.

This page is an up-to-date guide to comprehensive LUKS encryption, including GRUB, covering 18.04 LTS and
later releases.

It is focused on modifying the Ubuntu Desktop installer process in the minimum possible way to allow it to install
with an encrypted `/boot/` and root file-system. It requires 36 commands be performed in a terminal, all of which
are shown in this guide and most can be copy and pasted.
It is also a useful overview on the manual steps required for storage-at-rest encryption.

It is intended to replace the current (hopelessly out-of-date and inadequate) [FullDiskEncryptionHowto](https://help.ubuntu.com/community/FullDiskEncryptionHowto) page.

## Almost Full Disk Encryption (FDE)

I'm (Tj) being deliberately pedantic in calling this almost Full Disk Encryption since the entire disk is never
encrypted. What is encrypted are the operating system partition and the boot-loader second-stage file-system which
includes the Linux kernel and initial RAM disk.

However, this is much better than the Ubuntu installer Encrypt Disk option which only supports encrypting the operating system partition but leaves the
boot-loader second stage file-system unencrypted and therefore vulnerable to tampering of the GRUB configuration, Linux kernel or more likely, the initial RAM file-system (`initrd.img`).

In both cases the first-stage GRUB boot-loader files are not (and cannot) be encrypted or protected through cryptographic signatures in BIOS boot mode.

It is possible, in UEFI Secure Boot mode, to have every stage cryptographically signed, in which case any tampering can be detected and boot aborted. Unfortunately, Canonical (who control the building of the packaged signed GRUB UEFI boot-loader) did not include the encryption modules in their signed GRUB EFI images until the release of 19.04 Disco. See bug [#1565950](https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/1565950).

Illustrations (screen-captures) are taken from the Ubuntu 19.04 'Disco' Desktop Installer. Other flavours have their own installers and themes and may not
look identical.

## Prerequisites

- Desktop installer ISO image from [http://releases.ubuntu.com/](http://releases.ubuntu.com/) copied to installation media (usually a USB Flash device but may be a DVD or the ISO file attached to a virtual machine
hypervisor).

- Empty installation media (no existing operating systems or data, or entire device can be over-written)

## Boot the Installer

Even before starting the installer it is critical to select the correct boot mode. Ubuntu (and flavours like Kubuntu, Lubuntu, Xubuntu, etc.) uses hybrid bootable images that have two alternate
boot-loaders:

1. GRUB (GRand Unified Bootloader)
2. Syslinux

The ISO images can boot in several possible combinations of mode and partitioning:

1. ISO-9660 El-Torito (the CD/DVD optical media boot mechanism - uses Syslinux)
2. GPT + EFI-SP (GUID Partition Table and EFI System Partition - uses GRUB)
3. MBR + EFI-SP (Master Boot Record and EFI System Partition - uses GRUB)
4. GPT + PC (GUID Partition Table and BIOS boot - uses Syslinux)
5. MBR + PC (Master Boot Record and BIOS boot - uses Syslinux)

## Boot Modes

PCs have two boot modes: BIOS (Basic Input Output System) and UEFI (Unified Extensible Firmware Interface). BIOS was installed in IBM PCs and compatibles from the 1980s. UEFI mode has become prevalent since Microsoft introduced it in Windows 7 and later began requiring it on new PCs to meet the Windows Logo License Agreement requirements. Most PCs since
2010 have UEFI.

Apple Macintosh/iMac devices have their own EFI (Extensible Firmware Interface) which is almost, but not quite, the same as UEFI but do not have a BIOS equivalent. This guide doesn't (currently) address installation on Apple devices.

BIOS is also known as Legacy or CSM (Compatibility Support Module) when part of UEFI.

If the target system is BIOS-only you can disregard the rest of this section.

#### Selecting UEFI boot mode

In order to support UEFI Secure Boot, or to install alongside another operating system that uses UEFI boot mode (e.g. Windows 10), the system motherboard's firmware boot-manager has to be told to start the Ubuntu installer in UEFI mode.

Unfortunately there is no consistency between different PC manufacturers on how motherboard firmware boot-managers should indicate boot-mode so we, as users, have to figure it out from what clues we can see when the PC's boot menu is displayed and lists boot devices.

Let's assume we're using a USB Flash device. The boot menu may list that device twice (once for UEFI mode, and again for BIOS/CSM/Legacy mode). It may make it explicit that one is "UEFI" and the other not, or it may use some hard-to-spot code such as a single letter abbreviation (e.g. "U" vs "B").

If we want to guarantee UEFI mode and avoid BIOS/CSM/Legacy mode then by entering firmware Setup at power-on we should be able to find an option to disable CSM/Legacy mode.

After doing that we can be sure the installer will boot in UEFI mode.

There is a quick way to confirm the installer has started in UEFI mode - it will be using GRUB, so see the following section First Boot Screen > GRUB (UEFI mode) for what it will look
like.

#### Detecting UEFI boot mode

Once Linux has started it is possible to check. The presence of the `efivarfs` file-system means the system booted in UEFI mode:

```
$ mount | grep efivars
efivarfs on /sys/firmware/efi/efivars type efivarfs (rw,nosuid,nodev,noexec,relatime)
```

## First Boot Screen

The options displayed will look different depending on which boot-loader is used.

#### GRUB (UEFI mode)

Choose `Try Ubuntu without installing` from the GRUB boot-loader menu:

#### Syslinux (BIOS mode)

The display will briefly pause for selection of the input language:

If you interrupt at this stage to choose a language Syslinux will display a menu where you can make various advanced changes to the boot options. At this point you should choose the `Try Ubuntu without installing` menu option.

#### Welcome Options

If the boot hasn't been interrupted to choose a language the Welcome dialog with start-up options will be displayed. Choose Try Ubuntu.

#### Live Desktop

Once the Live Desktop environment has started we need to use a Terminal shell command-line to issue a series of commands to pre-prepare the target device before executing the Installer
itself.

On Ubuntu (Gnome) press the Show Applications button at lower-left corner

In the subsequent text search field type "Term" until just the Terminal icon is shown

Press the icon to launch Terminal.

Instead of these steps you can just press `Ctrl+Alt+T` hot-key combination.

## Pre-Prepare Encrypted Partitions

You might find maximising the Terminal window is helpful for working with the command-line.

As much as is possible these manual steps will keep to the same installation layout and naming as the installer uses.
For these commands you'll need elevated privileges so switch to root user (the `$` prefix indicates a regular user and `#` indicates root user):

```
$ sudo -i
```

Identify Installation Target Device

```
# lsblk
NAME  MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
loop0   7:0    0  1.9G  1 loop /rofs
loop1   7:1    0 89.3M  1 loop /snap/core/6673
loop2   7:2    0 53.7M  1 loop /snap/core18/941
loop3   7:3    0  151M  1 loop /snap/gnome-3-28-1804/31
loop4   7:4    0    4M  1 loop /snap/gnome-calculator/406
loop5   7:5    0 14.8M  1 loop /snap/gnome-characters/254
loop6   7:6    0 1008K  1 loop /snap/gnome-logs/61
loop7   7:7    0  3.7M  1 loop /snap/gnome-system-monitor/77
loop8   7:8    0 35.3M  1 loop /snap/gtk-common-themes/1198
sda     8:0    0    9G  0 disk 
sr0    11:0    1    2G  0 rom  /cdrom
```

Here the installation target device is sda but yours may vary so examine the SIZE to ensure you choose the correct target. (in this example target is a 9GiB virtual machine disk image file).

We'll set an environment variable we can re-use in all future commands. Doing this will allow you to copy and paste these instructions directly into your terminal (note: do not copy and paste
the "#" prefix). In this example I'm installing to `/dev/sda`:

```
# export DEV="/dev/sda"
```

On systems with NVME storage devices the naming scheme is `/dev/nvme${CONTROLLER}n${NAMESPACE}p${PARTITION}` so if there is only one device it is likely it would
require:

```
# export DEV="/dev/nvme0n1"
```

Finally we'll set an environment variable for the encrypted device-mapper naming that omits the leading path "/dev/" part:

```
# export DM="${DEV##*/}"
```

And we have to cope with NVME devices needing a 'p' for partition suffix:

```
# export DEVP="${DEV}$( if [[ "$DEV" =~ "nvme" ]]; then echo "p"; fi )"
# export DM="${DM}$( if [[ "$DM" =~ "nvme" ]]; then echo "p"; fi )"
```

#### Partitioning

We'll now create a disk label and add four partitions. We'll be creating a GPT (GUID Partition Table) so it is compatible with both UEFI and BIOS mode installations. We'll also create
partitions for both modes in addition to the partitions for the encrypted `/boot/` and `/` (root) file-systems.

We'll be using the sgdisk tool. To understand its options please read [man 8 sgdisk](http://manpages.ubuntu.com/manpages/bionic/man8/sgdisk.8.html)

First check for any existing partitions on the device and if some are found consider if you wish to keep them or not. If you wish to keep them **DO NOT USE** `sgdisk --zap-all` command
detailed next. Instead, consider if you need to free up disk space by shrinking or deleting individual existing partitions.

```
# sgdisk --print $DEV
Creating new GPT entries.
Disk /dev/sda: 18874368 sectors, 9.0 GiB
Model: QEMU HARDDISK   
Sector size (logical/physical): 512/512 bytes
Disk identifier (GUID): 41BCC4F5-B604-4C39-863F-C73B90B38397
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 34, last usable sector is 18874334
Partitions will be aligned on 2048-sector boundaries
Total free space is 18874301 sectors (9.0 GiB)

Number  Start (sector)    End (sector)  Size       Code  Name
```

If you do need to manipulate the existing partitions use the Show Applications menu to search for GPartEd which is the graphical user interface partitioning tool (see the [GPartEd manual](https://gparted.org/display-doc.php?name=help-manual) for how to use it)

If it is safe to delete everything on this device you should wipe out the existing partitioning metadata - DO NOT DO THIS if you are installing alongside existing partitions!

```
# sgdisk --zap-all $DEV
GPT data structures destroyed! You may now partition the disk using fdisk or other utilities.
```

Now we'll create the partitions. A small `bios_boot` (2MB) partition for BIOS-mode GRUB's core image, an 128MB EFI System Partition, a 768MB `/boot/` and a final partition for the remaining space for the operating system.

Syntax: `--new=<partition_number>:<start>:<end>` where start and end can be relative values and when zero (`0`) adopt the lowest or highest possible value respectively.

Partition `4` is not created. The reason is the Ubuntu Installer would only create partitions `1` and `5`. Here we create those and in addition the two boot-loader alternatives.
```
# sgdisk --new=1:0:+768M $DEV
# sgdisk --new=2:0:+2M $DEV
# sgdisk --new=3:0:+128M $DEV
# sgdisk --new=5:0:0 $DEV
# sgdisk --typecode=1:8301 --typecode=2:ef02 --typecode=3:ef00 --typecode=5:8301 $DEV
# sgdisk --change-name=1:/boot --change-name=2:GRUB --change-name=3:EFI-SP --change-name=5:rootfs $DEV
# sgdisk --hybrid 1:2:3 $DEV

# sgdisk --print $DEV
Disk /dev/sda: 18874368 sectors, 9.0 GiB
Model: QEMU HARDDISK   
Sector size (logical/physical): 512/512 bytes
Disk identifier (GUID): 41BCC4F5-B604-4C39-863F-C73B90B38397
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 34, last usable sector is 18874334
Partitions will be aligned on 2048-sector boundaries
Total free space is 2014 sectors (1007.0 KiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048         1574911   768.0 MiB   8301  /boot
   2         1574912         1579007   2.0 MiB     EF02  GRUB
   3         1579008         1841151   128.0 MiB   EF00  EFI-SP
   5         1841152        18874334   8.1 GiB     8301  rootfs
```

#### LUKS Encrypt
The default LUKS (Linux Unified Key Setup) format (version) used by the cryptsetup tool has changed since the release of 18.04 Bionic. 18.04 used version 1 ("luks1") but more recent
Ubuntu releases default to version 2 ("luks2"). GRUB only supports opening version 1 so we have to explicitly set luks1 in the commands we use or else GRUB will not be able to install to, or unlock, the encrypted device.

In summary, the LUKS container for `/boot/` must currently use LUKS version 1 whereas the container for the operating system's root file-system can use the default LUKS version 2.

For more information see the man-pages for 18.04 Bionic or 18.10 Cosmic onwards.

First the `/boot/` partition:

```
# cryptsetup luksFormat --type=luks1 ${DEVP}1

WARNING!
========
This will overwrite data on /dev/sda1 irrevocably.

Are you sure? (Type uppercase yes): YES
Enter passphrase for /dev/sda1: 
Verify passphrase: 
```

Now the operating system partition:

```
# cryptsetup luksFormat ${DEVP}5

WARNING!
========
This will overwrite data on /dev/sda5 irrevocably.

Are you sure? (Type uppercase yes): YES
Enter passphrase for /dev/sda5: 
Verify passphrase:
```

#### LUKS unlock

Now open the encrypted devices:

```
# cryptsetup open ${DEVP}1 LUKS_BOOT
Enter passphrase for /dev/sda1: 

# cryptsetup open ${DEVP}5 ${DM}5_crypt
Enter passphrase for /dev/sda5: 

# ls /dev/mapper/
control  LUKS_BOOT sda5_crypt
```

After the Ubuntu installation is finished we will be adding key-files to both of these devices so that you'll only have to type the pass-phrase once for GRUB and thereafter the operating
system will use embedded key-files to unlock without user intervention.

#### Format File-systems

IMPORTANT this step must be done otherwise the Installer's partitioner will disable the ability to write a file-system to this device without it having a partition table (Man-page for
mkfs.ext4):

```
# mkfs.ext4 -L boot /dev/mapper/LUKS_BOOT
mke2fs 1.44.6 (5-Mar-2019)
Creating filesystem with 196096 4k blocks and 49056 inodes
Filesystem UUID: 659410fb-29a7-40af-9a5f-4dc31b72ad0a
Superblock backups stored on blocks: 
        32768, 98304, 163840

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (4096 blocks): done
Writing superblocks and filesystem accounting information: done
```


Format the EFI-SP as FAT16 (Man-page for mkfs.vfat):

```
# mkfs.vfat -F 16 -n EFI-SP ${DEVP}3
mkfs.fat 4.1 (2017-01-24)
```

#### LVM (Logical Volume Management)

We'll now create the operating system LVM Volume Group (VG) and a Logical Volume (LV) for the root file-system.

LVM has a wonderful facility of being able to increase the size of an LV whilst it is active. To provide for this we will only allocate 80% of the free space in the VG to the LV initially. Later,
if you need space for other file-systems, or snapshots, the installed system will be ready and able to support those requirements without struggling to free up space.

I am also creating a 4GiB LV device for swap which, as well as being used to provide additional memory pages when free RAM space is low, is used to store a hibernation image of memory
so the system can be completely powered off and can resume all applications where they left off. The size of the swap space to support hibernation should be equal to the amount of RAM the
PC has now or is is expected to have in the future.

Man-pages for pvcreate vgcreate lvcreate.

```
# pvcreate /dev/mapper/${DM}5_crypt
Physical volume "/dev/mapper/sda5_crypt" successfully created.
# vgcreate ubuntu-vg /dev/mapper/${DM}5_crypt
Volume group "ubuntu-vg" successfully created
# lvcreate -L 4G -n swap_1 ubuntu-vg
Logical volume "swap_1" created.
# lvcreate -l 80%FREE -n root ubuntu-vg
Logical volume "root" created.
```

## Install Ubuntu

Now minimise the Terminal window and start the Installer:

Choose the installation language and keyboard and then the software installation choices:

In the Installation Type options choose Something Else:

#### Manual Partitioning

The manual partitioner will start:

Select the root file-system device for formatting (`/dev/mapper/ubuntu--vg-root`), press the Change button, choose Use As Ext4... and Mount point /:

Select the swap device (`/dev/mapper/ubuntu--vg-swap_1`), press the Change button, choose Use as swap area:

Select the Boot file-system device for formatting (`/dev/mapper/LUKS_BOOT`), press the Change button. choose Use as Ext4... and Mount point `/boot`:

Select the boot-loader device (`/dev/sda` in my example). Boot-loader device should always be a raw disk not a partition or device-mapper node:

Press the Install Now button to write the changes to the disk and press the Continue button:

The installation process will continue in the background whilst you fill in the Where Are You? and Who Are You? forms:

#### Enable Encrypted GRUB

As soon as you have completed those forms switch to the Terminal to configure GRUB. These commands wait until the installer has created the GRUB directories and then adds a drop-in
file telling GRUB to use an encrypted file-system. The command will not return to the shell prompt until the target directory has been created by the installer. In most cases that will have been
done before this command is executed so it should instantly return:

```
# while [ ! -d /target/etc/default/grub.d ]; do sleep 1; done; echo "GRUB_ENABLE_CRYPTODISK=y" > /target/etc/default/grub.d/local.cfg
```

**This has to be done before the installer reaches the Install Bootloader stage at the end of the installation process.**

If installation is successful choose the Continue Testing option:

## Post-Installation Steps

Return to the Terminal and create a change-root environment to work in the newly installed OS (Man-pages for mount chroot):

```
# mount /dev/mapper/ubuntu--vg-root /target
# for n in proc sys dev etc/resolv.conf; do mount --rbind /$n /target/$n; done 
# chroot /target

# mount -a
```

Within the chroot install and configure the cryptsetup-initramfs package. This may already be installed. Note: this package is not available in 18.04 Bionic because the files are included in
the main cryptsetup package.

```
# apt install -y cryptsetup-initramfs
```

This allows the encrypted volumes to be automatically unlocked at boot-time. The key-file and supporting scripts are added to the `/boot/initrd.img-$VERSION` files.

This is safe because these files are themselves stored in the encrypted `/boot/` which is unlocked by the GRUB boot-loader (which asks you to type the pass-phrase) which then loads the
kernel and `initrd.img` into RAM before handing execution over to the kernel. (Man-page for `initramfs.conf`):

```
# echo "KEYFILE_PATTERN=/etc/luks/*.keyfile" >> /etc/cryptsetup-initramfs/conf-hook
# echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf
```

Create a randomised key-file of 4096 bits (512 bytes), secure it, and add it to the LUKS volumes (Man-pages for dd chmod):

```
# mkdir /etc/luks
# dd if=/dev/urandom of=/etc/luks/boot_os.keyfile bs=512 count=1
1+0 records in u=rx,go-rwx /etc/luks
1+0 records out
512 bytes (0.5 kB, 0.5 KiB) copied, 0.0002368 s, 17.3 MB/s

# chmod u=rx,go-rwx /etc/luks
# chmod u=r,go-rwx /etc/luks/boot_os.keyfile

# cryptsetup luksAddKey ${DEVP}1 /etc/luks/boot_os.keyfile 
Enter any existing passphrase: 

# cryptsetup luksAddKey ${DEVP}5 /etc/luks/boot_os.keyfile 
WARNING: Locking directory /run/cryptsetup is missing!
Enter any existing passphrase:
```

Add the keys to the crypttab (Man-pages for crypttab blkid):

```
# echo "LUKS_BOOT UUID=$(blkid -s UUID -o value ${DEVP}1) /etc/luks/boot_os.keyfile luks,discard" >> /etc/crypttab
# echo "${DM}5_crypt UUID=$(blkid -s UUID -o value ${DEVP}5) /etc/luks/boot_os.keyfile luks,discard" >> /etc/crypttab
```

Finally update the initialramfs files to add the cryptsetup unlocking scripts and the key-file:

```
# update-initramfs -u -k all
```

If everything has gone well the system is now ready to reboot.

## ReBoot

Reboot the system, not forgetting to remove the installation media (otherwise it'll boot again!).

You should get a GRUB pass-phrase prompt:

## P.S.

`F9` key may serve for hardware Boot menu. Press and hold `Shift` key during a boot in order to see Grub menu.

#### Things to be prepared for vanilla installer

|device with file system        |mount point|
|-------------------------------|-----------|
|`/dev/mapper/ubuntu--vg-root`  |`/`        |
|`/dev/mapper/ubuntu--vg-swap_1`|`swap area`|
|`/dev/mapper/LUKS_BOOT`        |`/boot`    |



## About

Changes:
- Pictures ommited, available via links to materials sources.
- Browser bugs during conversion into Markdown text.
- Minor insertions concerning keyboard hot-keys and pivot points.

The material on this [wiki](https://help.ubuntu.com/community/) is available under a free license, see [Copyright / License](https://help.ubuntu.com/community/License) for details.

You can contribute to this [wiki](https://help.ubuntu.com/community/), see [Wiki Guide](https://help.ubuntu.com/community/WikiGuide) for details.

(last edit as of 2020-11-07 14:19:16 by [tj](https://launchpad.net/~tj) @ 51-155-44-233.ll.in-addr.zen.co.uk[51.155.44.233]:tj)
