# qemu-wrappers

Wrappers for running Qemu/KVM without the need of fat abstraction layers.

The files here started as scripts to test Heise Desinfec't builds in Qemu and were later adapted to make my work at [Checkmk](https://github.com/Checkmk) easier.
They are not intended to be a replacement for what libvirt can do.

## General notes

For performance reasons, block and network devices are virtio.
They might not work with older kernels or require additional drivers (Windows).
Networking is best used together with the tap devices provided by `dummybridge.sh`.
Console access is mostly done with VNC.
I recommend using [Remmina](https://remmina.org) to access the console.
In case you are using Windows, enable RDP.

## The scripts

### dummybridge.sh

Run with sudo without parameters to create network devices.
The network devices are non-permanent which makes it easy to tinker and mess (for example if a second net with dummy and tap devices is needed).
Just reboot in case of messing it up.

1. Create vmdummy0 to use for tap devices later
1. Create vmtap0 to vmtap9 owned by $SUDO_USER to attach VMs to
1. Assign 198.51.100.1/24 to vmdummy0
1. Configure NAT and create a default route

If no DHCP configuration is present, an example is emitted. 
Just copy and paste it to `/etc/dhcp/dhcpd.conf` and `/etc/default/isc-dhcp-server` repspectively.

### quickdebuntu.sh

Create an Ubuntu or Debian VM from scratch with debootstrap.
To work, a `debootstrap` with the needed scripts has to be installed.
For example, Ubuntu Noble provides scripts to successfully bootstrap Ubuntu Jammy and Noble and Debian Bookworm and Trixie, but misses scripts for Devuan (Debian with SysV init).
The disk images created are raw, but the default filesystem is btrfs and the installation is done in a subvolume, so you can create snapshots at file system level.
Since the debootstrap procedure requires creating loop files and chroot, the install step has to be run with sudo.
The script enables an SSH server and copies the ed25519 public key from $SUDO_USER to `/root/.ssh/authorized_keys` to enable SSH login immediately after starting.

How to use:

1. Create a directory for the VM to live in
1. Copy the configuration `quickdebuntu_config.sh` to the target directory and adjust according to your needs
1. Run the installation: `sudo ./quickdebuntu.sh /path/to/targetdir`
1. Start the VM as non-root user: `./quickdebuntu.sh /path/to/targetdir`

After starting up, the script tries to read the MAC address specified from the arp cache and retrieve its IP address:

    Successfully started, use
    
    vncviewer localhost:23
    
    to see the system console.
    Waiting 15 seconds for the MAC to appear...
    You should now be able to run
    
    ssh root@198.51.100.100

### quickcmkvirt.sh

Create and run the [Checkmk appliance](https://docs.checkmk.com/latest/en/appliance_virt1_quick_start.html) in Qemu/KVM.
The script unpacks the OVA archive, converts the disk images to qcow2, copies Open Virtual Machine Firmware files and launches the VM.

How to use:

1. Create a directory for the VM to live in
1. Copy the configuration `quickcmkvirt_config.sh` to the target directory and adjust according to your needs
1. Start the VM as non-root user: `./quickcmkvirt.sh /path/to/targetdir /path/to/virt1-1.7.x.ova`

Once the OVA archive has been unpacked and disks are converted, the second command line parameter can be omitted.
Remember: The Checkmk appliance requires a static IP configuration, so you have to connect to the system console with VNC at least once.

After starting up, the script tries to read the MAC address specified from the arp cache and retrieve its IP address:

    Successfully started, use
    
    vncviewer localhost:26
    
    to see the system console.
    Waiting 30 seconds for the MAC to appear...
    You should now be able to access the appliance in the browser:
    
    http://198.51.100.205/
