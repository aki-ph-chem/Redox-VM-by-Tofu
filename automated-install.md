# Redox の自動インストール・設定注入

最終更新: 2026-11-10

Redox OS で「Linux の cloud-init / autoinstall / virt-customize に相当するもの」を
どう実現するかを調査したメモ。結論から言うと、現時点では次の使い分けになる。

| 目的 | Redox の手段 | 状態 |
|---|---|---|
| 初回起動時にメタデータから設定を渡す | cloud-init 互換サービス（NoCloud / HTTP metadata） | **未実装（計画中）** |
| インストール時に設定を焼き込む | `redox_installer --config=...` | 利用可能（Linux ではソースからビルド） |
| 既存イメージの中身を編集する | `redoxfs` の FUSE マウント | 利用可能 |
| イメージをビルド時にカスタマイズする | Redox build system の `config/*.toml` | 利用可能（ビルドが必要） |
| 起動後にパッケージを追加する | `pkg install` | 利用可能（ネットワーク必要） |

---

## 1. cloud-init 相当の「初回起動設定」

**2026-11 時点では未実装。**

Redox の 2026-11-08 の記事
[Virtualized Redox: from Virtio-FS to Cloud Hypervisor, and beyond](https://www.redox-os.org/news/virtualized-redox/)
では、残作業として次のように書かれている。

> First-boot configuration: A modular, cloud-init-compatible service that sets
> the hostname and installs an SSH key, read from a NoCloud drive or the HTTP
> metadata service, so credentials stay out of the image.

つまり、

- cloud-init 互換の設定サービス
- NoCloud ドライブ
- HTTP メタデータサービス

は**計画中**で、2026-11-08 の daily イメージには入っていない。

確認した範囲では:

- cookbook に `cloud-init` レシピはない
- Redox の GitLab に `cloud-init` / `cloudinit` / `nocloud` プロジェクトはない
- Redox の base リポジトリに NoCloud datasource はない

したがって、Linux のように「VM を起動するたびにメタデータから hostname や
SSH 鍵を取得する」ことは、現状では標準機能ではできない。

### 現状の代替

初回起動時に何かをしたい場合は、`/usr/lib/init.d/` に独自の init スクリプトを
置くことはできる。ただし、設定ファイルの取得・解釈は自前になる。

例:

```sh
# /usr/lib/init.d/99-first-boot
#!/bin/sh
# 例: 共有ディレクトリや追加ディスクから設定を読む
if [ -f /scheme/virtio-fs.config/hostname ]; then
    cp /scheme/virtio-fs.config/hostname /etc/hostname
fi
```

Redox は virtio-fs に対応しているため、ホスト側のディレクトリを設定配布に
使うことは理論上可能。ただし cloud-init のような汎用処理はない。

---

## 2. 自動インストール: `redox_installer` の CLI

Redox の installer には GUI / TUI のほかに、設定ファイルを読む CLI がある。

リポジトリ:

- <https://gitlab.redox-os.org/redox-os/installer>

### 2.1 使い方

```text
redox_installer <diskpath.img> \
  [--config=file.toml] \
  [--write-bootloader=file.img] \
  [--live] \
  [--no-mount] \
  [--skip-partition]
```

主なオプション:

| オプション | 意味 |
|---|---|
| `--config=file.toml` | インストール設定 TOML |
| `--write-bootloader=file` | UEFI ブートローダーを追加で書き出す |
| `--live` | live disk 用のブートローダー設定にする |
| `--no-mount` | FUSE マウントではなく RedoxFS AR で書き込む |
| `--skip-partition` | GPT を書かない（パーティション作成を自分で行う場合） |
| `--cookbook=path` | ローカルの Redox build system を使う |
| `--config-name=name` | `os-release` の `VARIANT` を設定 |

設定ファイルのパーサーとしても使える:

```sh
redox_installer --config=file.toml --list-packages
redox_installer --config=file.toml --filesystem-size
redox_installer --config=file.toml --output-config merged.toml
```

### 2.2 設定 TOML でできること

設定は Redox build system の filesystem 設定と同じ形式。

```toml
[general]
prompt = false
filesystem_size = 16384
efi_partition_size = 2

[packages]
base = {}
kernel = {}
bootloader = {}
relibc = {}
userutils = {}
uutils = {}
openssh = {}
cosmic-term = {}
cosmic-files = {}

[[files]]
path = "/etc/hostname"
data = "redox-vm"

[[files]]
path = "/home/user/.ssh/authorized_keys"
data = "ssh-ed25519 AAAA..."
mode = 384 # 0600
uid = 1000
gid = 1000

[users.user]
password = ""
shell = "/usr/bin/ion"

[groups.sudo]
gid = 1
members = ["user"]
```

指定できるもの:

- `[general]`: ファイルシステムサイズ、EFI パーティションサイズ、暗号化、
  live disk、`no_mount`、ブートローダー出力先など
- `[packages]`: インストールするパッケージ
- `[[files]]`: 任意のファイル、ディレクトリ、シンボリックリンク
  - `postinstall = true` にするとパッケージインストール後に書かれる
  - `uid` / `gid` / `mode` を指定可能
- `[users.*]`: ユーザー、UID/GID、ホーム、シェル、パスワード
- `[groups.*]`: グループとメンバー

パスワードは installer が argon2 でハッシュ化して `/etc/shadow` に書く。
設定ファイル自体には平文で書くため、扱いには注意する。

### 2.3 UEFI

`redox_installer` は GPT と ESP を作り、UEFI ブートローダーを書き込める。
RedoxFS のドキュメントにも「UEFI ブート可能な GPT を作るのは
`redox-installer` の役割」と書かれている。

`redoxfs-mkfs` / `redoxfs-ar` だけでは UEFI ブートディスクは作れない。

### 2.4 実行環境

- Redox の live イメージには `installer` パッケージが入っており、
  `redox_installer` CLI と `redox_installer_tui` が含まれる（ソース上）
- Linux 側で使う場合はソースからビルドする

  ```sh
  git clone https://gitlab.redox-os.org/redox-os/installer.git
  cd installer
  cargo build --release --bin redox_installer
  ```

- RedoxFS の FUSE を使う場合、Linux では libfuse 3.x が必要になることがある
- `--no-mount` を使うと実行時の FUSE マウントを避けられる
- パッケージは既定で `https://static.redox-os.org/pkg` から取得するため、
  ネットワークが必要（`--cookbook` を使うとローカルビルド）

### 2.5 注意点

- 配布バイナリはない。Linux では自分でビルドする必要がある
- GUI installer は libcosmic / Wayland 前提だが、CLI はその制約がない
- CLI は主にディスクイメージを対象にしている。ブロックデバイス直接指定は要検証
- 設定ファイルに平文パスワードを書く場合は、リポジトリにコミットしない

---

## 3. 既存イメージの編集: RedoxFS ツール

RedoxFS は Linux の FUSE でマウントできる。Linux の
`virt-customize` / `libguestfs` に近い使い方ができる。

### 3.1 インストール

```sh
cargo install redoxfs
```

FUSE 3.x が必要になる場合がある。

### 3.2 マウントして編集

```sh
mkdir mnt
redoxfs redox.img ./mnt

# 設定を編集
vi mnt/etc/hostname
mkdir -p mnt/home/user/.ssh
cp authorized_keys mnt/home/user/.ssh/

fusermount3 ./mnt
```

### 3.3 その他のツール

| ツール | 用途 |
|---|---|
| `redoxfs` | FUSE でマウント |
| `redoxfs-ar` | ディレクトリツリーをイメージに書き込む（既存内容は上書き） |
| `redoxfs-mkfs` | 空の RedoxFS を作成 |
| `redoxfs-clone` | イメージをクローン |
| `redoxfs-resize` | イメージのリサイズ（実験的） |

`redoxfs-ar` は既存イメージの部分更新には向かない。既存イメージを編集するなら
FUSE マウントを使う。

### 3.4 制約

- `redoxfs-mkfs` / `redoxfs-ar` では UEFI ブート可能な GPT は作れない
- UEFI ブート可能なイメージが必要なら `redox_installer` を使う
- Linux の libguestfs / virt-customize は RedoxFS を扱えない

---

## 4. ビルド時にイメージへ設定を焼き込む

Redox の build system は `config/*.toml` でイメージ内容を定義できる。
`[[files]]`、`[packages]`、`[users]` など、installer とほぼ同じ形式。

これは「イメージをビルドする時点で設定を入れる」方式で、Linux の
Packer / image builder に近い。ただし Redox 本体をビルドする必要があり、
時間とディスク容量がかかる。

既存の例:

- `config/desktop.toml`
- `config/server.toml`
- `config/x86_64/demo.toml`

---

## 5. Linux ツールとの対応

| Linux | Redox の現状 |
|---|---|
| cloud-init / NoCloud | 未実装。cloud-init 互換サービスが計画中 |
| autoinstall / kickstart | `redox_installer --config` で可能 |
| virt-customize / libguestfs | `redoxfs` の FUSE マウントで可能 |
| Packer | Redox 用の公式プラグインは確認できず。`redox_installer` + OpenTofu で自作 |
| cloud image + metadata | メタデータサービスは未実装 |
| 初回起動スクリプト | `/usr/lib/init.d/` に独自スクリプトを置ける。設定取得は自前 |
| パッケージ追加 | `pkg install` |

---

## 6. 本リポジトリへの適用案

現在の `plan.md` は「GUI installer で手動インストール」を前提にしている。
自動化したい場合、次の案が考えられる。

### 案 A: `redox_installer` + 設定 TOML（おすすめ）

ホスト側で設定済みの Redox ディスクイメージを作り、OpenTofu はそれを
`vda` として接続する。

流れ:

1. `flake.nix` で `redox_installer` をビルド（または手動で用意）
2. `install.toml` に hostname、SSH 鍵、ユーザー、パッケージを書く
3. `redox_installer redox.qcow2 --config=install.toml` を実行
4. OpenTofu は `redox.qcow2` をディスクとして接続
5. VM 起動

メリット:

- `tofu apply` だけで設定済み VM が出来る
- ユーザー、SSH 鍵、パッケージを再現可能にできる
- UEFI ブートローダーも installer が書ける

デメリット:

- `redox_installer` の Linux ビルドが必要
- パッケージ取得にネットワークが必要
- まだこのリポジトリでは実機検証していない

### 案 B: prebuilt イメージ + RedoxFS マウント

prebuilt の `harddrive.img` をダウンロードし、`redoxfs` でマウントして
`/etc/hostname` や SSH 鍵を入れる。

メリット:

- installer のビルドが不要
- 小さい変更なら簡単

デメリット:

- パッケージ追加やユーザー作成は手作業になりがち
- イメージの更新時に再作業が必要

### 案 C: 現在の手動 GUI インストール

`plan.md` の現行案。GUI installer で `Clone this OS`。

メリット:

- すでに UEFI ブートまで検証済み
- 確実

デメリット:

- 自動化されない

### 案 D: 独自の first-boot 設定

`/usr/lib/init.d/` に初回起動スクリプトを入れ、設定ディスクや virtio-fs から
hostname / SSH 鍵を読む。

メリット:

- cloud-init に近い動きを自前で実現できる

デメリット:

- 完全に自作
- cloud-init 互換サービスが入るまでのつなぎ

---

## 7. 検証状況

このメモはソース・ドキュメント・パッケージ一覧の調査に基づく。
以下はまだ実機検証していない。

- `redox_installer` を Linux でビルドしてイメージを作成する
- そのイメージが UEFI で起動すること
- `redoxfs` でマウントして編集したイメージが起動すること
- `install.toml` の `[[files]]` / `[users]` が期待通り反映されること

---

## 8. 参考リンク

- Redox: Virtualized Redox（2026-11-08）
  - <https://www.redox-os.org/news/virtualized-redox/>
- Redox installer
  - <https://gitlab.redox-os.org/redox-os/installer>
- RedoxFS（Linux FUSE ツール）
  - <https://doc.redox-os.org/book/redoxfs.html>
- Redox の filesystem 設定リファレンス
  - <https://doc.redox-os.org/book/configuration-settings.html>
- Redox のインストール手順
  - <https://doc.redox-os.org/book/installing.html>
