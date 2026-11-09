# Redox OS を QEMU/KVM + libvirt + virt-manager で動かす

## 0. 結論（要約）

- Redox は **2026-11-08 の daily `desktop` イメージ**を使う。stable 0.9.0 は 2024-09 で、COSMIC アプリや最新の virtio 対応が入っていない。
- VM は **q35 + KVM + UEFI (OVMF, Secure Boot off) + virtio-blk + SATA CD** 構成にする。
- 環境構築は **OpenTofu 1.13.2 + `dmacvicar/libvirt` 0.9.9**。どちらもリポジトリ内の `flake.nix` で固定する。
- Redox のディスクへのインストールは、**livedisk から GUI installer を手動実行**する（`Clone this OS`）。VM の作成・起動・CD の接続までは OpenTofu が行う。
- **重要:** 2026-11 時点で Redox に配布されている COSMIC は「COSMIC アプリ」のみ。`cosmic-comp` / `cosmic-session` は未配布で、**完全な COSMIC デスクトップ環境はまだ動かない**。今回の達成条件は「Orbital 上で `cosmic-term` / `cosmic-files` / `cosmic-edit` が動く」とする。完全な COSMIC DE は別フェーズ（Redox をソースビルド）で挑戦する。

---

## 1. 現状調査（2026-11-09 時点）

| 項目 | 状況 |
|---|---|
| ホスト | NixOS 26.11, Nix 2.34.9, libvirt 12.8.0, QEMU 11.1.2, virt-manager 導入済み |
| KVM | `/dev/kvm` あり。ユーザーは `libvirtd` グループに所属 |
| Redox stable | 0.9.0（2024-09-07）。daily に対して古い |
| Redox daily | `2026-11-08_581`（desktop / demo / server の各 variant） |
| desktop variant | `cosmic-edit`, `cosmic-files`, `cosmic-icons`, `cosmic-term`, `installer-gui`, `netsurf`, Orbital |
| demo variant | 上記 + `cosmic-monitor`, `cosmic-reader`, `servo`, `webkitgtk3` など（約 3 GB） |
| 完全な COSMIC DE | `cosmic-comp` / `cosmic-session` / `cosmic-app-library` はパッケージ未配布。`config/wayland.toml` はあるが cookbook にレシピがなく、現状は実験用 |
| UEFI | livedisk ISO に BIOS + UEFI の El Torito イメージあり。OVMF で起動確認済み |
| libvirt | `qemu:///system` で UEFI + virtio-blk + SATA CD + SPICE + std VGA のドメインが Orbital ログイン画面まで起動することを確認済み |
| Secure Boot | `firmware = "efi"` だけ指定すると Secure Boot 有効の OVMF が選ばれ、署名のない Redox は起動できない。**非 Secure Boot の OVMF を明示指定する必要がある** |
| ブートローダー | 起動のたびに画面解像度の選択画面が出る。Enter で進む（手動） |
| インストーラー | `/scheme/disk*` を列挙する。virtio-blk も AHCI も `disk.*` スキームを登録するため、virtio ディスクも検出可能（ソース確認済み） |
| libvirt provider | nixpkgs の 0.8.3 は旧フラットスキーマ。0.9.9 は `os` / `devices` のネストスキーマで、CD-ROM・UEFI・シリアルを自然に書ける |

### 1.1 COSMIC についての注意

Redox の「COSMIC デスクトップ環境」は、現時点では次の 2 つを混同しやすい。

1. **COSMIC アプリ**（`cosmic-term`, `cosmic-files`, `cosmic-edit`, `cosmic-monitor`, `cosmic-reader`）
   - これは libcosmic 製のアプリで、Redox では Orbital 上で動く。daily desktop イメージに一部が同梱済み。
2. **COSMIC DE 本体**（`cosmic-comp` コンポジター、`cosmic-session`、パネル、設定デーモン）
   - これは未配布。2026-03 の「COSMIC compositor が winit のウィンドウとして動いた」はデモ段階で、日常利用できるセッションではない。

したがって、今回の計画では **1 を達成目標**とし、2 は「将来の拡張」として切り分ける。

---

## 2. 達成条件（Definition of Done）

### Phase 1（今回のゴール）

