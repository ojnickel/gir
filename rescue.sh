#!/bin/bash
# Rescue a broken Gentoo from a live USB: mount it, chroot in, fix it.
#
#   ./rescue.sh DEVICE            mount DEVICE as the root and chroot into it
#   ./rescue.sh --borrow SRC TGT  chroot into the already-mounted TGT and
#                                 borrow SRC's /etc/portage, repos, distfiles
#                                 and binpkgs (for when the broken system's
#                                 own Portage config is the problem)
#
# Examples:
#   ./rescue.sh /dev/nvme0n1p3
#   ./rescue.sh /dev/sda3
#   MNT=/mnt/fix ./rescue.sh /dev/sda3
#
# DEVICE is the ROOT partition, not the whole disk. Btrfs roots in a subvolume
# named @ are detected and mounted correctly. Anything else listed in the
# system's own /etc/fstab (/boot/efi, /home, ...) is mounted too, so
# grub-install and emerge work inside the chroot.
#
# Leave with 'exit'; everything is unmounted again on the way out.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
MNT=${MNT:-/mnt/gir}

# Print this file's header comment, stopping at the first line of real code
usage() {
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
    exit 1
}

# Check the argument shape first, so wrong usage is reported even to non-root
[ $# -ge 1 ] || usage
case "$1" in
    --borrow)       [ $# -eq 3 ] || usage ;;
    -h|--help)      usage ;;
    *)              [ $# -eq 1 ] || usage ;;
esac
[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }

# --- Borrow mode: hand straight over to chroot.sh, nothing to mount ---
if [ "$1" = --borrow ]; then
    exec bash "$DIR/lib/chroot.sh" rescue "$2" "$3"
fi

DEV=$1
[ -b "$DEV" ] || { echo "$DEV is not a block device. Aborted."; exit 1; }
if [ "$(lsblk -dno TYPE "$DEV")" = disk ]; then
    echo "$DEV is a whole disk, not a partition. Pick the root partition:"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$DEV"
    exit 1
fi

FSTYPE=$(blkid -s TYPE -o value "$DEV" || true)
[ -n "$FSTYPE" ] || { echo "No filesystem found on $DEV. Aborted."; exit 1; }

MOUNTED=()          # everything we mounted, unmounted in reverse on exit
cleanup() {
    set +e
    local i
    for (( i=${#MOUNTED[@]}-1; i>=0; i-- )); do
        umount -R "${MOUNTED[i]}" 2>/dev/null || umount -Rl "${MOUNTED[i]}"
    done
}
trap cleanup EXIT

# --- Btrfs: find out whether the root lives in a subvolume named @ ---
SUBVOL=""
if [ "$FSTYPE" = btrfs ]; then
    probe=$(mktemp -d)
    if mount -o ro "$DEV" "$probe" 2>/dev/null; then
        [ -d "$probe/@" ] && SUBVOL="@"
        umount "$probe"
    fi
    rmdir "$probe"
fi

# --- Mount the root ---
mkdir -p "$MNT"
if [ -n "$SUBVOL" ]; then
    echo "Mounting $DEV (btrfs, subvol=$SUBVOL) at $MNT"
    mount -o "subvol=$SUBVOL" "$DEV" "$MNT"
else
    echo "Mounting $DEV ($FSTYPE) at $MNT"
    mount "$DEV" "$MNT"
fi
MOUNTED+=("$MNT")

[ -d "$MNT/usr" ] || { echo "WARNING: $MNT does not look like a Linux root."; }

# --- Mount whatever the system's own fstab expects ---
# Sorted by mountpoint, so /boot is mounted before /boot/efi.
if [ -f "$MNT/etc/fstab" ]; then
    echo "Mounting the rest from its own /etc/fstab:"
    while read -r src mp type opts _; do
        case "$src" in ''|\#*) continue ;; esac
        case "$mp"  in ''|/|none|swap) continue ;; esac
        case "$type" in proc|sysfs|devpts|tmpfs|devtmpfs|swap|none) continue ;; esac
        mkdir -p "$MNT$mp"
        if mount -t "$type" -o "${opts:-defaults}" "$src" "$MNT$mp" 2>/dev/null; then
            echo "  $mp"
            MOUNTED+=("$MNT$mp")
        else
            echo "  $mp - FAILED ($src), continuing"
        fi
    done < <(grep -v '^[[:space:]]*#' "$MNT/etc/fstab" | sort -k2,2)
else
    echo "No /etc/fstab in the target - only the root is mounted."
fi

echo
findmnt -R "$MNT" || true
echo
echo "Entering the chroot. Leave it with 'exit'."
echo "Useful in there:  emerge --info | grub-install --efi-directory=/boot/efi"
echo "                  grub-mkconfig -o /boot/grub/grub.cfg | passwd"
echo

# chroot.sh does the /proc /sys /dev /run work and cleans up after itself
bash "$DIR/lib/chroot.sh" chroot "$MNT"

echo "Left the chroot. Unmounting $MNT..."
