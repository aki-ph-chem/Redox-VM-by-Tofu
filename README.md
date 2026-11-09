# Redox VM Tofu

An OpenTofu setup for running Redox OS on QEMU/KVM + libvirt + virt-manager.
OpenTofu creates and starts the VM and attaches the Redox livedisk; installing
Redox to the VM disk is done manually with the GUI installer.

See [plan.md](./plan.md) for the research, design notes, and risks.

## Requirements

- Nix with flakes enabled
- libvirt / QEMU / virt-manager installed system-wide
- `/dev/kvm` available
- Your user in the `libvirtd` group
- libvirt's `default` storage pool and `default` network active

```sh
virsh -c qemu:///system pool-list --all
virsh -c qemu:///system net-list --all
```

## Usage

```sh
nix develop
tofu -chdir=tofu init
tofu -chdir=tofu apply
```

Or:

```sh
nix run .#init
nix run .#apply
```

The `tofu` command provided by `nix develop` is a wrapper that automatically
sets up:

- the `dmacvicar/libvirt` 0.9.9 provider
- the Redox desktop livedisk ISO (from the Nix store)
- the non-Secure-Boot OVMF paths

## Boot and manual installation

1. Open the display:

   ```sh
   virt-viewer --connect qemu:///system redox
   ```

   Or open `redox` in virt-manager.

2. At the bootloader resolution prompt, press **Enter**.
3. At the Orbital login screen, log in as `user` (empty password).
4. In a terminal:

   ```sh
   sudo redox_installer_gui
   ```

5. In the installer:
   - **Whole Drive**
   - the 16 GiB virtio disk (e.g. `disk.vd0`; do **not** select `disk.live`)
   - **Clone this OS**
   - no encryption
6. When the installation finishes, reboot the VM.
7. Press Enter at the resolution prompt. If it still boots from the CD, eject it:

   ```sh
   virsh -c qemu:///system change-media redox sda --eject --config
   ```

   Or:

   ```sh
   tofu -chdir=tofu apply -var attach_installer=false
   ```

8. Log in as `user` and verify `cosmic-term`, `cosmic-files`, and `cosmic-edit`.

## About COSMIC

As of November 2026, Redox only ships COSMIC **applications**.
`cosmic-comp` / `cosmic-session` are not packaged yet, so the full COSMIC
desktop environment does not run. This setup runs COSMIC applications on top
of Orbital.

Additional applications:

```sh
sudo pkg install cosmic-monitor cosmic-reader
```

## Cleanup

```sh
tofu -chdir=tofu destroy
```

To keep the installed disk:

```sh
tofu -chdir=tofu destroy -var protect_disk=true
```

## Updating the image

Update the `redoxImage` URL and `hash` in `flake.nix` to match the new daily
image's `SHA256SUM`.

```nix
redoxImage = pkgs.fetchurl {
  url = "https://static.redox-os.org/img/x86_64/redox_desktop_..._livedisk.iso.zst";
  hash = "sha256-...";
};
```

## Notes

- UEFI uses non-Secure-Boot OVMF because Redox is unsigned.
- The bootloader prompts for a resolution on every boot. Press Enter for now.
- The disk is virtio-blk (`vda`); the installer media is a SATA CD (`sda`).
- Networking uses an e1000 NIC on libvirt's `default` NAT network.