- [ ] `nix develop` で OpenTofu + libvirt provider + Redox ISO が揃う
- [ ] `tofu init` / `tofu apply` で VM が作成され、UEFI で livedisk が起動する
- [ ] Orbital のログイン画面が出て、`user`（パスワードなし）でログインできる
- [ ] GUI installer で 16 GiB の virtio ディスクへ `Clone this OS` でインストールできる
- [ ] 再起動後、CD なしで UEFI からインストール済み Redox が起動する
- [ ] `cosmic-term` / `cosmic-files` / `cosmic-edit` が起動する
- [ ] `tofu destroy` で VM とディスクを削除できる（保護オプションあり）

### Phase 2（余裕があれば）

- [ ] `cosmic-monitor` / `cosmic-reader` を `pkg install` で追加
- [ ] virtio-fs でホストディレクトリを共有
- [ ] virtio-gpu / 音声（ich9）の動作確認
- [ ] 完全な COSMIC DE（`config/wayland.toml` をベースに Redox をソースビルド）

---

## 3. アーキテクチャ

```text
flake.nix
 ├─ OpenTofu 1.13.2
 ├─ dmacvicar/libvirt 0.9.9（リリースバイナリを SHA256 固定で取得）
 ├─ Redox desktop livedisk ISO（fetchurl + zstd、SHA256 固定）
 └─ devShell（tofu, virsh, virt-manager, qemu, zstd, jq）
        │
        ▼
tofu/
 ├─ libvirt_volume "disk"     16 GiB qcow2（default pool）
 └─ libvirt_domain "redox"
      ├─ q35 + KVM + host-passthrough
      ├─ OVMF（非 Secure Boot）+ 専用 NVRAM
      ├─ virtio-blk vda : インストール先
      ├─ SATA CD   sda : Redox livedisk ISO
      ├─ e1000 NIC : libvirt default NAT
      ├─ SPICE + std VGA 64 MiB
      ├─ PS/2 キーボード・マウス
      ├─ ich9 サウンド
      └─ serial pty（デバッグ用）
        │
        ▼
libvirt (qemu:///system)
        │
        ▼
QEMU/KVM → OVMF → Redox livedisk（手動で installer 実行）
                    → vda に RedoxFS + ESP を書き込み
                    → 再起動 → vda から UEFI ブート
```

---

## 4. VM スペック

| 項目 | 値 | 理由 |
|---|---|---|
| machine | `q35` | AHCI / PCIe が使える。Redox の QEMU 推奨構成 |
| accel | KVM | ホストで高速化 |
| CPU | `host-passthrough`, 4 vCPU | Redox の推奨に合わせる |
| メモリ | 4096 MiB | Orbital + COSMIC アプリ + ブラウザを考慮 |
| ディスク | 16 GiB qcow2, virtio-blk (`vda`) | インストール先。qcov2 でスナップショット可能 |
| インストールメディア | SATA CD (`sda`), raw ISO, read-only | UEFI/BIOS 両対応の El Torito。virtio ディスクと区別しやすい |
| ファームウェア | OVMF 非 Secure Boot + 専用 NVRAM | Redox は署名されていないため Secure Boot 不可 |
| ブート順 | `hd`, `cdrom` | 空ディスクなら CD、インストール後はディスク |
| NIC | `e1000`, `default` ネットワーク | Redox の e1000 ドライバで確実。NAT で DHCP |
| ディスプレイ | SPICE + `vga` 64 MiB | virt-manager から操作。std VGA は実績あり |
| 入力 | PS/2 マウス・キーボード | libvirt の既定。Redox で確実 |
| 音声 | `ich9` | Redox の ich9 HDA ドライバ用（任意） |
| シリアル | pty | ブートログ・デバッグ用 |
| autostart | false | 手動で起動 |

---

## 5. リポジトリ構成（案）

```text
.
├── flake.nix
├── flake.lock
├── README.md
├── plan.md
├── .gitignore
└── tofu/
    ├── versions.tf        # required_providers: dmacvicar/libvirt 0.9.9
    ├── variables.tf       # name, memory, vcpu, disk_size, iso_path, OVMF paths
    ├── main.tf            # libvirt_volume + libvirt_domain
    ├── outputs.tf         # domain 名, ディスクパス, SPICE ポート, serial 接続方法
    └── terraform.tfvars.example
```

