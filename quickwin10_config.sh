#!/bin/bash 
# encoding: utf-8
#
# (c) Mattias Schlenker
# License: GPL v2

# Used for disk creation upon first run:

SYSSIZE=64 # Size of the system drive in GB

# General parameters for running, overwrite in quickvirt_config.sh you place into the VM dir.

CPUS=2
MEM=4096
# If you set VNC to an empty string, it will use a random port between 10 and 99
VNC=""
DAEMONIZE="-daemonize" # set to empty string to run in foreground
KEYBOARD="en-us" # Keyboard for VNC

# Networking parameters, simple:

# Default networking requires the dummybridge script being run in advance, thus the vmtap
# interfaces are available and owned by the user running the script.
# Set to an empty string to automatically probe devices from vmtap0 to vmtap9
TAPDEV=""
# You might specify a MAC address, for example generated with randmac:
# MAC="b2:d5:18:8d:01:7b"
# If no MAC is specified, one is created from the name of $TARGETDIR and appended to the config:
# MAC="00:08:25:"`echo $TARGETDIR | md5sum | awk -F '' '{print $1$2":"$3$4":"$5$6}'`
MACWAIT=30 # How many seconds to wait for the MAC to appear to ip n command.

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

# Drivers ISO: Modern Qemu versions can attach ISOs that are provided via HTTP. Default:
# DRIVERS="http://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
# In case your Qemu is too old, download it and specify a local path to overwrite:
# DRIVERS="/home/johndoe/Downloads/stable-virtio/virtio-win.iso"

EXTRAS="" # add additional CLI parameters
