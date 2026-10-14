# Guided Rivest installation

This replaces the earlier proposal for a separate KDE live hardware-test boot.
The intended cutover is guided installer → encrypted home restore → one normal
reboot → provisioning → Plasma login → logout/select Hyprland. Physical hardware
acceptance happens after installation. Do not boot an unfinished rehearsal image
on Rivest: STATUS.md records the current validation and media state.

## Public build and private preparation

`migration.py public DESTINATION` creates an explicitly allowlisted payload with
the Fedora playbook and shared desktop configuration. It never exports vault
templates, browser profiles, private keys or personal documents. `build-public.sh`
runs as root only inside the Fedora build guest on Scherbius; it uses the verified
Fedora 44 Everything netinstaller, a Fedora-signed age binary and the previously
verified static Restic binary. Lorax updates both normal and embedded EFI boot
configuration. The customized ISO has its own checksum; it is not a Fedora-signed
ISO. Fedora's original boot executables remain signed.

After rehearsing, copy only the public ISO/payload back to the workstation cache.
Real backups and credentials must never be uploaded to Scherbius. The final
configuration commit must be pushed before pinning it in the payload.

Refresh protected recovery inputs locally (the assistant must not run local
sudo, as required by AGENTS.md):

```sh
umask 077
sudo ~/.config/fedora/migration/capture-root.sh > ~/.local/state/fedora-migration/root-reference.tar
migration_bw_session="$(bw unlock --raw)" && test -n "$migration_bw_session" && printf '%s' "$migration_bw_session" > "$XDG_RUNTIME_DIR/fedora-migration-bw-session"
unset migration_bw_session
```

Run `python3 ~/.config/fedora/migration/migration.py prepare --payload PAYLOAD`
in your own terminal. It adds a protected **USB bootstrap passphrase** field to
the existing Bitwarden **Rivest migration backup** item. Retrieve that field on a
separate device and enter it into the terminal's hidden prompt, never into chat.
Close stateful applications before typing BACKUP. Preparation pins the final NAS
snapshot, copies it to a separately encrypted local repository, checks every
data pack and restores the public fixture. The RAM-only bundle includes the
current selected Wi-Fi keyfile, existing user password hash and USB repository
password. Its encryption and decryption are checked before cleanup. Temporary
Bitwarden sessions and plaintext credentials are removed afterward.
If copying is interrupted, rerun the same prepare command after unlocking
Bitwarden again. Its encrypted checkpoint retains the same snapshot and USB
repository password; a resumed copy does not take another source snapshot.
Use `--cache` with a new subdirectory under the migration cache only when
deliberately starting a separate preparation; previous vault fields are retained.

`migration.py compose --iso ISO --recovery RECOVERY --output IMAGE --payload PAYLOAD` operates on a
regular image file only. It preserves the two or three Lorax/Fedora boot
partitions, relocates the backup GPT, and appends recovery as partition 4. Ext4 is
populated without local root or loop mounts. After GPT changes, Fedora's signed
isomd5sum tools refresh and verify the embedded media checksum. The encrypted repository and age
bundle fit on the authorized 15,376,000,000-byte USB; preparation measures actual
space rather than assuming the backup will always fit.

`write-usb.py IMAGE` uses UDisks and normal desktop authentication. It checks
SanDisk serial 03021830022221114151, capacity, removable USB transport, mounts and
holders, verifies the opened block device, writes with exclusive synchronous
direct I/O, reads back the entire image and rescans UDisks. It never invokes sudo
or changes device permissions. Receipts and images stay outside chezmoi.

## Installer behavior

The public Kickstart contains no partitioning instructions or passwords. Its
pre-install guard unlocks the age bundle into root-only `/run`, authenticates the
manifest against it, verifies public payload hashes, and connects Wi-Fi through
NetworkManager. Interface-name/MAC bindings are removed for Fedora. Connection,
DHCP/DNS and HTTPS repository checks must pass. The captured profile can be
corrected interactively; Wi-Fi passwords are never command-line arguments.

The guard verifies the exact USB snapshot and restores a known fixture before
offering to erase anything. The internal target must match model **WD PC SN5000S
SDEPTSJ-512G**, serial **25343C801463**, capacity **512,110,190,592 bytes**, NVMe
transport and the original partition fingerprint. You type the serial and enter
a new LUKS passphrase twice. A changed layout stops accidental reinstallation.
Recovery is mounted through a read-only loop view because Anaconda mounts the
ISO from the whole USB. Restic reads this immutable repository without locks.

Fedora installs native KDE, UEFI, an encrypted Btrfs root/home, UID/GID 1000 and
the existing login password hash. Root stays locked, SELinux enforcing, and
Fedora's display/power/network defaults remain native. Anaconda boots with
`inst.nosave=all`; temporary secret Kickstart directives are removed after use.

Before reboot, Restic restores into private staging with content verification;
rsync preserves home ownership, modes, ACLs, hardlinks and xattrs. Arch system
captures are references, not a system overlay. Arch user-service activation,
environment/session overrides and user D-Bus registrations are quarantined under
the restored home's migration state, then the reviewed public desktop files are
applied. SELinux labels are regenerated. Only artwork data is imported from the
protected system archive. Re-enroll fingerprints/re-pair Bluetooth as needed.
Native Bitwarden, Discord and Telegram profiles are copied into their verified
Flatpak config/data paths while retaining their originals. Existing Flatpak
profiles take precedence; stale Electron singleton locks are omitted from the
new copies. Applications may still require authentication after migration.

Updates run before the installation reboot. A root-owned first-boot controller
completes the Fedora playbook before the login manager starts. It enables only
the reviewed Berg/session services, preserves corporate package choices, and
checks required executables and enforcing SELinux. The first login is Plasma;
there is no autologin. Log out and choose packaged Hyprland/UWSM to check Berg.
The native greeter's remembered-session state is seeded to Plasma once; later
logins remember your normal session choice.
VM-only rendering variables and dummy credentials are never included on Rivest.

## Status, interruption and rollback

On installed Fedora, run `sudo rivest-migration status` to show verified phases. If setup
fails, use another TTY, sign in, and run `sudo rivest-migration resume` yourself.
The installed resume command has no partitioning path. An interrupted home
restore requires the USB and another bundle unlock; provisioning retries need no
backup password. Successful manual resume starts the login manager. Inspect
`journalctl -u rivest-migration` for sanitized provisioning output.

Keep the NAS backup, USB and private restore staging until acceptance. No
automatic retention/pruning or staging deletion is performed. Returning to Arch
requires reinstalling Arch and restoring the backup from the independent laptop;
reverting dotfiles alone does not reverse partitioning. Prior to physical
cutover, reverting the new dotfiles commit removes the preparation tools without
changing Rivest's partitions or boot configuration.

## Validation

Run `python3 -m unittest discover -s ~/.config/fedora/migration -p test_migration.py`.
The separate `guided-start.sh` server VM tests UEFI boot from a full-capacity USB
image with a dummy encrypted repository, target NVMe and decoy disk. Its lab-only
adapter substitutes QEMU's model and wired networking; production code has no
such bypass. Wireless configuration has independent tests, and actual physical
Wi-Fi must pass before erase. Restore/provision results and unresolved failures
are recorded in STATUS.md, not inferred from an ISO build succeeding.

References: [Lorax mkksiso](https://weldr.io/lorax/mkksiso.html),
[Kickstart](https://pykickstart.readthedocs.io/en/latest/kickstart-docs.html),
[Restic repository copies](https://restic.readthedocs.io/en/stable/045_working_with_repos.html#copying-snapshots-between-repositories).
