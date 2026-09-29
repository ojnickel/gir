# GIR — Gentoo Install & Rescue

Two jobs, one toolkit, run from a live USB:

- **Rescue** — mount a Gentoo that will not boot, chroot into it, fix it.
- **Install** — partition a disk, verify and unpack a stage3, and build a
  working system with a distribution kernel and GRUB.

Rescue is where this started: a script to chroot into the machine when it is
failing, without re-reading the handbook every time to remember the six mount
commands. The installer grew out of the same scripts.

Works from the Gentoo live ISO or from any other live system with the usual
tools — **SystemRescue** is fine, and the scripts fall back to fetching the
Gentoo release key over WKD when there is no local keyring.

Targets **amd64 / UEFI** and follows the official
[Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64).

---

## Rescue a broken system

```sh
./gir.sh rescue /dev/nvme0n1p3      # your ROOT partition, not the whole disk
```

That mounts it, mounts everything else its own `/etc/fstab` asks for
(`/boot/efi`, `/home`, …), binds `/proc` `/sys` `/dev` `/run`, and drops you
into a chroot. Leave with `exit` — it unmounts on the way out.

A btrfs root inside a subvolume named `@` is detected and mounted correctly,
which is the case the plain handbook `mount` command gets wrong.

Because `/boot/efi` is mounted, the usual repairs just work:

```sh
grub-install --efi-directory=/boot/efi --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg
emerge --info
passwd
```

If the broken system's own Portage config is the problem, borrow a working
one instead:

```sh
./gir.sh rescue --borrow /mnt/working /mnt/broken
```

That binds the source's `/etc/portage`, ebuild repos, distfiles and binpkgs
into the target at the same paths, so `emerge` inside the chroot uses the
config that works.

## Install from scratch

**This erases an entire disk. Read the summary it prints before confirming.**

```sh
./gir.sh                            # menu, easiest
./gir.sh install nvme0n1            # or non-interactive
FS=ext4 ./gir.sh install sda systemd
```

Then, inside the chroot it leaves you in:

```sh
bash /root/setup.sh
```

---

## Layout

```
gir.sh          single entry point — every command below
rescue.sh       mount a broken system and chroot in
.env            your defaults (tracked on purpose)
env.example     reference for every option
lib/
  tui.sh        menu front end (dialog, whiptail, or plain text)
  install.sh    disk.sh -> stage3.sh -> chroot.sh in order
  disk.sh       GPT partitioning, filesystem, mounts, fstab
  stage3.sh     download, GPG-verify and unpack a stage3
  chroot.sh     mount pseudo-filesystems and chroot (also the borrow mode)
  setup.sh      everything inside the chroot: profile, kernel, services, GRUB
```

Every script in `lib/` still runs standalone, so you can resume after a
failure instead of starting over:

```sh
bash lib/stage3.sh openrc
bash lib/chroot.sh chroot /mnt/gentoo
```

## Requirements

- Booted in **UEFI** mode (`/sys/firmware/efi` must exist)
- Root
- Network
- `sgdisk`, `wipefs`, `partprobe`, `mkfs.vfat`, `mkswap`, `blkid`, `gpg`,
  `tar`, `xz`, plus `mkfs.<fs>` for the filesystem you pick

Each script checks and names anything missing **before** touching the disk.

---

## disk.sh — partitioning

```sh
bash lib/disk.sh DISK        # e.g. sda, nvme0n1
```

Layout: partition 1 EFI, 2 swap (unless disabled), last one root. NVMe/eMMC
`p` suffixes are handled.

| Variable | Default | Meaning |
|---|---|---|
| `FS` | `btrfs` | Root filesystem: `btrfs`, `ext4`, `xfs` |
| `DATA` | `dup` | Btrfs data profile: `dup` or `single` (btrfs only) |
| `EFI_SIZE` | `1G` | EFI system partition size |
| `SWAP_SIZE` | `8G` | Swap size, `0` for no swap partition |
| `LABEL` | `gentoo` | Root filesystem label |
| `MNT` | `/mnt/gentoo` | Where the new system is mounted |
| `CONFIRM` | *(unset)* | `YES` skips the interactive confirmation |

**btrfs** additionally gets subvolumes `@` (`/`), `@home` and `@snapshots`,
mounted `noatime,compress=zstd:3`. **ext4** and **xfs** are one plain
filesystem; only ext4 gets a boot-time fsck pass in the fstab.

```sh
FS=xfs SWAP_SIZE=0 bash lib/disk.sh nvme0n1
```

## stage3.sh — download and verify

```sh
bash lib/stage3.sh [VARIANT]    # openrc (default), systemd, desktop-openrc, ...
```

The signature must chain to the Gentoo release key
`13EBBDBE DE7A1277 5DFDB1BA BB572E0E 2D182910`. The signing subkey is traced
back to that primary key, so a valid signature from some *other* key in the
keyring is rejected — which matters on SystemRescue, where the key is fetched
over WKD rather than shipped. The `latest-stage3` list is verified before it
is parsed, so a tampered list cannot point at an old build. Cross-check the
fingerprint at <https://www.gentoo.org/downloads/signatures/>.

## setup.sh — inside the chroot

`chroot.sh` copies it to `/root/setup.sh` for you.

It **detects** the init system (OpenRC or systemd) from the unpacked stage3
and the root filesystem from the mount, then picks the matching profile,
service manager, keymap file and filesystem tools. Safe to re-run: finished
steps are marked in `/var/lib/setup.sh/` and skipped. Log in
`/var/log/setup.log`.

