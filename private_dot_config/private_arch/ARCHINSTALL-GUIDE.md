# Arch Linux Installation Guide

Using archinstall with the provided configuration file.

## Quick Install

1. **Boot Arch ISO** (from USB or VM)

2. **Connect to internet** (if using WiFi):
   ```bash
   iwctl
   station wlan0 connect "Your-Network-Name"
   exit
   ```

3. **Download the config**:
   ```bash
   curl -O https://raw.githubusercontent.com/vitorpy/dotfiles/main/.config/arch/archinstall-config.json
   ```

   Or if you have the file on USB:
   ```bash
   # Mount USB and copy the file
   mount /dev/sdX1 /mnt
   cp /mnt/archinstall-config.json .
   ```

4. **Run archinstall**:
   ```bash
   archinstall --config archinstall-config.json
   ```

5. **Follow prompts** for:
   - Disk selection and partitioning
   - User creation (username and password)
   - Root password

6. **After installation completes**, reboot:
   ```bash
   reboot
   ```

7. **Post-install setup**:
   ```bash
   # Login as your user
   # Run the bootstrap script
   curl -sSL https://vitorpy.com/bootstrap.sh | bash

   # Install hyprcorners
   cargo install hyprcorners

   # Reboot to start Hyprland with ly
   sudo reboot
   ```

## Configuration Details

### Hostname
- **zygalski**

### Timezone
- **Europe/Warsaw**

### Locale
- **en_US.UTF-8**
- Keyboard: US

### Bootloader
- **systemd-boot** (modern, simple UEFI bootloader)

### Kernel
- **linux** (latest stable kernel)

### Network
- **NetworkManager** (enabled at boot)

### Audio
- **PipeWire** (with ALSA, PulseAudio, and JACK support)

### Services Enabled
- NetworkManager (networking)
- sshd (SSH server)

### Pre-installed Packages
Essential packages for the bootstrap script to work:
- base, base-devel, linux-firmware
- git, neovim, fish
- curl, wget, jq, openssh, rsync
- NetworkManager
- PipeWire audio stack

## Disk Partitioning

The configuration is **fully automated** for replacing Fedora on `/dev/nvme0n1`.

### What It Does

The archinstall config will:
1. **Keep** the existing EFI partition (600M) - **NO FORMATTING**
2. **Delete** existing partitions 2 and 3 (old /boot and Fedora root)
3. **Create** new root partition using all remaining space (~464G)
4. **Enable** zram swap (configured via `"swap": true`)

### Resulting Layout
```
/dev/nvme0n1p1  600M   EFI (existing)  /boot      [KEPT - not wiped]
/dev/nvme0n1p2  ~464G  ext4 (new)      /          [FORMATTED]
[zram0]         ~8G    zram            [swap]     [IN-MEMORY]
```

### IMPORTANT: Different Disk?

If your disk is **NOT** `/dev/nvme0n1`, edit the config before running:

```bash
# Check your disk name
lsblk

# Edit the config to change device
nvim archinstall-config.json
# Change "device": "/dev/nvme0n1" to your disk (e.g., /dev/sda)
```

## Customization

Before running archinstall, you can edit the JSON:

```bash
nvim archinstall-config.json
```

### Common Changes:
- **Hostname**: Change `"hostname": "zygalski"`
- **Timezone**: Change `"timezone": "Europe/Warsaw"`
- **Mirrors**: Add your country's mirrors for faster downloads
- **Swap size**: Adjust in disk configuration

## After Installation

Once archinstall finishes and you reboot:

1. Login with your user
2. Run the bootstrap script (see above)
3. All your dotfiles, packages, and configurations will be applied
4. SSH and GPG keys restored from Bitwarden
5. Ready to use!

## Troubleshooting

### WiFi not working after install
```bash
nmcli device wifi list
nmcli device wifi connect "SSID" password "password"
```

### Can't connect to internet during install
```bash
# Check connection
ping archlinux.org

# If using WiFi, use iwctl
iwctl
station wlan0 connect "Your-Network"
```

### archinstall command not found
Update the live system:
```bash
pacman -Sy archinstall
```

## Manual Installation

If you prefer manual installation without archinstall, follow the [Arch Installation Guide](https://wiki.archlinux.org/title/Installation_guide), then run the bootstrap script after first boot.
