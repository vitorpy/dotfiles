# Current USB: standard Fedora KDE plus home backup

The selected path is a normal Fedora installation and manual home recovery.
Guided automation is cancelled. See SIMPLE-INSTALL.md for the short procedure.

Authorized device: SanDisk 3.2Gen1, 15,376,000,000 bytes, serial
03021830022221114151. The internal WD NVMe is not the USB backup target.

The original Fedora KDE 44 live image passed its full 3,368,683,520-byte SHA256
read-back again before partition changes. Its signed original SHA256 is
`c8295961d4c41adbf785a31a17c21a971d3b7415fda72dcad0c11c49577bf03a`.
Fedora 44 signing fingerprint:
`36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6`.

The original installer/EFI partitions are retained. Unused space became a separate
12,005,146,624-byte ext4 partition labelled **RIVEST_BACKUP**. Its backup is
unencrypted, as explicitly requested. The embedded installer media checksum was
refreshed after GPT changes and passed. No Kickstart, bootstrap password or
custom installation controller is used by this standard installer.

The backup is streamed directly from home to `home.tar.zst` on the USB; no second
copy is created locally or on the NAS. `SHA256SUMS` and `BACKUP-VERIFIED.json`
record verification. The original NAS snapshots are preserved.

Use F12 to boot the standard Fedora KDE installer. Choose only the internal
512 GB WD disk for installation and keep the SanDisk intact. Create vitorpy as
the first user and restore using SIMPLE-INSTALL.md. No reboot is scheduled.

Partitioning and formatting use UDisks desktop authorization, with exact device
identity checks. The assistant does not execute local sudo or change device
permissions. The original installer remains cached under
`~/.cache/fedora-migration/usb/`; private backup data is written only to USB.