### Your defaults: .env

Hostname, user, locale and keyboard live in `.env`, **not** in the scripts.
That file is tracked in git, so a fresh clone already has them — nothing to
carry to the live system separately.

They are **defaults, not decisions**: every one is offered in a prompt and can
be typed over. An environment variable wins for a single run:

```sh
CFG_HOSTNAME=laptop ./gir.sh setup
UNATTENDED=1 ./gir.sh setup          # accept everything, ask nothing
```

| Variable | In the tracked `.env` | Meaning |
|---|---|---|
| `CFG_HOSTNAME` | `gentoo` | Hostname |
| `CFG_USER` | `ossi` | Account to create (added to `wheel`) |
| `CFG_TZONE` | `Europe/Berlin` | Time zone |
| `CFG_LANG` | `de_DE.UTF-8` | System locale |
| `CFG_KBD` | `de` | X/Wayland keyboard layout |
| `CFG_CONSKBD` | `de-latin1-nodeadkeys` | Console keymap |
| `CFG_SHELL` | `fish` | Login shell: `bash`, `fish`, `zsh` |
| `CFG_DESKTOP` | `sway` | `sway` or `none` (console only) |
| `CFG_PROFILE` | `plain` | `plain` or `desktop` — see below |
| `CFG_ROOT_PW` | *(empty — prompted)* | root password |
| `CFG_USER_PW` | *(empty — prompted)* | user password |
| `UNATTENDED` | *(empty)* | `1` accepts everything without asking |

Search order: `$SETUP_ENV`, `/root/.env`, `.env` beside the script, the repo
root, then `~/.env`. First hit wins. With no `.env` at all, every personal
field starts empty and is asked for; empty answers are refused.

`env.example` documents all of it if you want to start clean.

### Passwords

Both are **empty** in the tracked `.env`, which is the right choice for a file
in version control: you get prompted at the end and nothing is written to
disk.

If you do store one, never put plaintext in a tracked file. Use a hash — a
value starting with `$` is passed to `chpasswd -e`:

```sh
openssl passwd -6        # or: mkpasswd --method=yescrypt
```

**Single-quote it.** `.env` is sourced by bash, so an unquoted `$6$salt$digest`
expands to nothing:

```sh
CFG_ROOT_PW='$6$salt$digest'     # correct
CFG_ROOT_PW=$6$salt$digest       # WRONG — bash eats it
```

A hash in a repo can still be attacked offline, so the prompt stays better.
`setup.sh` rejects a value that starts with `$` but is not a well-formed hash,
so a mangled one fails loudly instead of setting a password nobody knows.
Passwords are piped straight into `chpasswd` and never reach stdout, so they
stay out of the log. `/root/.env` — the throwaway copy inside the chroot — is
shredded after a successful run.

### plain vs desktop profile

The official binary host is built against the **plain** profile. The desktop
profile changes USE flags globally, so most binary packages stop matching and
get built from source — hours instead of minutes. Sway does not need it, so
`plain` is the default.

`cpuid2cpuflags` still writes your CPU's native `CPU_FLAGS_X86`, which
invalidates some binary packages regardless. "Binary host" never means zero
compiling.

### What it installs

`gentoo-kernel-bin` with dracut and GRUB, microcode on Intel, NetworkManager,
cronie, sudo, and the tools for your root filesystem. On OpenRC it adds
sysklogd, chrony and elogind; systemd covers those itself. With
`CFG_DESKTOP=sway`: Sway, waybar, foot, fuzzel, mako, PipeWire and fonts, plus
an autostart snippet for tty1 in your login shell.

---

## Notes and deviations from the handbook

- The EFI system partition is mounted at **`/boot/efi`**, not the handbook's
  newer `/efi`. Both work with GRUB; it only changes where the ESP appears.
- `/boot` is on the root filesystem, so GRUB reads the kernel from it. On
  btrfs that relies on GRUB's btrfs and zstd support — fine on GRUB 2.12.
- GRUB is installed twice on purpose: an NVRAM entry, and the removable
  fallback `\EFI\BOOT\BOOTX64.EFI`, so the machine still boots if the
  firmware loses its entry.
- The filesystem's userspace tools are installed **before** the kernel, so
  dracut's modules find them — `90btrfs` starts with
  `require_binaries btrfs || return 1` and silently skips itself otherwise.

## Troubleshooting

**`/boot/efi is not mounted`** — `setup.sh` checks this up front rather than
failing after an hour of compiling:

```sh
mount /dev/<disk>1 /mnt/gentoo/boot/efi     # NVMe: /dev/nvme0n1p1
```

**Re-run after a failure** — `setup.sh` skips completed steps. To redo one,
delete its marker:

```sh
rm /var/lib/setup.sh/07-kernel
```

**Signature check failed** — usually a wrong clock, since TLS and GPG both
depend on it. `stage3.sh` prints the date it is working with.

**`rescue.sh` says "is a whole disk"** — pass the root *partition*
(`/dev/sda3`), not the disk (`/dev/sda`). It prints the partition table to
help you pick.

## Status

The partitioning, `emerge` and GRUB paths have not been run end to end on real
hardware. Logic is covered by static checks and stubbed runs; the destructive
and long-running parts are not. Keep a live USB handy.
