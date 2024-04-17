# Debian STABLE tweak
A script to remove and install my own debian 12 base install

clone the repo or copy the file "debian-tweak.sh" to your local computer then run it with bash

## QEMU / KVM Tweaks
You may want to modify a bit how KVM / QEMU runs

Remove '#' at the following lines: unix_sock_group = "libvirt" and unix_sock_rw_perms = "0770"' of the following file:
- **`/etc/libvirt/libvirtd.conf`**

Uncomment and add your user name to user and group to this file.
- **`/etc/libvirt/qemu.conf`**
  - user = "your username"
  - group = "your username"
 
## Adding storage pools
As root user
``` bash
[root@fedora ~]# virsh pool-list --all
 Name      State    Autostart
-------------------------------
 default   active   yes
```

Define the directory for VM Disks
``` bash
virsh pool-define-as --name "Disk Images" --type dir --target /media/fedo/VMdisk/VMmainDisk/
```

Define the directory for Installation Media
``` bash
virsh pool-define-as --name "Installation Media" --type dir --target /media/fedo/MiscData/ISOs/
```

Start the pools
``` bash
virsh pool-start --build "Disk Images"
virsh pool-start --build "Installation Media"
```

Check their status
``` bash
virsh pool-list --all
 Name                 State      Autostart
--------------------------------------------
 default              inactive   no
 Disk Images          active     no
 Installation Media   active     no
```

Enable auto-start
``` bash
virsh pool-autostart "Disk Images"
virsh pool-autostart "Installation Media"
```

Check their status again
``` bash
virsh pool-list --all
 Name                 State      Autostart
--------------------------------------------
 default              inactive   no
 Disk Images          active     yes
 Installation Media   active     yes
```

We can more info if needed with below commands
``` bash
[root@debian ~]# virsh pool-info "Disk Images"
Name:           Disk Images
UUID:           1ed11501-52a3-4640-9229-498538d31c92
State:          running
Persistent:     yes
Autostart:      yes
Capacity:       1.83 TiB
Allocation:     32.00 KiB
Available:      1.83 TiB

[root@debian ~]# virsh pool-info "Installation Media"
Name:           Installation Media
UUID:           e35f5d1d-bf78-4b39-8e6b-954a6bf443a8
State:          running
Persistent:     yes
Autostart:      yes
Capacity:       3.58 TiB
Allocation:     32.00 KiB
Available:      3.58 TiB
```

In the file `/etc/libvirt/qemu.conf` check setting "`security_driver`". By default it uses **selinux** which prevents issues with a VM that can potentially harm the host machine. 

