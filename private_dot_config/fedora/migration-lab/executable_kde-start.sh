#!/usr/bin/env bash
# Dedicated KDE/LUKS rehearsal, entirely separate from the Cloud guest.
set -euo pipefail
umask 077
[[ $(uname -n) == scherbius ]] || { echo 'Run this helper on Scherbius.' >&2; exit 1; }
lab=${XDG_DATA_HOME:-$HOME/.local/share}/fedora-kde-rehearsal
mode=${1:---live}
[[ $mode == --live || $mode == --disk || $mode == --install ]] || { echo "Usage: $0 [--live|--disk|--install]" >&2; exit 2; }
[[ -r /dev/kvm && -w /dev/kvm ]]
[[ -r $lab/images/Fedora-KDE-Desktop-Live-44-1.7.x86_64.iso ]]
mkdir -p "$lab/run"
if [[ -f $lab/run/qemu.pid ]] && kill -0 "$(cat "$lab/run/qemu.pid")" 2>/dev/null; then
    echo 'KDE rehearsal is already running'; exit 0
fi
if [[ $mode == --install ]]; then
    [[ ! -e $lab/install-started ]] || { echo 'An installation has already started. Preserve this disk; use --disk.' >&2; exit 1; }
    : > "$lab/install-started"
fi
[[ -f $lab/disk.qcow2 ]] || qemu-img create -f qcow2 "$lab/disk.qcow2" 80G
[[ -f $lab/OVMF_VARS.fd ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$lab/OVMF_VARS.fd"
boot=c
[[ $mode == --live ]] && boot=d
image=$lab/images/Fedora-KDE-Desktop-Live-44-1.7.x86_64.iso
installer=()
if [[ $mode == --install ]]; then
    image=$lab/images/Fedora-Everything-netinst-x86_64-44-1.7.iso
    installer=(-kernel "$lab/images/vmlinuz" -initrd "$lab/images/initrd.img"
        -append "inst.stage2=cdrom inst.ks=http://10.0.2.2:48765/install.ks console=ttyS0,115200 inst.nosave=all")
fi
seed=()
[[ ! -f $lab/seed.iso ]] || seed=(-drive "file=$lab/seed.iso,format=raw,media=cdrom,readonly=on")
rm -f "$lab/run/qmp.sock" "$lab/run/qemu.pid"
qemu-system-x86_64 -name fedora44-kde-rehearsal \
    -machine q35,accel=kvm,dump-guest-core=off -cpu host -smp 8 -m 16384 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
    -drive "if=pflash,format=raw,file=$lab/OVMF_VARS.fd" \
    -drive "file=$lab/disk.qcow2,format=qcow2,if=virtio,discard=unmap" \
    -cdrom "$image" "${seed[@]}" "${installer[@]}" \
    -boot "order=$boot" -device virtio-vga -device qemu-xhci -device usb-tablet \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:22245-:22 \
    -device virtio-rng-pci -display none -vnc 127.0.0.1:5 \
    -chardev "socket,id=labserial,path=$lab/run/serial.sock,server=on,wait=off,logfile=$lab/run/serial.log,logappend=on" \
    -serial chardev:labserial \
    -qmp "unix:$lab/run/qmp.sock,server=on,wait=off" \
    -pidfile "$lab/run/qemu.pid" -D "$lab/run/qemu.log" -daemonize
echo 'Started KDE rehearsal: 127.0.0.1:22245 SSH; 127.0.0.1:5905 VNC'
