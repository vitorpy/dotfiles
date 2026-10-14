# Software-graphics VM reproductions — 2026-10-14

The clean Fedora 44 KDE guest uses virtio-vga without a render node or virgl,
Mesa software rendering and a UWSM-managed Hyprland session. Scherbius exposes
ASPEED display hardware and no render node. Kernel 7.2.10-200.fc44, Hyprland
0.56.2-3, Aquamarine 0.15.1-1, hyprpaper 0.8.4-3, Mesa 26.2.4 and the packaged
xdg-desktop-portal-hyprland 1.4.1-1 were used. SELinux stays Enforcing.

## Wallpaper: reproduced with three image formats

A public 64×64 solid-color image was generated with ImageMagick and converted to
PNG, JPEG and WebP. Each was tested separately with this minimal configuration:

```ini
ipc = false
splash = false
wallpaper {
    monitor =
    path = /var/tmp/hyprpaper-repro/tiny.png
    fit_mode = cover
}
```

Run `hyprpaper -c /var/tmp/hyprpaper-repro/png.conf` as the active desktop user,
with HOME, XDG_RUNTIME_DIR, WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE
matching the real session. Use a clean environment when launching from guest
root SSH; inherited root Flatpak icon paths cause an unrelated permission error.
The three valid clean-environment tests all exited 139/SIGSEGV immediately.
Their logs ended:

```text
KMS: DRM_IOCTL_MODE_CREATE_DUMB failed: Permission denied
GBM: Failed to allocate a GBM buffer: bo null
Swapchain: Failed acquiring a buffer
Segmentation fault (core dumped)
```

The core stack enters `Hyprtoolkit::CWaylandBuffer::CWaylandBuffer` from
`IWaylandWindow::resizeSwapchain`. In inspected upstream commit
`2907e0d1f8a3a540737a0e738acc40d48ad7ba0d`, resizeSwapchain passes next() into
CWaylandBuffer, whose constructor dereferences buffer->dmabuf() without checking
for a null buffer. A failed GBM allocation reaching this dereference is an
inference consistent with the logs and stack. It is not a confirmed upstream fix.

The image format and fetched artwork content are excluded by the tiny-image
reproduction. Logs/configurations are retained at `/var/tmp/hyprpaper-repro/` in
the clean guest. The shared workstation wallpaper configuration was not changed.

## Capture and application observations

The preserved Cloud guest's screen-capture attempt crashed the compositor in
Aquamarine's DRM output commit path with EGL_BAD_PARAMETER. Plasma's portal
screen capture passed in the clean guest. The clean KDE-based guest subsequently
also passed Hyprland capture: the picker selected only Virtual-1, the probe
produced a nonempty PNG through the portal PipeWire FD and closed its session.
The compositor PID remained 11942 and no new core dump occurred. This is a
successful clean-guest result, not an identified fix for the preserved Cloud
guest. A physical Intel-GPU capture test remains an acceptance gate.

Slack renders its sign-in window in clean-guest Hyprland after creating a
lab-only keyring. An explicit native-Wayland launch and ordinary launcher checks
rendered successfully. Stopping its process with systemctl caused a SIGTRAP;
Ctrl+Q closed the test window successfully. Zoom rendered sign-in when its
launch omitted the VM-only QT_QUICK_BACKEND=software override. A ZoomWebviewHost
SIGABRT occurred at 15:25:27 during the first launch, before systemctl stop at
15:25:56. No further Zoom core dump was recorded during the normal-Qt rerun.
Flatpak startup also activated a failed IBus portal unit; input-method integration
remains untested despite successful login-window rendering. Account calls and application sharing are
still pending. Do not equate a welcome window with a verified corporate workflow.

This report is retained locally for a reviewable upstream issue; no issue was
posted. Hardware acceptance and account-workflow checks are in ACCEPTANCE.md.

## Primary source inspected

- [Hyprtoolkit buffer and swapchain implementation](https://github.com/hyprwm/hyprtoolkit/blob/2907e0d1f8a3a540737a0e738acc40d48ad7ba0d/src/window/IWaylandWindow.cpp)
