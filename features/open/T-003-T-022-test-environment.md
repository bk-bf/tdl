<!-- LOC cap: 344 (source: 2457, ratio: 0.14, updated: 2026-03-09) -->
# T-003 / T-022 — Test Environment Setup

## Task tracker

**Branch:** `feature/cross-distro-install` (worktree: `aid/feature/cross-distro-install/`)
**Status as of 2026-03-10**

### Code changes

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | `_detect_distro()` in `install.sh` | ✅ done | Returns `arch\|debian\|fedora\|alpine\|opensuse\|macos\|unknown` |
| 2 | `_require <cmd>` helper | ✅ done | Hard-abort with distro-specific hint; lsof non-fatal on Alpine |
| 3 | `_ver_ge` semver helper | ✅ done | `sort -V` based; used for tmux and nvim version checks |
| 4 | Pre-flight checks (git, curl, tmux ≥3.2, node, lsof) | ✅ done | Hard-abort with actionable messages |
| 5 | nvim AppImage fallback for Debian/Ubuntu < 0.9 | ✅ done | Fetches latest stable tag from GitHub API; extracts if FUSE absent |
| 6 | pynvim distro-dispatch (apt/dnf/zypper/pip3) | ✅ done | Replaces Arch-only pacman block |
| 7 | delta distro-dispatch | ✅ done | apt (22.04+/Debian 12+ only), zypper, brew; skip-with-note on RHEL/old Debian |
| 8 | `watch_and_update.sh`: `_pane_cwd` — `/proc/` on Linux, `lsof` on macOS | ✅ done | Both cwd-detection call-sites replaced |
| 9 | `host-setup.sh` (KVM one-time host setup) | ✅ done | Arch-only; installs virt-manager/qemu/libvirt, adds user to groups |

> **Uncommitted.** All 3 modified/new files (`install.sh`, `nvim-treemux/watch_and_update.sh`, `host-setup.sh`) are unstaged on `feature/cross-distro-install`. Syntax-checked clean (`bash -n`).

### VM provisioning

| # | VM | ISO downloaded | VM created | Snapshot `clean` taken | `install.sh` tested |
|---|----|---------------|------------|----------------------|---------------------|
| 1 | `debian-11` | ✅ | ✅ | ✅ | [ ] |
| 2 | `debian-12` | ✅ | ✅ | [ ] | [ ] |
| 3 | `ubuntu-2404` | ✅ | ✅ | [ ] | [ ] |
| 4 | `ubuntu-2204` | ✅ | ✅ | [ ] | [ ] |
| 5 | `ubuntu-2004` | ✅ | ✅ | [ ] | [ ] |
| 6 | `fedora-42` | ✅ | ✅ | [ ] | [ ] |
| 7 | `rocky-9` | ✅ | ✅ | [ ] | [ ] |
| 8 | `opensuse-tw` | ✅ | ✅ | [ ] | [ ] |
| 9 | `alpine-319` | ✅ | ✅ | [ ] | [ ] |
| 10 | `arch` | ✅ | ✅ | [ ] | [ ] |

### Remaining work

- [ ] Complete unattended OS installs for VMs 2–9 (see blocker log below)
- [ ] Verify SSH access on all 9 remaining VMs
- [ ] Take `clean` snapshot on all 9 remaining VMs
- [ ] Run `install.sh` on each VM and record result
- [ ] Fix any failures found during VM testing
- [ ] Open PR: `feature/cross-distro-install` → `main`

---

## Unattended install attempt log (2026-03-10)

### What was working before this session

- `debian-11`: manually installed, SSH working on port 2201, `clean` snapshot taken. Used as the reference baseline.

### Approach 1: libvirt direct kernel boot via `virt-xml`

**Goal:** Set `<kernel>`, `<initrd>`, `<cmdline>` in each VM's libvirt XML so the installer kernel boots automatically on `virsh start`.

**Root cause of failure:** Libvirt unconditionally re-adds `<boot dev='hd'/>` (and/or `<boot dev='cdrom'/>`) into the `<os>` section whenever `virsh define` is called, regardless of whether the submitted XML contained those elements. This causes QEMU to receive `-boot strict=on`, which instructs it to only try the listed boot devices in order and ignore the `-kernel` flag entirely. The VM boots into SeaBIOS/iPXE instead of the installer kernel.

**Things tried that did not fix it:**

