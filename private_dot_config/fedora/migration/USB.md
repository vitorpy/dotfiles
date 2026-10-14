# Rivest Fedora live USB — 2026-10-14

The user explicitly authorized re-imaging the connected installer USB. The target
is the 15,376,000,000-byte SanDisk 3.2Gen1, serial 03021830022221114151, identified
through its persistent device ID. It previously contained ARCH_202605 and had no
mounted filesystems. The workstation's internal WD NVMe is a separate device.

Image: `Fedora-KDE-Desktop-Live-44-1.7.x86_64.iso`, 3,368,683,520 bytes.
SHA256: `c8295961d4c41adbf785a31a17c21a971d3b7415fda72dcad0c11c49577bf03a`.
Fedora's signed checksum verified with its Fedora 44 signing fingerprint
`36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6`. The ISO was copied from Scherbius
and the complete local copy matched the signed checksum before writing.

The write uses UDisks OpenDevice and normal desktop authentication. It does not
use local sudo, a root shell, new device permissions or a system configuration
change. The one-shot helper rechecks model, serial, size, USB/removable status,
mounts and holders, then verifies the opened device's identity and capacity.
Exclusive direct I/O with synchronous writes confines the operation to this USB;
complete direct-read SHA256 verification follows the write. No new runtime
package or persistent imaging service is installed.

Write and complete direct-read verification passed. All 3,368,683,520 written
bytes matched the signed image SHA256. The receipt is stored in
`~/.local/state/fedora-migration/usb-verification.json`, mode 0600.
A post-write UDisks rescan confirmed GPT, `Fedora-KDE-Live-44` and its BOOT EFI
partition. Both USB partitions remain unmounted.
The ISO and signed checksum remain under `~/.cache/fedora-migration/usb/`.

## Next boot: live hardware checks

1. Save work and reboot when convenient. Keep the SanDisk connected and tap F12
   immediately after powering on, before the Framework logo. Select its EFI USB
   boot entry. This step is user-controlled; no reboot is scheduled automatically.
2. Select **Test this media & start Fedora-KDE-Desktop-Live**. That exact entry is
   present in this ISO and is its default boot selection.
3. Use the live desktop for the hardware checks in ACCEPTANCE.md. If the installer
   opens automatically, close it while testing. Check Wi-Fi, audio/microphone,
   camera, touch, brightness, Bluetooth, dock/monitor and suspend/resume.
4. Record results and return to Arch to finish recovery and final-backup gates.
   The live medium has KDE; Hyprland/Berg provisioning and its remaining Intel-GPU
   checks are described in the Fedora runbook.

Secure Boot was reported disabled by this workstation's firmware before imaging;
no firmware setting was changed. The USB contains the standard Fedora live image,
not the VM's automated installation recipe. Installation remains a separate step
following independent recovery and the final quiesced backup checks.

The USB now replaces the previous Arch installer. For an Arch reinstall rollback,
use the personal Arch laptop to prepare Arch installer media and access the
verified NAS backup. Preserve that independent-device recovery route.

## Sources

- [Fedora KDE image and verification instructions](https://fedoraproject.org/kde/download/)
- [UDisks device-scoped imaging interface](https://storaged.org/doc/udisks2-api/latest/gdbus-org.freedesktop.UDisks2.Block.html)
- [Framework Laptop 12 Fedora KDE guide and F12 boot instructions](https://guides.frame.work/Guide/Fedora+KDE+Plasma+Desktop+44+on+a+Framework+Laptop+12+(13th+Gen+Intel%C2%AE+Core%E2%84%A2)/857)
