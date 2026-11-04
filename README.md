Configs: [`configs/`](configs/) · Read-only checks: [`scripts/readback.sh`](scripts/readback.sh)

# Old Laptop Still Works

> **A decade-old ThinkPad on CachyOS — and a tour of every wrong assumption I made along the way.**
> Performance, power management, hardware video decode: measured, read back, and reported without the marketing.

**TL;DR**

- A Haswell i5-4200U with 12 GB RAM, a SATA SSD and two batteries at ~60% of design capacity is now a genuinely usable daily work machine: desktop, browser, dev tools and AI clients (cloud models — *not* local LLMs).
- Final stack: **BORE kernel + TLP 1.10.2 + tlp-pd + an 85-line Python D-Bus helper** that exclusively owns the CPU governor, turbo and frequency limits. One owner per knob, no tool fights.
- **No battery miracle.** Moving PPD → TLP cut average discharge by only ~0.27 W (~3.4%) in single ~2-minute windows. Not statistically significant, and I won't pretend otherwise.
- The real wins were diagnostic: SCX was *installed but not running*; a major source of the "mystery" fan noise was a terminal UI that kept redrawing; `pwm1=255` does not mean full speed; and "turbo off, max 1.6 GHz" actually clamps to **1.5 GHz**.
- Everything is reproducible as files in [`configs/`](configs/), verified by reading back live sysfs/service state, with a rollback plan — but it is **not a one-click script**.

**Final setup at a glance**

| | ⚡ Performance | ⚖️ Balanced | 🐢 Power-saver |
|---|---|---|---|
| Selected | automatically on AC | automatically on battery | manually (leftmost KDE slot) |
| CPU governor | `performance` | `schedutil` | `conservative` |
| CPU range | 800–2600 MHz | 800–2600 MHz | 800–1500 MHz |
| Turbo | on | on | off |
| CPU EPB | performance / 0 | balance_power / 8 | power / 15 |
| iGPU range | 200–1000 MHz | 200–1000 MHz | 200–400 MHz |
| SATA link | `max_performance` | `med_power_with_dipm` | `med_power_with_dipm` |
| Wi-Fi power save | off | off | off |
| Fan | EC auto | EC auto | EC auto |

## Who this is for / not for

**For you if:**

- You run an old Intel laptop — specifically **Haswell-era**, with `intel_pstate` in passive mode (`intel_cpufreq` driver) and Intel **i915** graphics — and want it to feel good, not just benchmark well.
- You want to understand *which layer owns what* (kernel scheduler vs. sched_ext vs. cpufreq governor vs. power daemon) instead of stacking "optimization packs".
- You like debugging stories where the author is wrong several times and says so.

**Not for you if:**

- You're on **AMD or a newer Intel** CPU (HWP/Speed Shift, `platform_profile`). The CPU helper and the numbers here do not transfer.
- You want a **one-click installer**. This is a configuration record to read, split up and audit. The public version deliberately ships no installer or rollback script tied to my private backups.
- You're hoping for doubled battery life. Software can't un-age a battery's chemistry.

<!-- TODO (optional): add a real photo of the machine or a real `tlpctl get` / `tlp-stat` screenshot here. Do not use stock or generated images. -->

---

## Contents