- `virt-xml --edit --boot kernel=...,initrd=...` — sets kernel/initrd but libvirt still adds `-boot strict=on`
- `sed`-based removal of `<boot dev=...>` lines from XML before `virsh define` — libvirt re-adds them on define
- Python `xml.etree` rewrite of XML with all `<boot>` elements removed before `virsh define` — libvirt re-adds them on define
- Adding per-device boot order (`<boot order='1'/>` inside the `<disk>` element) as an alternative — this changes boot order to use `bootindex` QEMU args, but libvirt still emits `-boot strict=on`

**Conclusion:** Libvirt's XML normalisation cannot be overridden via `virsh define` for this use case. This approach is a dead end.

### Approach 2: `virt-install --reinstall`

**Not pursued in detail.** Earlier research established that `virt-install --reinstall` extracts kernel/initrd to `~/.cache/aid/virt-manager/boot/` but those files are deleted by virt-install before QEMU launches — QEMU then falls back to SeaBIOS. Abandoned.

### Approach 3: Direct QEMU (bypassing libvirt)

**Goal:** Run `qemu-system-x86_64` directly with `-kernel`, `-initrd`, `-append`, and `-cdrom` args. After install completes, the VM disk is imported back into libvirt as a clean domain.

**Key insight:** `-boot strict=on` is a libvirt-injected arg and not present when QEMU is run directly. The `-kernel` flag works correctly.

**Confirmed working:** `debian-12` booted the Debian installer kernel, DHCP succeeded, preseed config was fetched from `http://10.0.2.2:8888/debian/preseed.cfg`, and ~7.4 GB of writes were observed as packages were installed. The serial log showed "Finishing the installation" before the session was aborted.

**Root cause of earlier "no writes" confusion:** The Debian installer requires the ISO to be present as a CDROM (for package retrieval) in addition to the direct kernel boot. First attempt omitted `-cdrom`; installer booted but failed at "Detect and mount installation media". Fixed by adding `-cdrom ~/iso/aid-test/debian-12.iso`.

**Results per distro at time of abort:**

| VM | Writes at abort | Serial log state | Notes |
|----|----------------|-----------------|-------|
| `debian-12` | ~7.4 GB | "Finishing the installation" | Nearly complete — was running `update-initramfs` |
| `ubuntu-2404` | ~3.2 GB | Active package install | In progress |
| `ubuntu-2004` | ~3.0 GB | Active package install | In progress |
| `ubuntu-2204` | ~1.1 GB | Active package install | In progress, slower |
| `fedora-42` | 0 (restarted) | systemd starting after fix | First attempt: TUI waited for input (kickstart not fetched in time). Fixed with `inst.noninteractive`. Second attempt was progressing at abort |
| `rocky-9` | 0 | Kernel panic every attempt | See blocker below |
| `opensuse-tw` | 0 | Unclear — TUI fragments in log | Not enough time to assess |
| `alpine-319` | not started | — | Skipped — needs different approach (see below) |
| `arch` | not started | — | Skipped per user decision |

### Rocky-9 blocker

**Symptom:** Kernel panic immediately after initrd runs — `Attempted to kill init! exitcode=0x00007f00`. Exit code 127 means a command was not found inside the dracut initrd's `init` script.

**Attempted fixes:**
- Added `inst.stage2=cdrom` — no change
- Changed disk from `virtio-blk` to `virtio-scsi-pci` + `scsi-hd` — no change
- Added `inst.noninteractive` — no change

**Suspected cause:** The Rocky 9 boot initrd (`/ISOLINUX/INITRD.IMG`) is a minimal Anaconda netboot initrd that expects a network stage2 image. When stage2 cannot be loaded (possibly because virtio_net is not in the initrd, or the stage2 URL is not reachable), the dracut emergency shell hits a missing binary. The `inst.stage2=cdrom` hint should cause it to load stage2 from the CDROM but may require a specific cdrom device name that doesn't match what QEMU presents.

**Not resolved.** Needs investigation: inspect the dracut initrd contents, verify virtio_net is present, or try `rd.break` to drop to a debug shell.

### Alpine-319 approach (not attempted)

Alpine's `setup-alpine` does not support a network-fetched answers file natively at boot — the live ISO boots to a root shell and the answers file must be explicitly passed to `setup-alpine -f`. The planned approach was:

1. Boot Alpine live ISO via direct QEMU
2. Pass `script=http://10.0.2.2:8888/alpine/setup.sh` as a kernel parameter (Alpine supports this via `alpine_dev` / `ovl_dev` but not `script=` natively)
3. Alternative: use `modloop=...` or pass a custom init overlay

The `~/vm/autoinstall/alpine/setup.sh` wrapper script is ready and would work once triggered inside the live env. The remaining problem is auto-triggering it at boot without manual intervention. A reliable approach would be to use `virt-customize` to inject a systemd-style `rc.local` equivalent into the Alpine live initrd — not attempted.

