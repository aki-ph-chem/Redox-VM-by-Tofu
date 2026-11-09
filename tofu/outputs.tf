output "domain_name" {
  description = "libvirt domain name"
  value       = libvirt_domain.redox.name
}

output "disk_volume" {
  description = "libvirt volume name of the Redox disk"
  value       = libvirt_volume.disk.name
}

output "disk_path" {
  description = "Host path of the Redox disk"
  value       = libvirt_volume.disk.path
}

output "viewer_command" {
  description = "Open the VM display"
  value       = "virt-viewer --connect ${var.libvirt_uri} ${libvirt_domain.redox.name}"
}

output "serial_command" {
  description = "Attach to the serial console"
  value       = "virsh -c ${var.libvirt_uri} console ${libvirt_domain.redox.name}"
}

output "eject_installer_command" {
  description = "Eject the livedisk CD-ROM after installation"
  value       = "virsh -c ${var.libvirt_uri} change-media ${libvirt_domain.redox.name} sda --eject --config"
}
