{
  description = "Redox OS VM on libvirt, provisioned with OpenTofu";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # dmacvicar/libvirt 0.9.9 (the version in nixpkgs is 0.8.3 and uses the
      # old flat schema, which cannot express CD-ROM/UEFI devices the way we need).
      libvirtProvider = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "terraform-provider-libvirt";
        version = "0.9.9";

        src = pkgs.fetchurl {
          url = "https://github.com/dmacvicar/terraform-provider-libvirt/releases/download/v${version}/terraform-provider-libvirt_${version}_linux_amd64.zip";
          hash = "sha256-cKnVr5mmAXnH04AyZi9EPD0q2L3asR1TXFRcXEQnOy0=";
        };

        nativeBuildInputs = [ pkgs.unzip ];

        unpackPhase = "unzip $src";

        installPhase = ''
          mkdir -p $out/libexec/terraform-providers/registry.opentofu.org/dmacvicar/libvirt/${version}/linux_amd64
          cp terraform-provider-libvirt_v${version} \
            $out/libexec/terraform-providers/registry.opentofu.org/dmacvicar/libvirt/${version}/linux_amd64/
        '';
      };

      # Pinned daily image.  Update URL + hash together when bumping the image.
      redoxImage = pkgs.fetchurl {
        url = "https://static.redox-os.org/img/x86_64/redox_desktop_x86_64_2026-11-08_581_livedisk.iso.zst";
        hash = "sha256-e/5Qi6asoSJ7tXxrdYrxOwwexQwYba+ruf06hR8JXZk=";
        name = "redox-desktop-livedisk.iso.zst";
      };

      redoxIso = pkgs.runCommand "redox-desktop-livedisk.iso" {
        nativeBuildInputs = [ pkgs.zstd ];
      } ''
        zstd -d ${redoxImage} -o $out
      '';

      # Wrapper that makes the pinned provider and image available to OpenTofu
      # without touching the network during `tofu init`.
      tofu = pkgs.writeShellScriptBin "tofu" ''
        export NIX_TERRAFORM_PLUGIN_DIR=${libvirtProvider}/libexec/terraform-providers
        export TF_VAR_iso_path=${redoxIso}
        export TF_VAR_ovmf_code=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd
        export TF_VAR_ovmf_vars=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd
        exec ${pkgs.opentofu}/bin/tofu "$@"
      '';

      mkApp = name: args: {
        type = "app";
        program = "${pkgs.writeShellScriptBin "tofu-${name}" ''
          exec ${tofu}/bin/tofu -chdir=${toString ./tofu} ${args}
        ''}/bin/tofu-${name}";
      };
    in
    {
      packages.${system} = {
        inherit tofu redoxIso;
        default = tofu;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          tofu
          libvirt
          qemu_kvm
          virt-manager
          zstd
          jq
          socat
          xorriso
        ];

        shellHook = ''
          echo "Redox VM development shell"
          echo "  tofu -chdir=tofu init"
          echo "  tofu -chdir=tofu apply"
          echo "  tofu -chdir=tofu destroy"
        '';
      };

      apps.${system} = {
        init = mkApp "init" "init";
        plan = mkApp "plan" "plan";
        apply = mkApp "apply" "apply";
        destroy = mkApp "destroy" "destroy";
      };
    };
}
