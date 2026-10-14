#!/usr/bin/env bash
# Separate USB/Kickstart rehearsal on Scherbius. No physical disks or host mounts.
set -euo pipefail
umask 077
[[ $(hostname -s) == scherbius ]]
work=$HOME/.local/share/fedora-guided-rehearsal
[[ -f $work/dummy-usb.raw && $(stat -c %s "$work/dummy-usb.raw") == 15376000000 ]]
mkdir -p "$work/run"
if [[ -f $work/run/qemu.pid ]] && kill -0 "$(cat "$work/run/qemu.pid")" 2>/dev/null; then
    echo 'Guided rehearsal already running'; exit 0
fi
[[ -f $work/target.qcow2 ]] || qemu-img create -f qcow2 "$work/target.qcow2" 512110190592
[[ -f $work/decoy.qcow2 ]] || qemu-img create -f qcow2 "$work/decoy.qcow2" 8G
[[ -f $work/OVMF_VARS.fd ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$work/OVMF_VARS.fd"
rm -f "$work/run/qmp.sock" "$work/run/serial.sock"
qemu-system-x86_64 -name rivest-guided-usb-rehearsal \
    -machine q35,accel=kvm,dump-guest-core=off -cpu host -smp 8 -m 16384 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
    -drive "if=pflash,format=raw,file=$work/OVMF_VARS.fd" \
    -drive "file=$work/target.qcow2,format=qcow2,if=none,id=target,discard=unmap" \
    -device nvme,drive=target,serial=25343C801463,bootindex=1 \
    -drive "file=$work/decoy.qcow2,format=qcow2,if=none,id=decoy" \
    -device virtio-blk-pci,drive=decoy,serial=DECOY-DO-NOT-ERASE \
    -device qemu-xhci -device usb-tablet \
    -drive "file=$work/dummy-usb.raw,format=raw,if=none,id=installer,readonly=on" \
    -device usb-storage,drive=installer,removable=on,serial=03021830022221114151,bootindex=2 \
    -device virtio-vga -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:22246-:22 \
    -device virtio-rng-pci -display none -vnc 127.0.0.1:6 \
    -chardev "socket,id=serial,path=$work/run/serial.sock,server=on,wait=off,logfile=$work/run/serial.log,logappend=on" \
    -serial chardev:serial -qmp "unix:$work/run/qmp.sock,server=on,wait=off" \
    -pidfile "$work/run/qemu.pid" -D "$work/run/qemu.log" -daemonize
echo 'Started isolated guided USB rehearsal; SSH 127.0.0.1:22246, VNC 127.0.0.1:5906'
