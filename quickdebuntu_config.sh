#!/bin/bash 

# (c) Mattias Schlenker
# License: GPL v2

# Place this file as config.sh or quickdebuntu_config.sh to the folder where the virtual machine
# files should live.

# Parameters for building:

# Only specify one of these! Precedence: Ubuntu, Debian, Devuan
UBUEDITION="noble" # noble: 24.04, jammy: 22.04, focal: 20.04
DEBEDITION="" # trixie: 13, bookworm: 12, bullseye: 11.x Takes precedence over Devuan
DEVEDITION="" # daedalus 5.0 = 12.x, Devuan is Debian without systemd
UBUSERVER="http://archive.ubuntu.com/ubuntu" # You might change to local mirror, but
DEBSERVER="http://deb.debian.org/debian"     # this is less relevant when using caching!
DEVSERVER="http://deb.devuan.org/merged"

# Make sure you have devootstrap scripts or install Devuan debootstrap in case you want to install
# Devuan. See: http://deb.devuan.org/devuan/pool/main/d/debootstrap/
SYSSIZE=64 # Size of the system partition GB
SWAPSIZE=3 # Size of swap GB
TMPSIZE=512 # MB Create a small tmpfs on /tmp, this only affects /etc/fstab, 0 to disable
ROOTFS=btrfs # You might choose ext4 or zfs (haven't tried), btrfs uses snapshots
SSHKEYS="/home/${SUDO_USER}/.ssh/id_ed25519.pub"
# You might specify more than one key, separate them with spaces:
# SSHKEYS="/home/${SUDO_USER}/.ssh/id_ecdsa.pub /home/${SUDO_USER}/.ssh/id_ed25519.pub"
NAMESERVER=8.8.8.8 # Might or might not be overwritten later by DHCP.
HOSTNAME="throwawayvm"
EXTRADEBS=""
ADDUSER="" # "karlheinz" If non-empty a user will be added. This means interaction!
ROOTPASS=0 # Set to 1 to prompt for a root password. This means interaction!
PKGCACHE="" # Set to nonzero length directory name to enable caching of debs
# PKGCACHE="/data/VM/debcache" # Set to nonzero length directory name to enable caching of debs
LINUXIMAGE="" # Set for example to linux-virtual on Ubuntu to install a leaner kernel

# General parameters for running:

CPUS=2
MEM=2048
VNC=":23"
DAEMONIZE="-daemonize" # set to empty string to run in foreground

# Networking parameters, simple:

# Default networking requires the dummybridge script being run in advance, thus the vmtap
# interfaces are available and owned by the user running the script.
TAPDEV="vmtap1"
# You might specify a MAC address, for example generated with randmac:
# MAC="b2:d5:18:8d:01:7b"
# If no MAC is specified, one is created from $HOSTNAME:
# MAC="00:08:25:"`echo $HOSTNAME | md5sum | awk -F '' '{print $1$2":"$3$4":"$5$6}'`
# MACWAIT=15 # How many seconds to wait for the MAC to appear to be able to show the IPv4 address.

# If you are an advanced user, you can specify the network parameters directly. For example a very
# simple configuration that uses user mode networking. For security reasons this is not allowed in
# some corporate environments!!!
#
# This redirects port 8000 on the local machine to 80 on the virtualized Ubuntu
# and port 2222 to 22 on the Ubuntu. This is often sufficient for development:
# NET="-net nic,model=e1000 -net user,hostfwd=tcp::8000-:80,hostfwd=tcp::2222-:22"
#
# Or you can specify  different device models, down scripts or multiple interfaces:
# NET="-device virtio-net-pci,netdev=network3,mac=00:16:17:12:ac:ae -netdev tap,id=network3,ifname=vmtap1,script=no,downscript=no"

EXTRAS="" # add additional CLI parameters
