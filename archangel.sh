#!/bin/bash
#
# archangel.sh automates the process of installing my flavor of Arch Linux.
# it sets up full-disk encryption. Two partitions are used, one being boot
# and the other root. Both MBR and GPT is supported depending on whether
# legacy BIOS or UEFI is in use.

# author: oral okan
#   date: october, 2015

COUNTRY="Turkey"
TIMEZONE="Europe/Istanbul"
LOCALE="en_US.UTF-8"

cat << EOM

archangel -- installer script for Arch Linux

Installs a fresh install of Arch Linux onto an entire hard drive.
The disk is separated into two partitions:

  1: The boot partition (512 MB)
  2: Encrypted root partition (Rest of the available space)

NOTE:
In the current version, the following defaults are set automatically:
    Installation Mirror: ftp.linux.org.tr
    Time zone: Europe/Istanbul
    Locale: en_US.UTF-8

EOM

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

function list_hdd {
local LST=$(lsblk -pfln | grep '/dev/sd. ')
cat << EOM
Here is the list of available hard disk drives:
EOM
for ITEM in $LST
do
  printf "    $ITEM\n"
done
echo
}

function select_hdd {
cat << EOM
Pick the hard disk drive that Arch Linux will installed on.
This should be of the form /dev/sdX (e.g. /dev/sda)
WARNING: All the files on the selected device will be deleted!

EOM

list_hdd  # List the available devices

local DEVICE_LIST=$(lsblk -pnr | awk -F' ' '{ print $1 }')
local CONTAINED_ITEM=""
while [ -z "$CONTAINED_ITEM" ]
do
  echo -n "Enter your selection:  "
  read SELECTED_DEVICE 
  contains "$SELECTED_DEVICE" "$DEVICE_LIST"
  if [ -z "$CONTAINED_ITEM" ]
  then
    echo "ERROR: invalid selection!"
    echo
  fi
done
DEVICE="$CONTAINED_ITEM"
BOOT_PART=$DEVICE"1"
ROOT_PART=$DEVICE"2"
}

function get_hostname {
  HOSTNAME=""
  while [ -z "$HOSTNAME" ]
  do
    echo -n "Enter hostname:  "
    read HOSTNAME
    if [ -z "$HOSTNAME" ]
    then
      echo "Hostname cannot be empty"
    fi
  done
}

function get_disk_pass {
  DISK_PASSWD=""
  while [ -z "$DISK_PASSWD" ]
  do
    echo -n "Enter disk encryption password:  "
    read -s DISK_PASSWD
    echo
    if [ -z "$DISK_PASSWD" ]
    then
      echo "Disk password cannot be empty" 
      continue
    fi
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
}

function get_root_pass {
  ROOT_PASSWD=""
  while [ -z "$ROOT_PASSWD" ]
  do
    echo -n "Enter root password:  "
    read -s ROOT_PASSWD
    echo
    if [ -z "$ROOT_PASSWD" ]
    then
      echo "Root password cannot be empty" 
      continue
    fi
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
}

function get_boot_mode {
  if [ -e "/sys/firmware/efi" ]
  then 
    BOOT_MODE="UEFI"  
    BOOT_PART_LBL="gpt"
    BOOT_PART_TYP="ESP"
    BOOT_PART_FMT="fat32"
    BOOT_PART_SIZE=512
  else
    BOOT_MODE="LEGACY"
    BOOT_PART_LBL="msdos"
    BOOT_PART_TYP="primary"
    BOOT_PART_FMT="ext4"
    BOOT_PART_SIZE=256
  fi
}

function get_country {
  MIRROR_URL=""
  while [ -z "$MIRROR_URL" ]
  do
    local COUNTRY=""
    echo -n "Enter name of country of download mirror selection:  "
    read COUNTRY
    MIRROR_URL=$(grep -A1 $COUNTRY /etc/pacman.d/mirrorlist | tail -n1)
    if [ -z "$MIRROR_URL" ]
    then
     echo "Mirror for country not found."
     echo "Check /etc/pacman.d/mirrorlist"
   fi
  done
}

