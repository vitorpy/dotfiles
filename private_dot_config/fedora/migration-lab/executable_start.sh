#!/usr/bin/env bash
# Unprivileged KVM VM with localhost-only SSH and VNC.
set -euo pipefail
umask 077
lab_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fedora-migration-lab"
base_image="$lab_dir/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
failed=0
for tool in qemu-system-x86_64 qemu-img python3; do
    if ! command -v "$tool" >/dev/null; then
        printf 'Missing prerequisite: %s\n' "$tool" >&2
        failed=1
    fi
done
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    printf 'KVM is unavailable: vitorpy needs read/write access to /dev/kvm.\n' >&2
    failed=1
fi
for path in "$base_image" "$lab_dir/seed/seed.iso"; do
    if [[ ! -r "$path" ]]; then
        printf 'Missing prepared file: %s\n' "$path" >&2
        failed=1
    fi
done
(( failed == 0 )) || exit 1
if [[ "${1:-}" == --check ]]; then
    device_help=$(qemu-system-x86_64 -device help)
    grep -q 'name "virtio-vga"' <<< "$device_help"
    qemu_help=$(qemu-system-x86_64 -help)
    grep -q -- '-vnc ' <<< "$qemu_help"
    printf 'VM prerequisites are available.\n'
    exit 0
fi
if [[ $# -gt 0 ]]; then
    printf 'Usage: %s [--check]\n' "$0" >&2
    exit 2
fi
if [[ -f "$lab_dir/run/qemu.pid" ]]; then
    vm_pid=$(cat "$lab_dir/run/qemu.pid")
    if [[ "$vm_pid" =~ ^[0-9]+$ ]] && kill -0 "$vm_pid" 2>/dev/null \
        && grep -zq 'fedora44-migration-lab' "/proc/$vm_pid/cmdline"; then
        printf 'Fedora migration lab is already running (PID %s).\n' "$vm_pid"
        exit 0
    fi
fi
if [[ ! -f "$lab_dir/fedora44-lab.qcow2" ]]; then
    qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$lab_dir/fedora44-lab.qcow2" 80G
    qemu-img check "$lab_dir/fedora44-lab.qcow2"
fi
rm -f "$lab_dir/run/qmp.sock" "$lab_dir/run/qemu.pid"
qemu-system-x86_64 \
    -name fedora44-migration-lab \
    -machine q35,accel=kvm,dump-guest-core=off \
    -cpu host -smp 8 -m 16384 \
    -drive "file=$lab_dir/fedora44-lab.qcow2,format=qcow2,if=virtio,discard=unmap" \
    -drive "file=$lab_dir/seed/seed.iso,format=raw,if=virtio,readonly=on" \
    -device virtio-vga -device qemu-xhci -device usb-tablet \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:22244-:22 \
    -device virtio-rng-pci \
    -display none -vnc 127.0.0.1:4 \
    -serial "file:$lab_dir/run/serial.log" \
    -qmp "unix:$lab_dir/run/qmp.sock,server=on,wait=off" \
    -pidfile "$lab_dir/run/qemu.pid" -D "$lab_dir/run/qemu.log" -daemonize
printf 'Started Fedora lab: 8 vCPUs, 16 GiB RAM, 80 GiB thin disk.\n'
printf 'Guest SSH: 127.0.0.1:22244; VNC: 127.0.0.1:5904 (on Scherbius).\n'
