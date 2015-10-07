#!/bin/bash
#
# archangel.sh automates the process of installing my flavor of Arch Linux.
# it sets up full-disk encryption. Two partitions are used, one being boot
# and the other root. Both MBR and GPT is supported depending on whether
# legacy BIOS or UEFI is in use.

# author: oral okan
#   date: october, 2015

CONTAINED_ITEM=""

function contains {
  local ITEM=$1
  local LIST=$2
  for I in $LIST
  do
    if [ "$I" == "$ITEM" ]
    then
      CONTAINED_ITEM="$ITEM" 
      break
    fi
  done
}


echo "archangel -- installer script for Arch Linux"
echo
echo "NOTE: Edit /etc/pacman.d/mirrorlist before running this script"
echo
echo "NOTE: Currently, the time zone is set to Europe/Istanbul"
echo "NOTE: Currently, the locale is always en_US.UTF-8"
echo
echo "Two partitions are created:"
echo "  - 512 MB Boot Partition"
echo "  - Rest goes to encrypted root partition"
echo

# Begin by having the user select the target installation disk
echo "Select the installation target disk."
echo "IMPORTANT: All files on the disk will be deleted!"
echo
lsblk -pfln
DEVICE_LIST=$(lsblk -pnr | awk -F' ' '{ print $1 }')
echo

CONTAINED_ITEM=""
while [ -z "$CONTAINED_ITEM" ]
do
  echo -n "Enter your selection (e.g. /dev/sda OR /dev/sdb):  "
  read SELECTED_DEVICE 
  contains "$SELECTED_DEVICE" "$DEVICE_LIST"
  echo "result: $CONTAINED_ITEM"
  if [ -z "$CONTAINED_ITEM" ]
  then
    echo "ERROR: invalid selection!"
    echo
  fi
done
DEVICE="$CONTAINED_ITEM"
BOOT_PART=$DEVICE"1"
ROOT_PART=$DEVICE"2"

# Get the hostname
echo -n "Enter hostname:  "
read HOSTNAME

# Get disk password
DISK_PASSWD=""
while [ -z "$DISK_PASSWD" ]
do
  echo -n "Enter disk encryption password:  "
  read -s DISK_PASSWD
  echo
  echo -n "Again...:  " 
  read -s DISK_PASSWD_VFY
  echo
  if [ "$DISK_PASSWD" != "$DISK_PASSWD_VFY" ]
  then
    DISK_PASSWD="" 
    echo "ERROR: passwords do not match!"
    echo
  fi
done

# Get root password
ROOT_PASSWD=""
while [ -z "$ROOT_PASSWD" ]
do
  echo -n "Enter root password:  "
  read -s ROOT_PASSWD
  echo
  echo -n "Again...:  " 
  read -s ROOT_PASSWD_VFY
  echo
  if [ "$ROOT_PASSWD" != "$ROOT_PASSWD_VFY" ]
  then
    ROOT_PASSWD="" 
    echo "ERROR: passwords do not match!"
    echo
  fi
done

# Figure out if we are in legacy or UEFI mode
if [ -e "/sys/firmware/efi" ]
then 
  UEFI_MODE=1
fi


# GO/NOGO Decision

echo
echo "-------------------"
echo "Go / No-Go Decision"
echo "-------------------"
echo
echo "Target Device:  $DEVICE"
echo "Boot Partition: $BOOT_PART"
echo "Root Partition: $ROOT_PART (Encrypted)"
if [ -n "$UEFI_MODE" ]
then
  echo "Boot Mode:      UEFI"
else
  echo "Boot Mode:      Legacy"
fi

echo "WARNING: everything on $DEVICE will be deleted!!!"
echo
echo -n "Type yes in uppercase if you want to continue..."
read PROCEED

if [ "$PROCEED" != "YES" ]
then
    exit
fi


################################3


# Partitioning the block device
if [ -n "$UEFI_MODE" ]
then
    BOOT_PART_LBL=gpt
    BOOT_PART_TYP=ESP
    BOOT_PART_FMT=fat32
else
    BOOT_PART_LBL=msdos
    BOOT_PART_TYP=primary
    BOOT_PART_FMT=ext4
fi

set -x # echo on

parted -s $DEVICE mklabel $BOOT_PART_LBL
parted -s $DEVICE mkpart $BOOT_PART_TYP $BOOT_PART_FMT 1MiB 513MiB
parted -s $DEVICE set 1 boot on
parted -s $DEVICE mkpart primary ext4 513MiB 100%

set +x
if [ -n "$UEFI_MODE" ]
then
    set -x
    mkfs.fat -F32 $BOOT_PART    # ESP required to be FAT32
else
    set -x
    mkfs.ext4 $BOOT_PART
fi

# Set up the cryptroot

set -v
echo "$DISK_PASSWD" | cryptsetup --force-password luksFormat $ROOT_PART
echo "$DISK_PASSWD" | cryptsetup open $ROOT_PART cryptroot

set -x
mkfs -t ext4 /dev/mapper/cryptroot
mount -t ext4 /dev/mapper/cryptroot /mnt

# Install base system
pacstrap -i /mnt base base-devel
genfstab -p /mnt >> /mnt/etc/fstab
arch-chroot /mnt

# System configuration
echo $HOSTNAME > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime   # TODO: Get user input
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

set -v
echo "$ROOT_PASSWD" | passwd --stdin

set -x
# Allocate swapfile
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
# insert the encrypt hook before the filesystems hook in mkinitcpio.conf
sed '^HOOKS/s/filesystems/encrypt filesystems/g' /etc/mkinitcpio.conf
mkinitcpio -p linux

# Install and configure bootloader

ROOT_PART_UUID=$(blkid | grep $ROOT_PART | awk -F' ' '{print $2}' | cut -d'"' -f2)  # What a mess!!!

set +x
if [ -n "$UEFI_MODE" ]
then
    set -x
    bootctl install

    echo "title   Arch Linux" > /boot/loader/entries/arch.conf
    echo "linux   /vmlinuz-linux" >> /boot/loader/entries/arch.conf
    echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf
    echo "options cryptdevice=UUID=$ROOT_PART_UUID:cryptroot root=/dev/mapper/cryptroot quiet rw" >> /boot/loader/entries/arch.conf

    echo "default arch" > /boot/loader/loader.conf
else
    set -x
    pacman -S grub
    sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_ENABLE_CRYPTODISK=y\nGRUB_CMDLINE_LINUX=\"cryptdevice=/dev/disk/by-uuid/$ROOT_PART_UUID:cryptroot\"/g"
    echo "GRUB_CMDLINE_LINUX=\"cryptdevice=/dev/disk/by-uuid/$ROOT_PART_UUID:cryptroot\"" >> /etc/default/grub
    grub-install --recheck $DEVICE
    grub-mkconfig -o /boot/grub/grub.cfg
fi

# TODO: systemctl enable dhcpcd@eno1.service
