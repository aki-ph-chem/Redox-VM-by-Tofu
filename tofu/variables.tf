variable "libvirt_uri" {
  description = "libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "name" {
  description = "Domain and disk name prefix"
  type        = string
  default     = "redox"
}

variable "memory_mb" {
  description = "Guest memory in MiB"
  type        = number
  default     = 4096
}

variable "vcpus" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "Redox disk capacity in bytes"
  type        = number
  default     = 17179869184 # 16 GiB
}

variable "pool" {
  description = "libvirt storage pool for the disk"
  type        = string
  default     = "default"
}

variable "network_name" {
  description = "libvirt network for the e1000 NIC"
  type        = string
  default     = "default"
}

variable "iso_path" {
  description = "Path to the Redox livedisk ISO (set by the Nix wrapper)"
  type        = string
}

variable "ovmf_code" {
  description = "OVMF code image (non-Secure Boot)"
  type        = string
  default     = "/run/libvirt/nix-ovmf/edk2-x86_64-code.fd"
}

variable "ovmf_vars" {
  description = "OVMF NVRAM template"
  type        = string
  default     = "/run/libvirt/nix-ovmf/edk2-i386-vars.fd"
}

variable "nvram_dir" {
  description = "Directory where libvirt stores per-domain NVRAM files"
  type        = string
  default     = "/var/lib/libvirt/qemu/nvram"
}

variable "attach_installer" {
  description = "Attach the Redox livedisk ISO as a SATA CD-ROM"
  type        = bool
  default     = true
}

variable "start" {
  description = "Start the domain after creation"
  type        = bool
  default     = true
}

variable "protect_disk" {
  description = "Prevent tofu destroy from deleting the Redox disk"
  type        = bool
  default     = false
}

variable "spice_listen" {
  description = "SPICE listen address"
  type        = string
  default     = "127.0.0.1"
}