`.gitignore` の例:

```gitignore
tofu/.terraform/
tofu/*.tfstate
tofu/*.tfstate.*
tofu/crash.log
tofu/override.tf
tofu/override.tf.json
.direnv/
result
result-*
```

`tofu/.terraform.lock.hcl` はコミットする（プロバイダのチェックサム固定のため）。

---

## 6. Nix Flake の設計

### 6.1 入力

- `nixpkgs`: `nixos-26.11` を pin（現在のホストと合わせる）
- 追加の flake 入力は不要。`flake-utils` も使わず、`x86_64-linux` 固定でよい

### 6.2 libvirt provider 0.9.9

nixpkgs の `terraform-providers.dmacvicar_libvirt` は 0.8.3 で、今回使うネストスキーマと合わない。リリースバイナリを flake 内で取得・配置する。

```nix
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
```

> 実測: このバイナリは静的リンク（`not a dynamic executable`）で、NixOS 上でそのまま動く。`tofu providers schema` も成功済み。

### 6.3 OpenTofu ラッパー

`NIX_TERRAFORM_PLUGIN_DIR` を provider のディレクトリに向けるだけで、オフラインで `tofu init` できる（実測済み）。

```nix
tofu = pkgs.writeShellScriptBin "tofu" ''
  export NIX_TERRAFORM_PLUGIN_DIR=${libvirtProvider}/libexec/terraform-providers
  export TF_VAR_iso_path=${redoxIso}
  export TF_VAR_ovmf_code=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd
  export TF_VAR_ovmf_vars=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd
  exec ${pkgs.opentofu}/bin/tofu "$@"
'';
```

`TF_VAR_*` にしておくと、`tofu apply` で長いパスを毎回渡さなくてよい。上書きしたいときは `-var` が優先される。

### 6.4 Redox ISO

```nix
redoxImage = pkgs.fetchurl {
  url = "https://static.redox-os.org/img/x86_64/redox_desktop_x86_64_2026-11-08_581_livedisk.iso.zst";
  hash = "sha256-e/5Qi6asoSJ7tXxrdYrxOwwexQwYba+ruf06hR8JXZk=";
};

redoxIso = pkgs.runCommand "redox-desktop-live.iso" { nativeBuildInputs = [ pkgs.zstd ]; } ''
  zstd -d ${redoxImage} -o $out
'';
```

- 固定する URL と SHA256 は `SHA256SUM` と一致していることを確認済み。
- ISO は `/nix/store` に置かれ、libvirt/qemu から読み取れる（実測済み）。
- daily を更新するときは URL と hash を差し替える。

### 6.5 devShell / apps

devShell に `tofu`（ラッパー）、`libvirt`、`qemu_kvm`、`virt-manager`、`zstd`、`jq`、`socat` を入れる。

便利コマンド（任意）:

- `nix run .#init` → `tofu -chdir=tofu init`
- `nix run .#plan` → `tofu -chdir=tofu plan`
- `nix run .#apply` → `tofu -chdir=tofu apply`
- `nix run .#destroy` → `tofu -chdir=tofu destroy`

---

## 7. OpenTofu の設計

### 7.1 プロバイダ

```hcl
terraform {
  required_version = ">= 1.8"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
```

### 7.2 ディスク

```hcl
resource "libvirt_volume" "disk" {
  name     = "${var.name}.qcow2"
  pool     = "default"
  capacity = var.disk_size # 16 * 1024 * 1024 * 1024
  target = {
    format = {
      type = "qcow2"
    }
  }
}
```

### 7.3 ドメイン（検証済みの形）

