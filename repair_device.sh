#!/bin/bash
set -eu

# --- Select Drive Function ---
select_target_disk() {
  echo "Scanning for available disks..."
  mapfile -t disks < <(lsblk -dno NAME,SIZE,TYPE | grep "disk" | sort)
  if [ ${#disks[@]} -eq 0 ]; then
    echo "No disks found! Exiting."
    exit 1
  fi
  echo "Available disks:"
  for i in "${!disks[@]}"; do
    line="${disks[$i]}"
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    echo "$((i+1)). /dev/$name  ($size)"
  done
  while true; do
    read -rp "Enter the number of the disk you want to use: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >=1 && choice <= ${#disks[@]} )); then
      selected="${disks[$((choice-1))]}"
      name=$(echo "$selected" | awk '{print $1}')
      size=$(echo "$selected" | awk '{$1=""; print $0}' | sed 's/^ //')
      echo "You selected: /dev/$name ($size)"
      read -rp "Are you sure you want to install SteamOS on this drive? Type YES to confirm: " confirm
      if [[ "$confirm" == "YES" ]]; then
        DISK="/dev/$name"
        # Determine suffix for nvme
        if [[ "$DISK" =~ "nvme" ]]; then
          DISK_SUFFIX="p"
        else
          DISK_SUFFIX=""
        fi
        echo "Confirmed. Proceeding with disk: $DISK"
        break
      else
        echo "Selection canceled. Please choose again."
      fi
    else
      echo "Invalid input. Try again."
    fi
  done
}

# Run disk selection
select_target_disk
echo "Using disk: $DISK"

# Set partition labels
readvar PARTITION_TABLE <<END
  label: gpt
  ${DISK}${DISK_SUFFIX}1: name="esp", size=64MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
  ${DISK}${DISK_SUFFIX}2: name="efi-A", size=32MiB, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
  ${DISK}${DISK_SUFFIX}3: name="efi-B", size=32MiB, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
  ${DISK}${DISK_SUFFIX}4: name="rootfs-A", size=5120MiB, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
  ${DISK}${DISK_SUFFIX}5: name="rootfs-B", size=5120MiB, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
  ${DISK}${DISK_SUFFIX}6: name="var-A", size=256MiB, type=4D21B016-B534-45C2-A9FB-5C16E091FD2D
  ${DISK}${DISK_SUFFIX}7: name="var-B", size=256MiB, type=4D21B016-B534-45C2-A9FB-5C16E091FD2D
  ${DISK}${DISK_SUFFIX}8: name="home", type=933AC7E1-2EB4-4F13-B844-0E14E2AEF915
END

# Partition IDs
FS_ESP=1
FS_EFI_A=2
FS_EFI_B=3
FS_ROOT_A=4
FS_ROOT_B=5
FS_VAR_A=6
FS_VAR_B=7
FS_HOME=8

# Utility functions
err() { echo >&2 "$@"; sleep infinity; exit 1; }
trap 'err "Unexpected error."' ERR

sh_c() { [[ $(tput colors 2>/dev/null || echo 0) -le 0 ]] && return; echo -e "\e[$((${1}==0?0:$1))m"; }

sh_quote() { printf '%q' "$@"; }
showcmd() { echo "+ $*"; "$@"; }

fmt_ext4() { sudo mkfs.ext4 -F -L "$1" "$2"; }
fmt_fat32() { sudo mkfs.vfat -n "$1" "$2"; }

# Prompt functions
prompt_step() {
  echo "$@"
  if [[ -n ${NOPROMPT:-} ]]; then
    return
  fi
  read -rp "$1" confirm_choice
  [[ "$confirm_choice" == "YES" ]] || exit 1
}
prompt_reboot() {
  prompt_step "$1" "Reboot now? (Press ENTER to continue, CTRL+C to abort)"
  systemctl reboot
}

# Verify partition
verifypart() {
  local dev=$1; local type=$2; local label=$3
  local real_type=$(blkid -o value -s TYPE "$dev" || echo "")
  local real_label=$(blkid -o value -s PARTLABEL "$dev" || echo "")
  [[ "$real_type" == "$type" ]] && [[ "$real_label" == "$label" ]] || err "Partition $dev mismatch."
}

# Image root
imageroot() {
  local src=$1; local dst=$2
  dd if="$src" of="$dst" bs=128M status=progress oflag=sync
  sudo btrfstune -f -u "$dst"
}

# Finalize partition (stub)
finalize_part() {
  echo "Finalizing partition $1..."
  # Placeholder for actual finalize commands
}

# --- Main sequence ---
main() {
  # Check disk exists
  [[ -e "$DISK" ]] || err "Disk $DISK not found."

  # Write partition table
  prompt_step "Reinstall or Repair" "This will erase and install SteamOS on $DISK. Are you sure?"
  echo "$PARTITION_TABLE" | sfdisk "$DISK"

  # Create filesystems
  fmt_fat32 "esp" "$(diskpart "$FS_ESP")"
  fmt_fat32 "efi-A" "$(diskpart "$FS_EFI_A")"
  fmt_fat32 "efi-B" "$(diskpart "$FS_EFI_B")"
  fmt_ext4 "rootfs-A" "$(diskpart "$FS_ROOT_A")"
  fmt_ext4 "rootfs-B" "$(diskpart "$FS_ROOT_B")"
  fmt_ext4 "var-A" "$(diskpart "$FS_VAR_A")"
  fmt_ext4 "var-B" "$(diskpart "$FS_VAR_B")"
  fmt_ext4 "home" "$(diskpart "$FS_HOME")"

  # Image system partitions
  local root_dev=$(findmnt -n -o source /)
  imageroot "$root_dev" "$(diskpart "$FS_ROOT_A")"
  imageroot "$root_dev" "$(diskpart "$FS_ROOT_B")"

  # Run latest SteamOS update
  echo "Checking for latest SteamOS updates..."
  output=$(steamos-update --no-reboot)
  echo "$output"
  if echo "$output" | grep -q "already the latest"; then
    echo "System already up-to-date."
  else
    echo "System updated to latest SteamOS."
  fi

  # Finalize boot
  finalize_part "A"
  finalize_part "B"
  echo "Installation complete. Rebooting..."
  reboot
}

# Run main
main
}

# Run the script
main "$@"