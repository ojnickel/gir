#!/bin/bash
# Autologin on tty1 -> Sway starts by itself (fish autostart from step 09)
# Works inside the chroot (/etc) and from the live USB (/mnt/gentoo, /mnt/gir)
U=${1:-ossi}
for R in /mnt/gentoo /mnt/gir ""; do [ -f "$R/etc/inittab" ] && break; done
F=$R/etc/inittab
[ -f "$F" ] || { echo "No inittab found"; exit 1; }
sed -i "s|^c1:.*|c1:12345:respawn:/sbin/agetty --autologin $U --noclear 38400 tty1 linux|" "$F"
# openrc-init systems use this file instead of inittab
echo "agetty_options=\"--autologin $U --noclear\"" > "$R/etc/conf.d/agetty.tty1"
grep '^c1:' "$F"
echo "done"