```hcl
resource "libvirt_domain" "redox" {
  name        = var.name
  type        = "kvm"
  memory      = 4096
  memory_unit = "MiB"
  vcpu        = 4
  running     = true
  autostart   = false

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"

    # Secure Boot を避けるため、明示的に非 Secure Boot の OVMF を指定する
    loader          = var.ovmf_code
    loader_readonly = "yes"
    loader_type     = "pflash"
    nv_ram = {
      nv_ram          = "/var/lib/libvirt/qemu/nvram/${var.name}_VARS.fd"
      template        = var.ovmf_vars
      template_format = "raw"
      format          = "raw"
    }

    boot_devices = [
      { dev = "hd" },
      { dev = "cdrom" },
    ]
  }

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = "default"
            volume = libvirt_volume.disk.name
          }
        }
        target = { dev = "vda", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2" }
      },
      {
        source = {
          file = {
            file = var.iso_path
          }
        }
        target    = { dev = "sda", bus = "sata" }
        driver    = { name = "qemu", type = "raw" }
        device    = "cdrom"
        read_only = true
      },
    ]

    interfaces = [
      {
        model  = { type = "e1000" }
        source = { network = { network = "default" } }
      },
    ]

    graphics = [
      {
        spice = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      },
    ]

    videos = [
      {
        model = {
          type    = "vga"
          vram    = 65536
          heads   = 1
          primary = "yes"
        }
      },
    ]

    sounds = [
      { model = "ich9" },
    ]

    serials = [
      {
        target = {
          type = "isa-serial"
          port = 0
        }
      },
    ]

    consoles = [
      {
        target = {
          type = "serial"
          port = 0
        }
      },
    ]
  }
}
```

### 7.4 実装上の注意（検証で判明したこと）

1. **`firmware = "efi"` だけにしない**
   - libvirt が Secure Boot 有効の OVMF（`edk2-x86_64-secure-code.fd`）を選び、Redox が起動できない。
   - 上記のように `loader` / `nv_ram` を明示し、非 Secure Boot の `OVMF_CODE.fd` を使う。
2. **`os.boot_devices` とディスクごとの `boot { order = ... }` を併用しない**
   - `per-device boot elements cannot be used together with os/boot elements` で失敗する（実測）。
   - 今回は `os.boot_devices` だけを使う。
3. **`firmware_info` は使わない**
   - provider 0.9.9 で `features` の順序が入れ替わり `Provider produced inconsistent result after apply` になるバグを確認。
   - 明示 `loader` 方式なら不要。
4. `libvirt_domain` の `running = true` で作成時に起動する。インストール中は起動したままにする。
5. ディスクを消されたくない場合は `libvirt_volume.disk` に `lifecycle { prevent_destroy = true }` を付ける（運用で選択）。

### 7.5 outputs（案）

- `domain_name`
- `disk_path`（`libvirt_volume.disk.path`）
- `spice_port`（`libvirt_domain.redox.graphics[0].spice[0].port` など。プロバイダの出力に合わせる）
- `serial_console`（`virsh console <name>` の案内）

---

## 8. 手動インストール手順

1. リポジトリで `nix develop`。
2. `tofu -chdir=tofu init`。
3. `tofu -chdir=tofu apply`。
   - VM が作成され、livedisk から起動する。
4. virt-manager で `redox` を開く、または `virt-viewer --connect qemu:///system redox`。
5. ブートローダーの解像度選択画面で **Enter**（最適な解像度が選択済み）。
6. Orbital のログイン画面で `user`（パスワード空）でログイン。
7. ターミナルを開き、次を実行:
   ```sh
   sudo redox_installer_gui
   ```
8. インストーラーで:
   - **Whole Drive** を選択
   - 16 GiB の virtio ディスク（`disk.vd0` など。**`disk.live` は選ばない**）を選択
   - **Clone this OS** を選択（livedisk の内容をそのままコピー。COSMIC アプリも入る）
   - 暗号化は今回はなし
   - インストール実行
9. 完了したら VM を再起動。
10. 再度解像度選択で Enter。ディスクから起動しない場合は CD を取り出す:
    - virt-manager の CDROM を Disconnect
    - または `virsh -c qemu:///system change-media redox sda --eject --config`
    - もしくは `tofu apply -var attach_installer=false`（実装する場合）
11. `user` でログインし、`cosmic-term` / `cosmic-files` / `cosmic-edit` を起動して確認。
12. 任意で:
    ```sh
    sudo pkg install cosmic-monitor cosmic-reader
    ```

> 補足: インストーラーの「Desktop」プロファイルはネットワークからパッケージを取得する。`Clone` の方が速く、livedisk に入っている COSMIC アプリをそのまま持って行ける。

---

## 9. 検証済み / 未検証

### 検証済み（この調査で実際に確認）

