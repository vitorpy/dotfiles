# Normal Fedora installation and USB recovery

The custom installer is cancelled. The SanDisk has the standard Fedora 44 KDE
installer plus an unencrypted ext4 partition labelled `RIVEST_BACKUP`.
`home.tar.zst` contains home, hidden files, permissions, ACLs, extended attributes,
symlinks/hardlinks and the protected root-reference archive. Disposable caches
and the old restore-test directory are excluded. No backup password is needed.
Check `BACKUP-VERIFIED.json` on the USB before erasing Arch.

1. Boot the SanDisk using Framework F12. Start the normal Fedora KDE installer.
2. Connect Wi-Fi normally. Install to the internal **WD PC SN5000S SDEPTSJ-512G**,
   serial **25343C801463**, 512 GB. Preserve the SanDisk and its backup partition.
   Use normal Fedora partitioning and disk encryption. Save the disk passphrase.
3. Create **vitorpy** as the first administrator. Keep hostname **rivest**.
4. Boot installed Fedora and sign into KDE once. Log out, press Ctrl+Alt+F3 and
   sign in as vitorpy. Check `id -u` and `id -g`: both should be **1000**.
5. Mount the USB backup and run the extraction below yourself. These local sudo
   commands are for the user; the assistant must not execute them.

```sh
udisksctl mount -b /dev/disk/by-label/RIVEST_BACKUP
backup=/run/media/vitorpy/RIVEST_BACKUP
cat "$backup/BACKUP-VERIFIED.json"
(cd "$backup" && sha256sum -c SHA256SUMS)
cp -a ~/.config ~/.config.fedora-fresh
sudo tar --zstd --extract --file="$backup/home.tar.zst" --directory=/home \
  --preserve-permissions --numeric-owner --acls --xattrs --xattrs-include='*' \
  --xattrs-exclude='security.selinux' \
  --exclude='vitorpy/.config/systemd/user' \
  --exclude='vitorpy/.config/environment.d' \
  --exclude='vitorpy/.config/uwsm' \
  --exclude='vitorpy/.local/share/dbus-1/services' \
  --exclude='vitorpy/.dmrc'
sudo restorecon -RF /home/vitorpy
sudo reboot
```

The initial extraction holds back Arch session activation, which remains fully
preserved in the USB archive. It keeps KDE available while applications and
Hyprland/Berg are installed. Do not extract root-reference.tar over Fedora's
system files; it is a private recovery reference inside the restored home.

After checking documents, projects and application data in KDE, use the separate
Fedora playbook in `~/.config/fedora/README.md`. Personal Arch configuration stays
available. Keep the USB until recovery is accepted; delete its backup only when
explicitly requested. The old encrypted NAS snapshots remain untouched.