---

## Infrastructure state (as of 2026-03-10)

All assets are on the host at `kirill@cachyos-x8664`.

```
~/iso/aid-test/          — all 10 ISOs fully downloaded
~/vm/aid-test/           — 10 qcow2 disk images (most blank or partially written)
~/vm/kernels/            — extracted kernel+initrd for 8/9 distros (arch skipped)
~/vm/autoinstall/        — HTTP-served autoinstall configs (preseed, cloud-init, kickstart, autoyast, answers)
```

**HTTP server** (must be running before any install attempt):
```bash
python3 -m http.server 8888 --directory ~/vm/autoinstall/
```

**Port map:**

| VM | SSH port | Status |
|---|---|---|
| `debian-11` | 2201 | ✅ SSH works, `clean` snapshot taken |
| `debian-12` | 2202 | install ~90% done at abort; disk has partial install |
| `ubuntu-2404` | 2203 | install in progress at abort |
| `ubuntu-2204` | 2204 | install in progress at abort |
| `ubuntu-2004` | 2205 | install in progress at abort |
| `fedora-42` | 2206 | install starting at abort |
| `arch` | 2207 | not attempted |
| `alpine-319` | 2208 | not attempted |
| `rocky-9` | 2209 | blocked — kernel panic |
| `opensuse-tw` | 2210 | not assessed |

**Disks with partial installs** — must be zeroed before re-attempting:
```bash
# For each VM that had a partial install:
qemu-img create -f qcow2 -o preallocation=off ~/vm/aid-test/<vm>.qcow2 20G
```

---

## Recommended next steps

### To complete the installs (direct QEMU approach — confirmed working)

Run each install as a direct QEMU process. Confirmed command template (debian-12 as reference):

```bash
# Ensure HTTP server is running first:
ps aux | grep "http.server 8888" || python3 -m http.server 8888 --directory ~/vm/autoinstall/ &

qemu-system-x86_64 \
  -enable-kvm -machine pc-q35-10.2 -m 2048 \
  -drive file=~/vm/aid-test/debian-12.qcow2,format=qcow2,if=virtio \
  -cdrom ~/iso/aid-test/debian-12.iso \
  -kernel ~/vm/kernels/debian-12/vmlinuz \
  -initrd ~/vm/kernels/debian-12/initrd.gz \
  -append "auto=true priority=critical url=http://10.0.2.2:8888/debian/preseed.cfg console=ttyS0" \
  -netdev user,id=net0,hostfwd=tcp::2202-:22 \
  -device virtio-net-pci,netdev=net0 \
  -serial file:/tmp/debian-12-install.log \
  -display none -daemonize
```

Monitor with:
```bash
# Disk writes (non-zero = installer is active):
grep write_bytes /proc/$(pgrep -f "debian-12.qcow2")/io
# Serial console:
tail -f /tmp/debian-12-install.log | strings
```

**Per-distro commands:**

