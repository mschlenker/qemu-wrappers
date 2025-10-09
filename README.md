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

### quickcloud.sh

Create an AlmaLinux, Debian, Rocky or Ubuntu VM from the respective's project cloud init images.
The script creates a minimal seed ISO for cloud init that just sets the host name and adds the user's SSH key.
You might overwrite with a more sophisticated seed image.
Always the latest cloud image for the chosen distribution will be downloaded.
Images are snapshotted before running, so when you need multiple VMs, you can copy the image and reset the snapshot.
When the MAC address is identified from the arp cache, you are automatically logged in.

1. Create a directory for the VM to live in
1. Copy the configuration `quickcloud_config.sh` to the target directory and adjust according to your needs
1. Start the VM as non-root user: `./quickcloud.sh /path/to/targetdir`

After starting up, the script tries to read the MAC address specified from the arp cache and retrieve its IP address:

    Successfully started, use
    
    vncviewer localhost:23
    
    to see the system console.
    Waiting 15 seconds for the MAC to appear...
    Trying to log in... rocky@198.51.100.118
    
    Last login: Thu Oct  9 10:58:50 2025 from 198.51.100.1
    rocky@localhost ~$


### quickanylinux.sh

First run with an arbitrary install ISO as parameter, this allows to install any modern Linux in a Qemu/KVM.
The ISO passed can be a http:// URL.
Qemu will then download needed chunks of that ISO.
When the installation is finished, run without passing an ISO.

1. Create a directory for the VM to live in
1. Copy the configuration `quickanylinuy_config.sh` to the target directory and adjust according to your needs
1. Start the VM as non-root user: `./quickanylinux.sh /path/to/targetdir http://distro.test/install.iso`
1. After installation is done, shut down
1. Start again without passing the ISO: `./quickanylinux.sh /path/to/targetdir`

After starting up, the script tries to read the MAC address specified from the arp cache and retrieve its IP address:

    Successfully started, use
    
    vncviewer localhost:23
    
    to see the system console.
    Waiting 15 seconds for the MAC to appear...
    You should now be able to run
    
    ssh username@198.51.100.113

### quickdebuntu.sh

> [!NOTE]
> This script will probably not be updated for Ubuntu 26.04.
> Virtual machines created with it will continue to work, but new bootstraps might not be possible.

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

### quickwin10.sh

Install and run Windows 10 or Windows Server 2019 or similar in Qemu/KVM.
This scripts works only for older Windows versions that can be booted via classic BIOS from MBR partitioned disks.
The script has an "installation mode" without networking and a "run mode" with networking.
Fedora virtio drivers are mounted as HTTP image (requires Qemu 8.2, for older versions, a local file can be specified).

How to use:

1. Create a directory for the VM to live in
1. Copy the configuration `quickwin10_config.sh` to the target directory and adjust according to your needs
1. Start the VM as non-root user: `./quickwin10.sh /path/to/targetdir /path/to/win10.iso`
1. Make sure to select the virtio disk drivers from E:/amd64
1. Finish the installation, then shutdown: `shutdown.exe /s /t 0`
1. Start again without specifying the ISO: `./quickcmkvirt.sh /path/to/targetdir`
1. Install the guest tools from E:/virtio-win-gt-x64.msi
1. Enable RDP access

After starting up, the script tries to read the MAC address specified from the arp cache and retrieve its IP address:

    Successfully started, use
    
    vncviewer localhost:23
    
    to see the system console.
    Waiting 30 seconds for the MAC to appear...
    If you have configured RDP, you now should be able to access your Windows:
    
    198.51.100.105

## TODO

I have other scripts that I need to convert to align with the config format used here.
These include:

- Desinfec't in USB stick mode
- Solaris x86_64
- FreeBSD
- OpenWRT

Currently adding support for cloud images of Alma and Rocky has the highest priority.
In case you think something is missing, please contact me or file an issue.
