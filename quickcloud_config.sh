#!/bin/bash 
# encoding: utf-8
#
# (c) Mattias Schlenker
# License: GPL v2

# Run Ubuntu and Debian cloud-init images in vanilla Qemu/KVM.

# Parameters for setting up the image:

DISTRO="ubuntu" # Currently must be one of almalinux/debian/rocky/ubuntu
VERSION="noble" # Can be any supported, names (lower case) for debian/ubuntu, numbers for almalinux/rocky
SSHKEYS="/home/${USER}/.ssh/id_ed25519.pub"
RESIZE=32 # Resize to 32 G
HOSTNAME="cloud"
# Do not generate a seed image, instead use an existing one
# SEED="/path/to/some/seed.iso"

# General parameters for running, overwrite in quickvirt_config.sh you place into the VM dir.

CPUS=2
MEM=4096
VNC=":23"
DAEMONIZE="-daemonize" # set to empty string to run in foreground
LOGMEIN=1 # Login via SSH instead of showing the command to login

# Networking parameters, simple:

# Default networking requires the dummybridge script being run in advance, thus the vmtap
# interfaces are available and owned by the user running the script.
# Set to an empty string to automatically probe devices from vmtap0 to vmtap9
TAPDEV=""
# You might specify a MAC address, for example generated with randmac:
# MAC="b2:d5:18:8d:01:7b"
# If no MAC is specified, one is created from the name of $TARGETDIR and appended to the config:
# MAC="00:08:25:"`echo $TARGETDIR | md5sum | awk -F '' '{print $1$2":"$3$4":"$5$6}'`
MACWAIT=15 # How many seconds to wait for the MAC to appear to ip n command.

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