```bash
# ubuntu-2404 (port 2203)
qemu-system-x86_64 -enable-kvm -machine pc-q35-10.2 -m 2048 \
  -drive file=~/vm/aid-test/ubuntu-2404.qcow2,format=qcow2,if=virtio \
  -cdrom ~/iso/aid-test/ubuntu-2404.iso \
  -kernel ~/vm/kernels/ubuntu-2404/vmlinuz \
  -initrd ~/vm/kernels/ubuntu-2404/initrd \
  -append "autoinstall ds=nocloud-net;s=http://10.0.2.2:8888/ubuntu/ console=ttyS0 quiet" \
  -netdev user,id=net0,hostfwd=tcp::2203-:22 -device virtio-net-pci,netdev=net0 \
  -serial file:/tmp/ubuntu-2404-install.log -display none -daemonize

# ubuntu-2204 (port 2204) — same append args
qemu-system-x86_64 -enable-kvm -machine pc-q35-10.2 -m 2048 \
  -drive file=~/vm/aid-test/ubuntu-2204.qcow2,format=qcow2,if=virtio \
  -cdrom ~/iso/aid-test/ubuntu-2204.iso \
  -kernel ~/vm/kernels/ubuntu-2204/vmlinuz \
  -initrd ~/vm/kernels/ubuntu-2204/initrd \
  -append "autoinstall ds=nocloud-net;s=http://10.0.2.2:8888/ubuntu/ console=ttyS0 quiet" \
  -netdev user,id=net0,hostfwd=tcp::2204-:22 -device virtio-net-pci,netdev=net0 \
  -serial file:/tmp/ubuntu-2204-install.log -display none -daemonize

# ubuntu-2004 (port 2205)
qemu-system-x86_64 -enable-kvm -machine pc-q35-10.2 -m 2048 \
  -drive file=~/vm/aid-test/ubuntu-2004.qcow2,format=qcow2,if=virtio \
  -cdrom ~/iso/aid-test/ubuntu-2004.iso \
  -kernel ~/vm/kernels/ubuntu-2004/vmlinuz \
  -initrd ~/vm/kernels/ubuntu-2004/initrd \
  -append "autoinstall ds=nocloud-net;s=http://10.0.2.2:8888/ubuntu/ console=ttyS0 quiet" \
  -netdev user,id=net0,hostfwd=tcp::2205-:22 -device virtio-net-pci,netdev=net0 \
  -serial file:/tmp/ubuntu-2004-install.log -display none -daemonize

# fedora-42 (port 2206)
qemu-system-x86_64 -enable-kvm -machine pc-q35-10.2 -m 2048 \
  -drive file=~/vm/aid-test/fedora-42.qcow2,format=qcow2,if=virtio \
  -cdrom ~/iso/aid-test/fedora-42.iso \
  -kernel ~/vm/kernels/fedora-42/vmlinuz \
  -initrd ~/vm/kernels/fedora-42/initrd.img \
  -append "inst.ks=http://10.0.2.2:8888/fedora/kickstart.ks inst.noninteractive console=ttyS0 inst.text" \
  -netdev user,id=net0,hostfwd=tcp::2206-:22 -device virtio-net-pci,netdev=net0 \
  -serial file:/tmp/fedora-42-install.log -display none -daemonize

# opensuse-tw (port 2210)
qemu-system-x86_64 -enable-kvm -machine pc-q35-10.2 -m 2048 \
  -drive file=~/vm/aid-test/opensuse-tw.qcow2,format=qcow2,if=virtio \
  -cdrom ~/iso/aid-test/opensuse-tw.iso \
  -kernel ~/vm/kernels/opensuse-tw/linux \
  -initrd ~/vm/kernels/opensuse-tw/initrd \
  -append "autoyast=http://10.0.2.2:8888/opensuse/autoyast.xml console=ttyS0 textmode=1" \
  -netdev user,id=net0,hostfwd=tcp::2210-:22 -device virtio-net-pci,netdev=net0 \
  -serial file:/tmp/opensuse-tw-install.log -display none -daemonize
```

**RAM budget:** Each VM uses ~1–2 GB RAM. Host has 16 GB. Run max 4–5 in parallel; debian-11 (already running) uses ~0.3 GB.

### Rocky-9 — needs debugging

Before re-attempting, extract and inspect the dracut initrd to confirm virtio_net is present:
```bash
mkdir /tmp/rocky-initrd && cd /tmp/rocky-initrd
# The initrd is a concatenated microcode + cpio archive
# Skip the microcode prefix and extract the cpio portion:
skipcpio ~/vm/kernels/rocky-9/initrd.img | zstd -d | cpio -id 2>/dev/null
# Or with xz compression:
skipcpio ~/vm/kernels/rocky-9/initrd.img | xz -d | cpio -id 2>/dev/null
ls lib/modules/*/kernel/drivers/net/virtio_net.ko* 2>/dev/null || echo "virtio_net NOT in initrd"
```

If `virtio_net` is missing, the fix is to use `dracut --add-drivers virtio_net` to rebuild the initrd, or pass `rd.driver.pre=virtio_net` on the kernel command line. Alternatively, use an e1000 NIC instead of virtio-net for the install.

### Alpine-319 — needs a trigger mechanism

Option A (simplest): boot the live ISO via direct QEMU with no `-kernel` (let it boot from CDROM to the root shell), then SSH in and manually run:
```bash
wget -O /tmp/setup.sh http://10.0.2.2:8888/alpine/setup.sh && sh /tmp/setup.sh
```
Note: Alpine live ISO root has no password — SSH in as root on port 2208 immediately after boot.

Option B: inject a `/etc/local.d/autoinstall.start` script into the Alpine ISO using `xorriso` or into a custom initrd overlay, auto-triggering the install on first boot.

### After each install completes

1. The QEMU process exits on its own (installer calls `reboot`/`poweroff`)
2. Remove the kernel/initrd from the libvirt XML so the VM boots from disk:
   ```bash
   virsh --connect qemu:///session dumpxml <vm> > /tmp/<vm>.xml
   # Remove <kernel>, <initrd>, <cmdline> lines from <os> block
   virsh --connect qemu:///session define /tmp/<vm>.xml
   ```
