provider "libvirt" {
  uri = var.libvirt_uri
}

resource "libvirt_volume" "disk" {
  name     = "${var.name}.qcow2"
  pool     = var.pool
  capacity = var.disk_size

  target = {
    format = {
      type = "qcow2"
    }
  }

  lifecycle {
    prevent_destroy = var.protect_disk
  }
}

resource "libvirt_domain" "redox" {
  name        = var.name
  type        = "kvm"
  memory      = var.memory_mb
  memory_unit = "MiB"
  vcpu        = var.vcpus
  running     = var.start
  autostart   = false

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"

    # Explicit non-Secure-Boot OVMF.  Using `firmware = "efi"` alone makes
    # libvirt choose the Secure Boot build, which cannot boot unsigned Redox.
    loader          = var.ovmf_code
    loader_readonly = "yes"
    loader_type     = "pflash"

    nv_ram = {
      nv_ram          = "${var.nvram_dir}/${var.name}_VARS.fd"
      template        = var.ovmf_vars
      template_format = "raw"
      format          = "raw"
    }

    boot_devices = var.attach_installer ? [
      { dev = "hd" },
      { dev = "cdrom" },
    ] : [
      { dev = "hd" },
    ]
  }

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
  }

  devices = {
    disks = concat(
      [
        {
          source = {
            volume = {
              pool   = var.pool
              volume = libvirt_volume.disk.name
            }
          }
          target = {
            dev = "vda"
            bus = "virtio"
          }
          driver = {
            name = "qemu"
            type = "qcow2"
          }
        },
      ],
      var.attach_installer ? [
        {
          source = {
            file = {
              file = var.iso_path
            }
          }
          target = {
            dev = "sda"
            bus = "sata"
          }
          driver = {
            name = "qemu"
            type = "raw"
          }
          device    = "cdrom"
          read_only = true
        },
      ] : []
    )

    interfaces = [
      {
        model = {
          type = "e1000"
        }
        source = {
          network = {
            network = var.network_name
          }
        }
      },
    ]

    graphics = [
      {
        spice = {
          auto_port = true
          listen    = var.spice_listen
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
