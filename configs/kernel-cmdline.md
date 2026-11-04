# Kernel command line: BORE boot entry


Added to the **BORE-only boot entry** (not to the regular kernel or LTS entries, which stay as fallbacks):

```text
systemd.mask=scx_loader.service
```

**Why:** on this boot path, it stops `scx_loader` from bringing up the Bpfland sched_ext scheduler, so the BORE kernel's own scheduler is the one actually being tested.

**Do not** copy anyone's whole kernel command line over yours. Keep your own boot disk, `root=`, subvolume and other existing parameters; *append* this one parameter to the BORE entry only.

## Verify after reboot

What the article's machine read back:

```text
kernel.sched_bore = 1
sched_ext state = disabled
scx_loader = inactive / masked-runtime
```

## Caveats

- BORE was kept mainly on day-to-day feel. No rigorous full-workload BORE vs. Bpfland comparison was done, so this is not proof that BORE is faster or more power-efficient everywhere.
- If you go back to the regular kernel and re-enable SCX, re-check the wiring. After the move to TLP, do not assume CachyOS's old PPD → SCX profile linkage still exists.

---

