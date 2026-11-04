#!/usr/bin/env bash
# readback.sh -- READ-ONLY diagnostics. Changes nothing.
#
# The commands below are copied verbatim from the article (section 15.4).
# They only read state; none of them writes config or sysfs.
# Note: `sudo tlp-stat` is a diagnostic read -- not the same thing as
# `tlp start`, editing config, or `powertop --auto-tune`.
#
# Check the paths for YOUR machine before trusting the output:
#   - Wi-Fi interface name: `wlan0` here; find yours with `ip link` / `iw dev`.
#   - DRM card paths (card*), cpufreq policies and debugfs locations can
#     differ between machines and kernels.
#   - tlpctl / tlp-stat require TLP >= 1.9 with tlp-pd (tested: 1.10.2).

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