1. [How old is this machine, exactly?](#1-how-old-is-this-machine-exactly)
2. [The goal was never "enable every power-saving knob"](#2-the-goal-was-never-enable-every-power-saving-knob)
3. [Baseline: what I assumed ≠ what was running](#3-baseline-what-i-assumed--what-was-running)
4. [Phase 1: PPD + SCX — split performance from battery](#4-phase-1-ppd--scx--split-performance-from-battery)
5. [A very real trap: Wi-Fi power save vs. Mesh](#5-a-very-real-trap-wi-fi-power-save-vs-mesh)
6. [Fan screaming: the load was the terminal I was looking at](#6-fan-screaming-the-load-was-the-terminal-i-was-looking-at)
7. [Phase 2: switch to BORE, don't stack schedulers](#7-phase-2-switch-to-bore-dont-stack-schedulers)
8. [Phase 3: three CPU tiers](#8-phase-3-three-cpu-tiers)
9. [Phase 4: PPD → TLP + tlp-pd](#9-phase-4-ppd--tlp--tlp-pd)
10. [Device power management: kept vs. not adopted](#10-device-power-management-kept-vs-not-adopted)
11. [Display: PSR on doesn't mean DRRS can be](#11-display-psr-on-doesnt-mean-drrs-can-be)
12. [What the old iGPU is actually good at: H.264](#12-what-the-old-igpu-is-actually-good-at-h264)
13. [What the impressive-looking numbers actually prove](#13-what-the-impressive-looking-numbers-actually-prove)
14. [Conflict cleanup, reboot and update verification](#14-conflict-cleanup-reboot-and-update-verification)
15. [The reproducible part](#15-the-reproducible-part)
16. [Backup and rollback are part of the design](#16-backup-and-rollback-are-part-of-the-design)
17. [**What I believed vs. what was true**](#17-what-i-believed-vs-what-was-true)
18. [Lessons](#18-lessons)
19. [References](#references)

> Compiled 2026-11-03; most experiments ran in October 2026.
>
> This is a real log of debugging, experimenting and correcting mistakes together with an AI assistant. The goal: make an old machine pleasant for daily use and leave behind a setup that can be re-checked and rolled back. All numbers come from limited measurement windows on **this one machine**. They don't represent every T440s, and this is not a one-click tutorial.
>
> Public, de-identified version: no usernames, hostnames, serial numbers, disk UUIDs, MAC addresses, network names, proxy subscriptions, device keys or private paths. Hardware models, software versions and PCI bus positions are non-unique information kept because they're needed to reproduce the setup.

## 1. How old is this machine, exactly?

Meet a ThinkPad T440s. Over ten years old. Spec sheet that would get laughed out of a 2026 product review:

| Component | This machine |
|---|---|
| CPU | Intel Core i5-4200U, Haswell, 2C/4T, nominal base 1.6 GHz, max single-core turbo 2.6 GHz |
| iGPU | Intel HD Graphics 4400, i915 driver, dynamic frequency ~200–1000 MHz |
| dGPU | NVIDIA dGPU variant; already in iGPU-only mode via EnvyControl at baseline |
| RAM | ~12 GB, ~11.6 GiB usable |
| Storage | Old 240 GB Kingston SATA SSD, shown as ~223.6 GiB. Not NVMe. |
| Battery | Internal + external dual battery; ~46.4 Wh combined design capacity, reporting ~27.8–28.8 Wh full charge during tuning — about 60% of design |
| OS | CachyOS, KDE Plasma, Wayland; Btrfs, Snapper and zram already in place |
| Cooling | Fan and thermal paste were serviced *before* this round. Not a result of the software tuning. |

No HWP/Speed Shift. No `platform_profile` interface for letting the desktop power profile drive firmware thermal policy. The old iGPU can't hardware-decode AV1, VP9 or HEVC.

But "old" doesn't mean "text editor only". After tuning, desktop, browser, dev tools and AI clients run well enough that it remains a working machine.

"Using AI" here means cloud models, AI coding tools and client workflows. There is no evidence this dual-core machine can run large local models smoothly, and no local LLM throughput test was done. **Inference that happens in the cloud does not count as the laptop's local compute.**

## 2. The goal was never "enable every power-saving knob"

I wasn't collecting green checkmarks. The requirements were explicit:

- **On AC:** performance first, boost when needed — but the fan should go quiet when idle.
- **On battery:** automatically switch to Balanced, keep turbo, don't make everyday use sluggish.
- **Leftmost Power-saver:** chosen manually, an explicit trade of performance for more conservative behaviour.
- **Wi-Fi stability first.** Don't let the Mesh network drop just to save a little power.
- **Brightness, screen-off and sleep are mine to decide.** Not used to "game" power numbers this round.
- **Back up first.** After each trial, know what actually took effect, and be able to go back.

CachyOS ships an optimized kernel and builds, but that doesn't mean it's already optimal for every old Wi-Fi card, every battery and every usage pattern. Equally, it doesn't mean you should pile on a bunch of "optimization packages".

## 3. Baseline: what I assumed ≠ what was running

I assumed the default power manager was TLP. It was actually **PPD (power-profiles-daemon)**. First of many "I was sure, and I was wrong" moments.

Other facts established up front:

- CPU: `intel_pstate` in passive mode, sysfs driver `intel_cpufreq`, governor `schedutil`.
- CPU range 800 MHz–2.6 GHz, turbo on.
- SCX was **installed**, but `scx_loader` was **not running** and `sched_ext` was **not enabled**. (Installed ≠ running. Write that on a sticky note.)
- SATA link biased to max performance; Wi-Fi power save was originally off.
- dGPU already in iGPU mode at baseline; its upstream PCIe bridge reported D3cold.
- PowerTOP was installed during the investigation as a measurement tool. No full-device `--auto-tune`, and no calibration run that would change test conditions such as the screen.

Backup meant more than "copy a config file": original files, service states, key runtime parameters, measurement logs, a change log and rollback entry points — later also SHA-256 checks to detect whether updates had modified files.

> **Lesson #1: a package being installed doesn't mean it's running. A value in a config file doesn't mean the kernel is using it.**

## 4. Phase 1: PPD + SCX — split performance from battery

The first approach didn't jump to TLP. It kept CachyOS's PPD and used its then-built-in SCX mode linkage:

| Situation | PPD profile | SCX mode at the time |
|---|---|---|
| AC | Performance | Gaming |
| Battery | Balanced | Auto |

LAVD was tried first, then replaced with Bpfland. Bpfland's Auto and Gaming modes both used a 5 ms time slice at the time. "Gaming" is just the scheduler mode's name — the machine wasn't gaming. (Naming things remains hard.)

Fixed-size SHA-256 short-task comparison:

| Scheduling setup | Single thread, 1 GiB | Two threads, 1 GiB each |
|---|---:|---:|
| Default kernel scheduler | 3.545 s | 4.141 s |
| LAVD Auto | 3.816 s | 4.346 s |
| Bpfland Auto, 5 ms | 3.550 s | 4.297 s |

LAVD was slower on these short compute tasks, so it didn't stay. Bpfland was near-default single-threaded, with about 3.8% more time dual-threaded. This only describes this task set; it doesn't prove any scheduler is best for every application.

Later, with real plug/unplug, another short-task set:

| Task | AC | Battery |
|---|---:|---:|
| Single thread | 3.564 s | 3.604 s |
| Two threads | 4.221 s | 4.362 s |

Battery took only ~1.1% and ~3.3% longer. For me that matched the original goal far better than "cut turbo the moment you unplug". But nobody was using the machine during these runs, so they must not be dressed up as interactive-smoothness measurements.

Alongside this, a short-lived service plus event-triggered rules switched SATA policy by power source. Not a resident daemon polling the system.

## 5. A very real trap: Wi-Fi power save vs. Mesh

Tried: Wi-Fi power save off on AC, on on battery. Short pings looked fine. Later came the tray exclamation mark and no connectivity. Classic "works in the lab, dies in the living room".

Logs showed AP roaming and missed beacons — and there were also proxy TUN and DNS factors. Connectivity was still broken with the proxy off, so you can't conclude "definitely the Wi-Fi card" from that alone — and you equally can't conclude "definitely the proxy" from an exclamation mark.

The final call was pragmatic: **Wi-Fi power save off on both power sources.** Stability first. Saving milliwatts is not worth a Mesh that ghosts you mid-meeting.

That decision survived the move to TLP:

```ini
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=off
```

The Wi-Fi card was also put on TLP's PCI runtime PM denylist, so TLP leaves its existing runtime power policy alone. "Excluded" does **not** mean "forced always-on".

I can't claim it was rigorously proven that every earlier drop was caused by power save, nor that long-term drops are now lab-proven cured. The real lesson: **ten pings with no loss do not prove Mesh roaming and long-session stability.**

## 6. Fan screaming: the load was the terminal I was looking at

For a while, CPU temperature looked fine but the fan kept spinning. Closing the browser didn't make it feel quieter. Naturally I blamed the power profile. Naturally I was looking in the wrong place.

Instead of touching the fan curve, first confirm:

- The fan is under EC firmware automatic control.
- No thinkfan, fancontrol or other manual fan service is running.
- No evidence Linux had locked the fan at max.
- "Window closed" ≠ "process exited". Chat apps, system monitors and terminal redraws can all keep running.

Measurements at the time:

| State | Observation |
|---|---|
| Browser closed, chat apps etc. still running | Whole-system CPU ~10–13%, CPU package ~6.4–7.1 W, ~50–53 °C, fan ~4000 RPM |
| Chat app and system monitor also closed | CPU ~6%, package ~4.9–5.2 W, ~46–48 °C, fan still lagging |
| Terminal minimized | Terminal, compositor and AI terminal still active — minimized ≠ not rendering |
| Terminal UI briefly paused, with a guaranteed-resume safeguard | Whole-system CPU down to ~0.3–0.7%, ~42–44 °C, fan ~3830 → 3070 → 2670 RPM |

In that last test, Performance/Gaming stayed selected, no task in the terminal was killed, and the UI was resumed afterwards. It shows the firmware's automatic ramp-down works, and that continuous display redraws were a major source of load at the time.

This is **not** a recommendation to pause your terminal, and certainly not to kill your current session. The experiment had a safeguard guaranteeing resume. The everyday fix is to cut unnecessary background programs and constant redraws.

### Two wrong calls, corrected

**1. `pwm1=255` does not necessarily mean full fan speed.**

On this ThinkPad in automatic mode, the driver's reading may come from a saved desired level rather than a direct measurement of the actual PWM. Judge by EC auto mode, actual RPM and load changes together. Treating it as proof of full speed was wrong; reading the driver source corrected it. The number looked decisive. The source code disagreed.

**2. Multiple AI CLI processes aren't necessarily duplicates or upgrade leftovers.**

I once assumed the AI CLI in the terminal was a redundant copy. On closer inspection it *was* the front end of the current conversation, and the other processes were its backend. Seeing several processes is no reason to have the user kill the session they're working in. (Almost did. Glad I didn't.)

Also: 4000 RPM only proves the fan was fast. That number alone doesn't establish the hardware's absolute maximum.

## 7. Phase 2: switch to BORE, don't stack schedulers

Next I wanted to try BORE. CachyOS's BORE kernel and headers were installed side by side, with the regular kernel and LTS kept as fallbacks. "Try the new thing" and "keep a way home" are not opposites.

These things live in different layers — and people keep calling all of them "the scheduler":

- **BORE** — a task scheduler inside the kernel.
- **Bpfland** — takes over task scheduling via sched_ext.
- **`performance` / `schedutil` / `conservative`** — CPU frequency governors; they pick frequencies.
- **TLP / PPD** — userspace power policy tools.

Same nickname. Four different jobs. Stacking them is how you invent bugs that nobody can reproduce.

Added to the BORE-only boot entry ([`configs/kernel-cmdline.md`](configs/kernel-cmdline.md)):

```text
systemd.mask=scx_loader.service
```

Purpose: on this boot path Bpfland no longer takes over, so BORE is what actually gets tested. The existing boot disk, root, subvolume and other parameters stay. Never paste someone else's entire kernel command line over yours.

After reboot:

```text
kernel.sched_bore = 1
sched_ext state = disabled
scx_loader = inactive / masked-runtime
```

BORE is what stayed. No sufficiently rigorous full-workload BORE vs. Bpfland comparison was done, so "it stayed" is largely based on feel. It doesn't prove BORE is faster or more power-efficient in every scenario. Feel is data; it just isn't *benchmark* data.

If you go back to the regular kernel and re-enable SCX, re-check the wiring. Don't assume CachyOS's original PPD → SCX linkage still exists after migrating to TLP.

## 8. Phase 3: three CPU tiers

The idea was simple: responsive on AC, still pleasant on battery, and only the leftmost slot is truly conservative.

Final targets:

| Item | Performance (auto on AC) | Balanced (auto on battery) | Power-saver (manual) |
|---|---|---|---|
| CPU governor | performance | schedutil | conservative |
| CPU allowed range | 800–2600 MHz | 800–2600 MHz | 800–1500 MHz |
| Turbo | allowed | allowed | off |
| CPU EPB | performance / 0 | balance_power / 8 | power / 15 |
| iGPU range | 200–1000 MHz | 200–1000 MHz | 200–400 MHz |
| SATA link | max_performance | med_power_with_dipm | med_power_with_dipm |
| SSD/port runtime PM | auto | auto | auto |
| PCI runtime PM | auto, denylist kept | same | same |
| Wi-Fi power save | off | off | off |
| Fan | EC auto | EC auto | EC auto |

Frequency ranges are *allowed bounds*, not real-time frequency promises. 2.6 GHz is max single-core turbo, not something all cores sustain under any load. The `performance` governor doesn't mean the CPU is always busy, let alone that the fan must always spin — CPU idle states and firmware thermal control are still there.

### Why the saver cap is 1.5 GHz, not the 1.6 GHz I asked for

The original plan: turbo off, 800 MHz floor, 1.6 GHz ceiling. The kernel clamped the ceiling to **1.5 GHz**. Spec sheet said 1.6. Silicon + firmware said otherwise. Spec sheets lie politely.

A **read-only** check of the relevant MSR information showed this machine's turbo activation ratio corresponds to a 15× multiplier. With turbo off, the non-turbo ceiling the kernel actually uses is ~1.5 GHz. Nominal base frequency and the real limit under this firmware/driver combination are not simply the same thing.

The first verification failed because it expected exactly 1.6 GHz, and the install logic rolled back automatically. Once the cause was found, the check was fixed and retried, and the genuinely effective 800–1500 MHz was kept. **No MSR writes or limit bypasses were used to force 1.6 GHz.** Accepting reality is faster than fighting the silicon.

> Note: the helper script ([`configs/cpu-helper/cachyos-cpu-governor`](configs/cpu-helper/cachyos-cpu-governor)) still writes `1600000` to `scaling_max_freq`; the kernel clamps it to 1.5 GHz as described above. The code is published unchanged.

Conservative governor tunables for saver:

```text
up_threshold = 90
down_threshold = 70
freq_step = 5
sampling_rate = 100000 us
sampling_down_factor = 1
```

Entering saver, the min/max are briefly narrowed to 800 MHz, then opened up to the saver ceiling; leaving it restores turbo and the full hardware frequency bounds. `freq_step=5` is a **percentage**, not 5 MHz per step.

## 9. Phase 4: PPD → TLP + tlp-pd

Back on Linux Mint + TLP I'd seen idle estimates of six to seven hours remaining, so I wanted to compare TLP. Nostalgia is not a measurement method — but it is a good reason to run one.

It turns out TLP 1.9+ ships `tlp-pd`, which can take over the desktop's three-profile interface. Using TLP doesn't mean giving up KDE's power menu.

TLP 1.10.2 was adopted — but without letting it fight every old script for control:

| Managed thing | Single final owner |
|---|---|
| Picking the profile on plug/unplug | TLP |
| Desktop three-profile interface | tlp-pd |
| CPU governor, turbo, frequency bounds | custom CPU helper service |
| EPB, iGPU limits, SATA, PCI/USB and other device policy | TLP |
| Battery info and desktop power features | UPower, KDE PowerDevil |
| Fan | firmware EC |

One owner per knob. Two tools writing the same sysfs file is how you get a laptop that disagrees with itself every five minutes.

To avoid double-writes, every TLP CPU governor / frequency / turbo entry that overlaps with the helper is set to an empty string (excerpt from [`configs/tlp/90-cachyos-t440s.conf`](configs/tlp/90-cachyos-t440s.conf)):

```ini
CPU_BOOST_ON_AC=""
CPU_BOOST_ON_BAT=""
CPU_BOOST_ON_SAV=""
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
CPU_ENERGY_PERF_POLICY_ON_SAV=power
```

The custom service's dependency was also switched from the old PPD to `tlp-pd.service`.

KDE's own "auto-set power profile" values were removed, but brightness, screen-off and sleep settings were not casually reset along the way.

The config uses `TLP_AUTO_SWITCH=1`: AC → Performance, battery → Balanced automatically. A manual Saver choice reverts to the automatic profile on the next power-source change or power-source initialization. Real reboot logs confirmed that booting on battery enters Balanced first, and the manual saver switch only happens afterwards.

The leftmost slot isn't a native fourth "ultra power saver" tier — it's Power-saver, customized to be more conservative. The implementation reads `ActiveProfile`; it can't tell whether a human clicked it. If other software selects power-saver, the same limits apply.

## 10. Device power management: kept vs. not adopted

### Kept

- SATA `max_performance` on AC, `med_power_with_dipm` on battery.
- AHCI/SSD runtime PM `auto` on both, original 15 s timeout kept.
- PCI runtime PM allowed to autosuspend, with the compatibility denylist kept.
- dGPU upstream bridge kept eligible for autosuspend.
- USB autosuspend using TLP defaults and the corresponding exclusion rules.
- Built-in audio idle power save kept at 10 s, controller power save on.
- Bluetooth off at boot but can be turned on manually — verified across a real reboot.
- Both batteries still charge to 100%. No 80% cap for longevity.

### Not adopted

- No forced PCIe ASPM `powersupersave`; stays `default`.
- No most-aggressive SATA `min_power`.
- iGPU not locked at 200 MHz; only Saver uses the 200–400 MHz dynamic range.
- No longer dirty-page writeback window to buy paper savings.
- No fiddling with SSD APM, Wake-on-LAN, or the autosuspend exceptions of every USB device.
- No second CPU power controller such as auto-cpufreq or tuned.
- No changes to CPU PL1/PL2 power limits, no undervolting, no RCU Lazy, no manual fan curve.

`auto` means a device may suspend when idle — not that it's unconditionally cut while in use. "Performance on AC" doesn't mean every idle device must stay on. Restraint is also a form of tuning.

### Two things that are easy to install by mistake

- **`tlp-rdw`** toggles radios on LAN/Wi-Fi/dock events. Bluetooth-off-at-boot doesn't need it; it wasn't installed.
- **`tp-smapi`** is a battery driver for older ThinkPads. On a T440s with a modern kernel, `thinkpad_acpi`'s native interface does the job — don't follow old tutorials and add it.

## 11. Display: PSR on doesn't mean DRRS can be

The display driver was checked specifically. Capability flags are not invitations:

| Tech | What it does | Result on this machine |
|---|---|---|
| PSR | Panel self-refreshes when the image is static, reducing display-link and memory work | Driver reports PSR1 enabled; parameter in auto mode |
| DRRS | Switches between high and low refresh rate by screen activity | No usable low-refresh timing available; not forced on |
| VRR | Variable refresh rate | Current display interface reports not supported |

The driver's `DRRS capable: yes` refers to the display controller's capability; it doesn't mean the current panel offers a usable downclock mode. The panel exposed only one native 1080p ~60 Hz detailed timing. An old module parameter from the internet can't conjure low-refresh support out of thin air.

PSR enabled also doesn't mean every sample is in the deepest residency. Diagnostics once read a PSR sink error flag; a single read can't tell whether it's historical, let alone declare a persistent screen fault. Driver defaults were kept — no forced flag clearing, EDID edits, custom timing injection or PSR parameter changes.

## 12. What the old iGPU is actually good at: H.264

Not "turn every browser graphics flag green", but confirm what the old hardware is good at. Haswell has opinions about codecs. Respect them.

- i915/Mesa hardware rendering works — not a CPU software renderer carrying the load.
- Haswell's VA-API driver is the legacy **i965**; the installed package was `libva-intel-driver-irql`.
- `vainfo` loads i965 correctly and lists H.264, MPEG-2, VC-1, JPEG, etc.
- No HEVC, VP9 or AV1 hardware decode. Browser flags can't summon hardware units that don't exist.

A 2-second, 1280×720, 30 fps H.264 test clip was generated:

| Test | Result |
|---|---|
| FFmpeg `h264_vaapi` encode | success |
| FFmpeg VA-API decode | 60 frames, 0 errors, hardware frame format vaapi |
| MPV with explicit `hwdec=auto` | used vaapi-copy successfully |
| Chrome status page (provided by me) | Video Decode hardware accelerated; H.264 Baseline/Main/High supported |

<!-- TODO (optional): add a real screenshot of your own `vainfo` output or Chrome's GPU status page. Do not fabricate one. -->

Chrome also reported hardware acceleration for Canvas, Compositing, Rasterization, WebGL, etc. Chrome's Video Encode was still software at the time, but system FFmpeg did complete H.264 hardware encode — so "this machine has no hardware encoding" would be wrong.

An app-defaults trap: standalone MPV's defaults aren't necessarily the same as an MPV-based player's. Standalone MPV didn't enable hwdec by default at the time; the corresponding version of Haruna (the default GUI player) defaults to auto — but it wasn't directly verified that every GUI playback actually hardware-decoded.

**A browser saying Video Decode is available proves the pipeline is capable — not that every video you watch uses it.** If a site serves AV1/VP9, the old iGPU may still hand it to the CPU. Vulkan and other pro features showing Disabled doesn't mean the desktop or H.264 decode is broken.

This round was mostly inspection and verification: no bulk browser flag changes, and no claim that every app now uses hardware decode automatically.

## 13. What the impressive-looking numbers actually prove

Pretty numbers are where honesty gets expensive. Here's what they actually bought.

### 13.1 The fan can stop even in Performance

During real on-AC verification, the machine was seen in Performance, turbo allowed, fan at **0 RPM**. So the goal isn't logically contradictory: allowing high performance doesn't require being hot and loud at idle.

But one 0 RPM reading doesn't guarantee it will stop in every environment. Room temperature, hidden sensors, background activity and firmware ramp-down delay all matter.

### 13.2 Idle cores ≠ deep package power saving

In early PowerTOP windows, core CC7 residency was already high, yet the package mostly sat in PC2; PC3 and deeper weren't observed. A later window, after a device-policy change, showed about 26% PC7 residency.

Lesson: look at core C-states, package C-states, device runtime PM and wakeup sources together. This doesn't prove a single device change produced all the gain, and you can't compute a reliable percentage across different measurement windows.

### 13.3 TLP did not produce a battery miracle in short tests

Short-window record from 2026-10-27:

| Setup | Avg whole-system discharge (full window) | Last minute | Whole-system CPU busy |
|---|---:|---:|---:|
| PPD + custom policy at the time | 7.89 W | 7.62 W | 7.04% |
| TLP Balanced | 7.62 W | 7.45 W | 7.04% |
| TLP Saver, separate run | 7.67 W | 7.48 W | 11.85% |

<!-- TODO (optional): if you add a chart, plot ONLY these exact numbers from the table above, and label it "single ~2-minute sequential windows, not statistically significant". -->

PPD → TLP lowered the mean by only ~0.27 W, about 3.4%. Each setup had a single ~2-minute sequential sample — no randomized alternation, no repeated runs. **No claim of a stable gain or statistical significance can be made.** If you came here for a "TLP doubles battery" headline, this is the part where I ruin it on purpose.

During the Saver run, the machine also switched from the external battery to the internal one. Power back-calculated from remaining-energy change didn't fully match the mean of the batteries' instantaneous power either; short windows and metering granularity cause differences.

Higher CPU busy share can't be read directly as "background got heavier": at lower frequency, the same work can take more CPU time. And picking the saver profile doesn't mean it will beat Balanced on power under every load.

Earlier desktop-activity windows of ~9–12 W were also seen, but with different programs, terminals, network and diagnostic conditions. So this write-up will **not** invent an overall improvement by computing "early 12 W minus later 7 W".

### 13.4 These power numbers are not the same kind of number

- On battery, the sum of both batteries' `power_now` can serve as an estimate of whole-system discharge.
- RAPL is CPU **package** energy, not whole-system.
- On AC, the few watts the battery shows may be **charging** power — not whole-system draw on AC.
- PowerTOP's per-process/per-device attribution is an estimate, not a power meter on every device.
- The tray's "six or seven hours remaining" is an extrapolation from remaining charge and recent draw. It can't be used to compare two systems.

I've seen Mint + TLP estimate six or seven hours, but this round did not measure six or seven continuous hours of runtime. The old batteries sit at about 60% capacity, which caps runtime by itself. Software can't turn chemical aging back into a new battery.

## 14. Conflict cleanup, reboot and update verification

Migration isn't a single `pacman -S`. Old control logic has a habit of coming back as a zombie. Explicitly checked and cleaned up:

- The old PPD package, binaries, CLI and systemd services were removed.
- The old SATA/Wi-Fi helper scripts, units, udev rules and NetworkManager dispatcher were archived and moved out.
- PPD's old state files were moved into the backup too.
- The CPU helper service stayed, but its dependency now points to tlp-pd.
- cpupower and PowerTOP the tools can stay; their auto-tune services and jobs are not running.
- UPower and KDE PowerDevil stay. Don't delete things just because "power" is in the name.

Two things that easily cause misdiagnosis:

1. Querying the old package name may return tlp-pd, which provides the compatible capability. That doesn't mean the old PPD is back.
2. `org.freedesktop.UPower.PowerProfiles` and `net.hadess.PowerProfiles` are two compatible D-Bus names that can be served by the same tlp-pd process. Not two power managers.

After a real reboot, logs confirmed: auto profile selection, the CPU helper and TLP all fine; Bluetooth really off at boot; iGPU Saver limits restorable; old services did not come back.

After a system update on 2026-10-29, a read-only re-check: all 6 retained tracked config files matched their checksums, TLP package integrity check showed no modifications, services healthy, no abnormal restarts, 0 failed system and user units.

While compiling this write-up on 2026-11-03, another read-only check: all 6 files still matched; TLP, tlp-pd and the CPU helper all running; versions still TLP/tlp-pd 1.10.2 and BORE 7.3.0-2. This check was **not** a new power or all-profile benchmark.

## 15. The reproducible part

What follows is my actual setup. Three preconditions first — ignore them and you'll reproduce someone else's bugs:

1. It targets this **Haswell + `intel_cpufreq` + Intel i915** machine. Don't apply it directly to AMD or newer Intel.
2. The CPU entries in the TLP config are **intentionally empty** because the helper service owns them. Copying only the TLP part will *not* give you the three-tier CPU behaviour described here.
3. **PCI addresses are device topology positions, not serial numbers, and they may differ on your machine.** Confirm your Wi-Fi card and dGPU upstream bridge with `lspci` first — don't copy them blindly.

This is a configuration record for reading, splitting up and auditing. It was not designed as a one-click root install script. Package conflicts, launchers and the backup scheme of the original system each need to be checked separately.

All files, with install locations, are in [`configs/`](configs/) — see [`configs/README.md`](configs/README.md).

### 15.1 TLP config → [`configs/tlp/90-cachyos-t440s.conf`](configs/tlp/90-cachyos-t440s.conf)

Install to `/etc/tlp.d/90-cachyos-t440s.conf`. TLP handles CPU EPB and device management; the rest of CPU frequency policy is handled by the helper in the next section.

The PCI part — **check these addresses against your own `lspci`** (`00:1c.4` = NVIDIA upstream bridge, `03:00.0` = Wi-Fi card on *this* machine):

```ini
# Keep the NVIDIA upstream bridge eligible for suspend on either power source.
RUNTIME_PM_ON_AC=auto
RUNTIME_PM_ON_BAT=auto
RUNTIME_PM_ENABLE="00:1c.4"
# Preserve Wi-Fi PCI runtime policy too, given prior connectivity problems.
RUNTIME_PM_DENYLIST="03:00.0"
WOL_DISABLE=""
```

### 15.2 CPU helper → [`configs/cpu-helper/cachyos-cpu-governor`](configs/cpu-helper/cachyos-cpu-governor)

Install to `/usr/local/libexec/cachyos-cpu-governor`. Requires system Python and PyGObject (`python-gobject` on Arch/CachyOS). The compatibility interface name in the script still contains "PowerProfiles"; that does not mean it depends on the old PPD.

It listens on D-Bus for power-profile, power-source and resume events, re-checks after a short delay following each event, and does **not** poll on a fixed interval. The published file is the actual de-identified script. The whole policy decision is one line:

```python
 ac=ac_online();governor='conservative' if profile=='power-saver' else ('performance' if ac and profile=='performance' else 'schedutil')
```

### 15.3 systemd unit → [`configs/systemd/cachyos-cpu-governor.service`](configs/systemd/cachyos-cpu-governor.service)

Install to `/etc/systemd/system/cachyos-cpu-governor.service`. The script needs to be executable and the unit root-owned. Review the code and environment before reproducing — **don't let a user-writable script be executed by a root service.**

```ini
[Unit]
Description=CPU governor following power profile and AC power
Wants=tlp-pd.service upower.service
After=tlp-pd.service upower.service

[Service]
Type=simple
ExecStart=/usr/local/libexec/cachyos-cpu-governor
ExecStopPost=/usr/local/libexec/cachyos-cpu-governor --restore
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
RestrictAddressFamilies=AF_UNIX
ReadWritePaths=/sys/devices/system/cpu

[Install]
WantedBy=graphical.target
```

Once the files and dependencies are installed, these persist the services:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tlp.service tlp-pd.service
sudo systemctl enable --now cachyos-cpu-governor.service
```

These lines only enable existing services. They don't handle removing the old PPD, installing the CPU helper, package conflicts, KDE auto profile switching or the BORE boot entry. **They are not a complete migration.**

### 15.4 Read back the live state, not just the config files → [`scripts/readback.sh`](scripts/readback.sh)

Read-only commands used for re-checks. Device names, interface names and debugfs locations may differ by machine or kernel — `wlan0` is this machine's Wi-Fi interface; **find yours with `ip link`**.

```bash
tlpctl get
systemctl status tlp tlp-pd cachyos-cpu-governor
systemctl --failed
systemctl --user --failed
cat /sys/devices/system/cpu/intel_pstate/status
cat /sys/devices/system/cpu/intel_pstate/no_turbo
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_min_freq
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq
cat /sys/class/drm/card*/gt_min_freq_mhz
cat /sys/class/drm/card*/gt_max_freq_mhz
cat /sys/class/drm/card*/gt_boost_freq_mhz
rfkill list bluetooth
iw dev wlan0 get power_save
sudo tlp-stat -s -p -g -d -e -u
```

`sudo tlp-stat` is a diagnostic read. Don't lump it together with `tlp start`, editing config, or `powertop --auto-tune`.

<!-- TODO (optional): add a real, de-identified screenshot of `tlpctl get` + `tlp-stat` output from your machine. Check it for hostnames/serials first. -->

## 16. Backup and rollback are part of the design

Locally I keep each phase's original configs, state data and versioned rollback entry points, but those raw directories are not published as-is: they may contain private paths and device information.

Rollback runs in reverse dependency order:

1. Restore the old files that were archived and moved out.
2. Undo the iGPU frequency limits, AHCI and Bluetooth adjustments; restore the original frequency bounds.
3. Undo the TLP migration; restore the previous PPD package, config and service relationships.
4. If needed, boot the retained regular kernel or LTS and deal with the BORE/SCX choice separately.

You can't just remove TLP and declare rollback done: iGPU caps already written to sysfs may still be in place. Rollback has to restore runtime values, service dependencies, event-trigger entry points and the file checksum manifest.

The full rollback entry points were syntax-checked and include automatic recovery if install verification fails. A full rollback was **not** executed on the final, working system just to show it's possible. The public version contains no installer or rollback script that depends on my private backup directory, and nobody should run those directly anyway.

## 17. What I believed vs. what was true

The highlight reel of being wrong. Keep it handy.

| What was easy to believe | What turned out to be true |
|---|---|
| CachyOS is optimized, so device power saving needs no attention | You still have to read the actual drivers, device states and load |
| SCX is installed, so SCX is in use | Check the running loader and `sched_ext` state |
| BORE, Bpfland and schedutil are the same kind of scheduler | They sit in the task-scheduling, sched_ext and CPU-frequency layers respectively |
| Performance means the fan should always spin | 0 RPM in Performance was observed; firmware auto control and background load matter more |
| Low temp but spinning fan = broken config | Also check sustained load, EC delay, hidden sensors and actual RPM |
| `pwm1=255` in auto mode = full speed | Source code confirms it can't be read that way |
| Browser closed = idle | Chat apps, monitors, terminal and compositor are still active |
| Multiple AI CLI processes = upgrade leftovers | May be the normal front end/back end of the current session — don't kill them |
| Wi-Fi power save passes a short test, so it's fine long-term | Mesh roaming and long-session stability need separate testing |
| The offline exclamation mark tells you proxy vs. Wi-Fi card | Check layer by layer: association, gateway, DNS, TUN, routing |
| CPU is rated 1.6 GHz, so turbo-off can be capped at 1.6 GHz | This machine's real ceiling clamps to 1.5 GHz — read it back |
| The leftmost saver slot always uses the least power | Lower clocks also stretch task time; measure actual power |
| Two PowerProfiles D-Bus names = two PPDs | Can be compatible interfaces of the same tlp-pd |
| Switching to TLP means losing KDE's three-profile menu | Recent tlp-pd provides the interface the desktop uses |
| Uninstalling PPD alone avoids conflicts | Old scripts, udev rules, dispatchers and boot jobs need cleanup too |
| `DRRS capable` means dynamic refresh downclocking can be enabled | Display controller capability ≠ panel has a low-refresh timing |
| Browser says HW decode is available, so all video is HW-decoded | Depends on the codec and the actual decoder |
| i965 is old, so force iHD | Haswell should use the appropriate legacy driver; don't pick by "newer" |
| RAPL watts = whole-system power | CPU package and whole-system discharge are different measurements |
| "Six or seven hours remaining" proves one system saves more power | Look at remaining Wh, recent load and discharge W together |
| A wall of PCI/USB `auto` = everything is powered off | It only *allows* suspend; check `runtime_status` etc. |
| dGPU upstream bridge in D3cold proves the dGPU rail is strictly 0 W | It supports a low-power-state judgment; it's not an electrical power measurement |

## 18. Lessons

What makes me happy with this T440s is that old hardware finally works the way I need: performance on AC, no obvious sluggishness on battery, and a more conservative tier on demand. Hardware decode, background load, device suspend, firmware fan control and policy conflicts were each looked at clearly, one by one.

No single test proved it suddenly became a new computer, and no single switch doubled battery life. What actually worked: **measure first, stack fewer tools, change one well-understood layer at a time, read back the real values, save the results, and correct yourself when you're wrong.**

For me, that's the part of this "geek tuning" most worth sharing. The machine didn't get younger. My assumptions did get thinner — and that turned out to be the useful part.

## References

Official docs, source code and projects consulted while debugging. Software behaviour changes between versions; check against your installed versions when reproducing.

- [CachyOS Kernel](https://wiki.cachyos.org/features/kernel/)
- [CachyOS sched-ext configuration](https://wiki.cachyos.org/configuration/sched-ext/)
- [TLP project](https://github.com/linrunner/TLP)
- [TLP and PPD](https://linrunner.de/tlp/faq/ppd.html)
- [TLP profiles and auto switching](https://linrunner.de/tlp/settings/operation.html)
- [TLP processor settings](https://linrunner.de/tlp/settings/processor.html)
- [TLP PCI runtime PM and ASPM](https://linrunner.de/tlp/settings/runtimepm.html)
- [TLP on Arch Linux, and notes on old ThinkPad drivers](https://linrunner.de/tlp/installation/arch.html)
- [Linux CPUFreq governors](https://docs.kernel.org/admin-guide/pm/cpufreq.html)
- [Linux intel_pstate](https://docs.kernel.org/admin-guide/pm/intel_pstate.html)
- [Linux DRRS documentation](https://docs.kernel.org/gpu/intel-display/drrs.html)
- [thinkpad_acpi fan control source](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/lenovo/thinkpad_acpi.c)
- [PowerTOP](https://github.com/fenrus75/powertop)
- [Chromium VA-API notes](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/docs/gpu/vaapi.md)
- [Haruna 1.8.1 playback defaults](https://github.com/KDE/haruna/blob/v1.8.1/src/settings/playbacksettings.kcfg)

## License

The article text is licensed under [CC BY 4.0](LICENSE-CC-BY-4.0.txt). The files in [`configs/`](configs/) and [`scripts/`](scripts/) are licensed under the [MIT License](LICENSE).

---

[Configs](configs/README.md) · [Read-only checks](scripts/readback.sh)