function get_configuration {
  select_hdd 
  get_hostname
  get_country
  get_disk_pass
  get_root_pass
  get_boot_mode
}

function get_confirmation {
cat << EOM

Selected configuration:

Target Disk:    $DEVICE
Boot Mode:      $BOOT_MODE
Boot Partition: $BOOT_PART  $BOOT_PART_SIZE MB  $BOOT_PART_TYP  $BOOT_PART_FMT 
Root Partition: $ROOT_PART  LUKS (encrypted)
LUKS Partition: /dev/mapper/cryptroot  primary  ext4
Hostname:       $HOSTNAME
Mirror URL:     $(echo $MIRROR_URL | awk -F" " '{ print $3 }')
Timezone:       $TIMEZONE
Locale:         $LOCALE

WARNING: everything on $DEVICE will be deleted!!!

EOM

local CONFIRM=""

echo -n "Type yes in uppercase if you want to continue...  "
read CONFIRM

if [ "$CONFIRM" != "YES" ]
then
  echo "Goodbye"
  exit
fi

}

get_configuration
get_confirmation

echo "GO"

exit

################################3

# Configure mirrorlist
#MIRROR_LINE=$(grep -n bootctl archangel.sh | awk -F':' '{ print $1 }')
COUNTRY="Turkey"
MIRROR_URL=$(grep -A1 $COUNTRY /etc/pacman.d/mirrorlist | tail -n1)
sed -i "1i $MIRROR_URL" /etc/pacman.d/mirrorlist

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
    mkfs.ext4 -F $BOOT_PART
fi

# Set up the cryptroot

set -v
echo "$DISK_PASSWD" | cryptsetup --force-password luksFormat $ROOT_PART
echo "$DISK_PASSWD" | cryptsetup open $ROOT_PART cryptroot

set -x
mkfs -t ext4 -F /dev/mapper/cryptroot
mount -t ext4 /dev/mapper/cryptroot /mnt
mkdir /mnt/boot
mount $BOOT_PART /mnt/boot

# Install base system
pacstrap -i /mnt base base-devel
genfstab -p /mnt >> /mnt/etc/fstab

set +x
ROOT_PART_UUID=$(blkid | grep $ROOT_PART | awk -F' ' '{print $2}' | cut -d'"' -f2)  # What a mess!!!

cat > /mnt/archangel.sh <<- EOM
# System configuration
echo $HOSTNAME > /etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime   # TODO: Get user input
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

set -v
passwd

set -x
# Allocate swapfile
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
# insert the encrypt hook before the filesystems hook in mkinitcpio.conf
sed -i '/^HOOKS/s/filesystems/encrypt filesystems/g' /etc/mkinitcpio.conf
mkinitcpio -p linux

# Install and configure bootloader

set +x
EOM

if [ -n "$UEFI_MODE" ]
then
cat >> /mnt/archangel.sh <<- EOM
set -x
bootctl install

echo "title   Arch Linux" > /boot/loader/entries/arch.conf
echo "linux   /vmlinuz-linux" >> /boot/loader/entries/arch.conf
echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf
echo "options cryptdevice=UUID=$ROOT_PART_UUID:cryptroot root=/dev/mapper/cryptroot quiet rw" >> /boot/loader/entries/arch.conf

echo "default arch" > /boot/loader/loader.conf
EOM
else
cat >> /mnt/archangel.sh <<- EOM
set -x
pacman -S --noconfirm grub
sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_ENABLE_CRYPTODISK=y\nGRUB_CMDLINE_LINUX=\"cryptdevice=\/dev\/disk\/by-uuid\/$ROOT_PART_UUID:cryptroot\"/g" /etc/default/grub
grub-install --recheck $DEVICE
grub-mkconfig -o /boot/grub/grub.cfg
EOM
fi

# TODO: systemctl enable dhcpcd@eno1.service
chmod u+x /mnt/archangel.sh

echo "Will now chroot into the new system."
echo "Run /archangel.sh" after this happens.
echo "Press any key to continue."
read -n1 nothing

arch-chroot /mnt
