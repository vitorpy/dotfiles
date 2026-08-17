# Arch maintenance TODO

These items are intentionally separate from the UKI, pacnew, and GNOME Keyring
pass.

## Backups

- Select and deploy an encrypted off-site backup workflow, likely Restic or
  Borg against the existing Storage Box account, with explicit retention and
  failure notifications.
- Define the backed-up data set: the primary home, chezmoi source, selected
  system configuration, and any application state that cannot be recreated.
- Back up recovery material separately and securely, including an offline LUKS
  header copy, tested encrypted-home recovery credentials, and the `sbctl` key
  set. Do not store recovery material only on this laptop or inside its normal
  backup repository.
- Document and perform a restore drill, including a sample file restore and a
  bare-machine configuration recovery rehearsal.

## Timers

- Add a monthly `btrfs-scrub@-.timer` policy with laptop/NVMe-friendly resource
  limits and alerting on errors.
- Enable and size a `paccache.timer` policy after choosing package retention;
  the current cache has no removals at the keep-three threshold.
- Review and enable `fwupd-refresh.timer`, then confirm refresh failures are
  visible rather than silent.
- Decide whether encrypted-home discard is acceptable before enabling
  `fstrim.timer`; document the storage-recovery benefit and allocation-leakage
  tradeoff.
