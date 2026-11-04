# configs/

Back to the article: [README.md](../README.md)

These are the **actual files** from one ThinkPad T440s (i5-4200U Haswell, `intel_cpufreq`, i915) running CachyOS KDE Wayland with the BORE kernel, TLP 1.10.2 and tlp-pd. They are copied verbatim from the article. They are a record to read, split up and audit — **not a one-click root installer**.

| File | Install location | What it does |
|---|---|---|
| [`tlp/90-cachyos-t440s.conf`](tlp/90-cachyos-t440s.conf) | `/etc/tlp.d/90-cachyos-t440s.conf` | TLP drop-in: profile auto-switch (AC → Performance, battery → Balanced), EPB, iGPU frequency limits, SATA link power, PCIe ASPM, runtime PM, Wi-Fi power save off, Bluetooth off at boot. |
| [`cpu-helper/cachyos-cpu-governor`](cpu-helper/cachyos-cpu-governor) | `/usr/local/libexec/cachyos-cpu-governor` (executable, root-owned) | Python D-Bus helper. Listens for power-profile, AC and resume events and **exclusively owns** CPU governor, turbo and frequency limits. Needs system Python + PyGObject (`python-gobject` on Arch/CachyOS). |
| [`systemd/cachyos-cpu-governor.service`](systemd/cachyos-cpu-governor.service) | `/etc/systemd/system/cachyos-cpu-governor.service` (root-owned) | Runs the helper after `tlp-pd.service` / `upower.service`, sandboxed, write access only to `/sys/devices/system/cpu`. On stop it runs `--restore`. |
| [`kernel-cmdline.md`](kernel-cmdline.md) | your bootloader's **BORE entry only** | The single `systemd.mask=scx_loader.service` parameter and how to verify it. |
| [`../scripts/readback.sh`](../scripts/readback.sh) | run from anywhere | Read-only diagnostics: read back what the kernel and services *actually* use. |

## Why the TLP CPU entries are empty

Every `CPU_DRIVER_OPMODE_*`, `CPU_SCALING_GOVERNOR_*`, `CPU_SCALING_MIN/MAX_FREQ_*`, `CPU_MIN/MAX_PERF_*` and `CPU_BOOST_*` entry is set to `""` **on purpose**. The helper owns those knobs; leaving them empty stops TLP and the helper from double-writing the same sysfs files. TLP still sets EPB (`CPU_ENERGY_PERF_POLICY_*`).

Consequence: **copying only the TLP file will not give you the three-tier CPU behaviour** described in the article. You need the helper + unit as well.

## Before you copy anything

- **PCI addresses are topology, not serials — and yours may differ.** `00:1c.4` is the NVIDIA dGPU's upstream PCIe bridge and `03:00.0` is the Wi-Fi card *on this machine*. Find yours with `lspci` (e.g. `lspci -nn`, `lspci -tv`) before reusing `RUNTIME_PM_ENABLE` / `RUNTIME_PM_DENYLIST`.
- **Interface names differ.** `scripts/readback.sh` uses `wlan0`; check yours with `ip link` or `iw dev`.
- The helper only touches cpufreq policies whose driver is `intel_cpufreq` (intel_pstate in passive mode). It is not meant for AMD or newer Intel (HWP) machines.
- The helper writes `1600000` to `scaling_max_freq` in saver mode; on this machine the kernel clamps that to 1.5 GHz because the turbo activation ratio is 15×. That is expected — see the article ("Why the saver cap is 1.5 GHz, not 1.6").
- Don't let a user-writable script be executed by a root service. Review the code and your environment first.

## Enabling the services

After the files and dependencies are installed:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tlp.service tlp-pd.service
sudo systemctl enable --now cachyos-cpu-governor.service
```

These lines only enable services. They do **not** remove the old PPD, install the helper, resolve package conflicts, change KDE's auto profile switching, or set up the BORE boot entry. They are not a complete migration.

---