3. Start VM via libvirt, SSH in, verify `tester` user + sudo works
4. Take snapshot: `virsh --connect qemu:///session snapshot-create-as <vm> clean`

---

## Background / design notes

KVM test environment for validating aid's cross-distro install support.

### Host setup (one time)

```bash
sudo pacman -S --needed virt-manager qemu-full libvirt dnsmasq
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm $USER
# re-login or: newgrp libvirt
virt-manager &
```

All VMs use `qemu:///session` (not system) — always pass `--connect qemu:///session` to virsh commands.

**Full dependency audit:**

| Dependency | Role | Arch | Ubuntu/Debian | Fedora/RHEL | macOS |
|------------|------|------|--------------|-------------|-------|
| `tmux ≥ 3.2` | core | `pacman -S tmux` | `apt install tmux` (≥3.2 on 22.04+) | `dnf install tmux` | `brew install tmux` |
| `nvim ≥ 0.9` | editor | `pacman -S neovim` | **blocker**: 24.04 ships 0.9.5 ✅; 22.04 ships 0.6 ❌ — needs AppImage | `dnf install neovim` (0.9+ on F38+) | `brew install neovim` |
| `python3-pynvim` | treemux cwd tracking | `pacman -S python-pynvim` | `apt install python3-neovim` or `pip3 install pynvim` | `pip3 install pynvim` | `pip3 install pynvim` |
| `lsof` | `watch_and_update.sh` cwd on macOS | pre-installed | `apt install lsof` (often missing on minimal) | pre-installed | pre-installed |
| `node` + `npm` | opencode runtime | `pacman -S nodejs npm` | `apt install nodejs npm` | `dnf install nodejs npm` | `brew install node` |
| `git` | repo clone, TPM, lazy.nvim | pre-installed | pre-installed | pre-installed | pre-installed |
| `curl` | `boot.sh` bootstrapper | pre-installed | pre-installed | pre-installed | pre-installed |

### VM matrix

| # | Name | ISO | RAM | Disk | What it tests |
|---|------|-----|-----|------|---------------|
| 1 | `ubuntu-2404` | Ubuntu 24.04 LTS server | 512 MB | 20 GB | nvim 0.9.5 in repo — apt happy path |
| 2 | `ubuntu-2204` | Ubuntu 22.04 LTS server | 512 MB | 20 GB | nvim 0.6 in repo — AppImage fallback |
| 3 | `debian-12` | Debian 12 netinst | 512 MB | 20 GB | Debian apt (no Ubuntu quirks) |
| 4 | `debian-11` | Debian 11 netinst | 512 MB | 20 GB | Older Debian, nvim 0.4 — AppImage |
| 5 | `fedora-42` | Fedora 42 Server | 512 MB | 20 GB | dnf family, nvim 0.9+ in repo |
| 6 | `arch` | Arch Linux | 512 MB | 20 GB | pacman baseline (home distro) — skipped for now |
| 7 | `alpine-319` | Alpine 3.19 virtual | 256 MB | 20 GB | No `lsof` — `/proc/` fallback path |
| 8 | `rocky-9` | Rocky Linux 9 minimal | 512 MB | 20 GB | RHEL-compatible, EPEL — blocked |
| 9 | `opensuse-tw` | openSUSE Tumbleweed NET | 512 MB | 20 GB | zypper family |
| 10 | `ubuntu-2004` | Ubuntu 20.04 LTS server | 512 MB | 20 GB | nvim 0.4 in repo — oldest apt case |

### Running a test (once VMs are set up)

```bash
ssh -p 220X tester@localhost
git clone https://github.com/anomalyco/aid ~/aid
bash ~/aid/install.sh
```

Reset to clean state: `virsh --connect qemu:///session snapshot-revert <vm> clean`

### What to look for per distro

| VM | Expected behaviour |
|----|--------------------|
| `ubuntu-2404` | install.sh completes without intervention |
| `ubuntu-2204` | install.sh detects nvim 0.6, downloads AppImage to `~/.local/bin/nvim` |
| `debian-12` | AppImage path (nvim 0.7 in repo) |
| `debian-11` | AppImage path (nvim 0.4 in repo) |
| `fedora-42` | install.sh completes; pynvim via `pip3 install pynvim` |
| `arch` | existing pacman path still works |
| `alpine-319` | `watch_and_update.sh` uses `/proc/<pid>/cwd` not `lsof` |
| `rocky-9` | EPEL enabled automatically; pynvim via pip3 |
| `opensuse-tw` | install.sh completes; zypper path |
| `ubuntu-2004` | AppImage path (nvim 0.4 in repo) |