- OVMF + q35 + SATA CD で Redox desktop livedisk が UEFI ブートし、Orbital のログイン画面まで到達する（QEMU 直接実行）
- 同じ構成を libvirt ドメインとして `tofu apply` で作成し、`virsh start` 後に Orbital ログイン画面が出る
- provider 0.9.9 のスキーマ取得、`tofu validate`、`tofu apply` / `destroy`
- Secure Boot 有効の OVMF では起動できないこと
- `os.boot_devices` と per-disk boot の併用がエラーになること
- ISO に UEFI El Torito イメージがあること
- インストーラーが `/scheme/disk*` を列挙し、virtio-blk も AHCI も `disk.*` を登録すること（ソース確認）

### 未検証（実装後に確認する）

- GUI installer が virtio ディスクを実際に一覧に出し、`Clone` でインストールできること
- インストール後のディスクから UEFI ブートできること
- `cosmic-term` / `cosmic-files` / `cosmic-edit` の起動
- e1000 + DHCP で `pkg install` が通ること
- 音声（ich9）の動作
- 解像度選択を自動化できるか（現状は手動 Enter）

---

## 10. リスクと対策

| リスク | 対策 |
|---|---|
| 完全な COSMIC DE が動かない | Phase 1 は Orbital + COSMIC アプリ。完全版は Phase 2 で Redox をソースビルド |
| Secure Boot で Redox が起動しない | 非 Secure Boot の OVMF を明示指定（本計画の既定） |
| installer が virtio ディスクを見つけない | ディスクを SATA (`sda`) に切り替える。または prebuilt `harddrive.img` をフォールバックに使う |
| インストール後の UEFI ブートに失敗 | BIOS (SeaBIOS) で起動してブートローダーを再確認。SATA ディスクで再試行 |
| 毎回の解像度選択が面倒 | 現状は仕様。手順に明記。将来 bootloader の設定で自動化を検討 |
| インストール後も CD から起動する | CD を取り出す / boot order を `hd` のみにする / `attach_installer` 変数を実装 |
| provider 0.8.3 だと HCL が合わない | flake で 0.9.9 を固定（本計画の既定） |
| `tofu destroy` でディスクを失う | `prevent_destroy` または `protect_disk` 変数で保護 |
| libvirt が Nix store の ISO/OVMF を読めない | `/nix/store` は world-readable。実測済み。SELinux/AppArmor 環境では追加設定 |
| ネットワークが繋がらない | e1000 + libvirt default NAT を既定に。DHCP のログを serial で確認 |

---

## 11. マイルストーン

- **M0: 骨組み**
  - `flake.nix`（tofu + provider + ISO + devShell）
  - `tofu/` の `versions.tf` / `variables.tf` / `main.tf` / `outputs.tf`
  - `tofu validate` と `tofu plan` が通る
- **M1: VM 起動**
  - `tofu apply` で VM が起動し、UEFI で Orbital ログインまで行く
- **M2: 手動インストール**
  - installer で virtio ディスクへ Clone
  - 再起動後にディスクから UEFI ブート
- **M3: COSMIC アプリ確認**
  - `cosmic-term` / `cosmic-files` / `cosmic-edit`
  - 任意で `cosmic-monitor` / `cosmic-reader`
- **M4: 拡張（任意）**
  - virtio-fs、virtio-gpu、音声、完全な COSMIC DE の検討

---

## 12. 未決事項（要相談）

1. **COSMIC の範囲**
   - A: Orbital + COSMIC アプリ（推奨。今回のスコープ）
   - B: Redox をソースビルドして `cosmic-comp` / `cosmic-session` を動かす（実験的。ビルド時間・不安定さ大）
   - C: まずは Redox の起動だけ確認し、COSMIC は後回し
2. **イメージ**
   - `desktop`（約 650 MiB、COSMIC アプリ 4 つ + installer）
   - `demo`（約 3 GiB、cosmic-monitor/reader + Servo/WebKit も入る）
   - 推奨: `desktop` + 必要なら `pkg install`
3. **ディスクサイズ / メモリ**
   - 既定: 16 GiB / 4 GiB。変更したい場合は `variables.tf` で調整
4. **永続化**
   - `tofu destroy` でディスクも消すか、`prevent_destroy` で残すか
5. **音声**
   - 初期構築では不要なら `sounds` を外すことも可能（Redox 側の audiod が不安定な場合がある）
