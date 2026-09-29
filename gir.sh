#!/bin/bash
# GIR - Gentoo Install & Rescue
#
# Single entry point. Every subcommand is a script in lib/ and can still be
# run directly if you prefer.
#
#   ./gir.sh                      menu (easiest - start here)
#   ./gir.sh install DISK [VAR]   full run: partition -> stage3 -> chroot
#   ./gir.sh disk DISK            partition and format only
#   ./gir.sh stage3 [VARIANT]     download, verify and unpack a stage3
#   ./gir.sh chroot TARGET        chroot into an already-mounted root
#   ./gir.sh rescue DEVICE        mount a broken system and chroot in
#   ./gir.sh setup                base setup (run INSIDE the chroot)
#
# Environment variables are passed through, so this works:
#   FS=ext4 ./gir.sh install nvme0n1
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
LIB=$DIR/lib

# Print the comment block at the top of this file, stopping at the first
# line of real code, so the help can never drift out of sync with it.
usage() {
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
    exit "${1:-1}"
}

cmd=${1:-menu}
[ $# -gt 0 ] && shift

case "$cmd" in
    menu|tui|"")  exec bash "$LIB/tui.sh" "$@" ;;
    install)      exec bash "$LIB/install.sh" "$@" ;;
    disk)         exec bash "$LIB/disk.sh" "$@" ;;
    stage3)       exec bash "$LIB/stage3.sh" "$@" ;;
    chroot)       exec bash "$LIB/chroot.sh" chroot "$@" ;;
    rescue)       exec bash "$DIR/rescue.sh" "$@" ;;
    setup)        exec bash "$LIB/setup.sh" "$@" ;;
    -h|--help|help) usage 0 ;;
    *)            echo "Unknown command: $cmd"; echo; usage ;;
esac
