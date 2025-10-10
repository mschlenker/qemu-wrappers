#!/bin/bash 
# encoding: utf-8
#
# (c) Mattias Schlenker
# License: GPL v2

# Script to convert and run Windows 10 or older in vanilla Qemu/KVM with BIOS partitioning and MBR
# boot. This script does not work with Windows 11 or Windows server 2025. These require GPT, UEF
# and TPM v2.

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

####################### SNIP HERE ############################################

MAC=""
NET=""
TARGETDIR="$1"
WINISO="$2"
DRIVERS="http://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

if [ -z "$TARGETDIR" ] ; then 
    echo "Please specify a target directory as first argument to this script."
    exit 1
fi

if [ "$UID" -lt 1 ] ; then
    echo "Please run this script as unprivileged user."
    exit 0
fi

# Check prerequisites:

neededtools="qemu-img qemu-system-x86_64 remmina"
for tool in $neededtools ; do
    if which $tool > /dev/null ; then
        echo "Found: $tool"
    else
        echo "Missing: $tool, please install $neededtools"
        exit 1
    fi
done

# Check config:

CFG=""
if [ -f "${TARGETDIR}" ] ; then 
    # A file is specified, assume that this is a config file in the folder containing the VM"
    echo "File instead of directory given, splitting..."
    chmod +x "${TARGETDIR}"
    CFG=` basename  "${TARGETDIR}" `
    TARGETDIR=` dirname  "${TARGETDIR}" `
    echo "cfg file: $CFG"
    echo "cfg dir: $TARGETDIR"
fi

if [ -z "$CFG" -a -f "${TARGETDIR}/quickwin10_config.sh" ] ; then
    CFG="quickwin10_config.sh"
elif [ -z "$CFG" -a -f "${TARGETDIR}/config.sh" ] ; then
    CFG="config.sh"
fi

if [ -f "${TARGETDIR}/${CFG}" ] ; then
    echo "Found config: ${TARGETDIR}/${CFG}, sourcing it..."
    . "${TARGETDIR}/${CFG}"
else
    echo "Could not find configuration file, please copy quickwin10_config.sh to the"
    echo "target directory, adjust it and try again."
    exit 1
fi

# Find an unused tap device:
idx=0
while [ -z "$TAPDEV" -a -z "$NET" -a "$idx" -lt 10 ] ; do
    if ip link show dev "vmtap${idx}" | grep 'state DOWN' ; then
        TAPDEV="vmtap${idx}"
    fi
    idx=$(( $idx + 1 ))
done
if [ -z "$TAPDEV" ] ; then
    echo "Could not find a free tap device to connect to. Make sure that devices exist."
    echo "For example you can create them with sudo ./dummybridge.sh."
    exit 1
fi

# Create a random VNC port number:
[ -z "$VNC" ] && VNC=":$((10 + $RANDOM % 90))"

# Exit if neither the disk image exists nor the path to an installation ISO is specified:

if [ -z "$WINISO" ] ; then
    if [ -f "${TARGETDIR}/windows.qcow2" ] ; then
        echo "Found disk image: ${TARGETDIR}/windows.qcow2"
    else
        echo "Could not find disk image: ${TARGETDIR}/windows.qcow2."
        echo "Please specify a Windows installation ISO as second parameter to this script."
        exit 1
    fi
else
    if [ '!' -f "${TARGETDIR}/windows.qcow2" ] ; then
        qemu-img create -f qcow2 "${TARGETDIR}/windows.qcow2" "${SYSSIZE}G"
    fi
fi

# Create the network settings:
if [ -n "$TAPDEV" ] ; then
    if ip link show dev "$TAPDEV" ; then
        echo "Found ${TAPDEV}, you probably will have proper networking..." 
    else
        echo ""
        echo "Could not find ${TAPDEV}, fix by running"
        echo "sudo ./dummybridge.sh"
        echo "Then try again."
        exit 1
    fi
fi

# Skip the arp command if a NET variable was passed:
SKIPARP=0
[ -n "$NET" ] && SKIPARP=1

# Calculate a MAC address from the target directory if none has been given:
if [ -z "$MAC" ] ; then
    MAC="00:08:25:"`echo "$TARGETDIR" | md5sum | awk -F '' '{print $1$2":"$3$4":"$5$6}'`
    echo "MAC=\"$MAC\"" >> "${TARGETDIR}/${CFG}"
fi

# Create a NET variable unless already specified:
if [ -z "$NET" -a -n "$TAPDEV" ] ; then
    NET="-device virtio-net-pci,netdev=net23,mac=${MAC} -netdev tap,id=net23,ifname=${TAPDEV},script=no,downscript=no"
elif [ -z "$NET" ] ; then
    NET="-net nic,model=e1000 -net user,hostfwd=tcp::8000-:80,hostfwd=tcp::2222-:22"
fi

if [ -n "$WINISO" ] ; then
    # Run in installation mode:
    echo "Running in installation mode without networking and with drivers attached."
    echo "You will be connected to localhost${VNC} to finish installation. Then shutdown."
    echo "When done, start again without the ISO file as parameter."
    qemu-system-x86_64 -enable-kvm -smp cpus="$CPUS" -m "$MEM" \
        -drive media=disk,index=0,file="${TARGETDIR}"/windows.qcow2,if=virtio,format=qcow2 \
        -drive media=cdrom,index=1,file="${WINISO}",readonly=on \
        -drive media=cdrom,index=2,file="${DRIVERS}",readonly=on \
        -boot d \
        -pidfile "${TARGETDIR}/qemu.pid" \
        -vnc "$VNC" \
        -usb -usbdevice tablet -k "$KEYBOARD"
        sleep 1
        remmina -c vnc://localhost"${VNC}"
    exit 0
else
    qemu-system-x86_64 -enable-kvm -smp cpus="$CPUS" -m "$MEM" \
        -drive media=disk,index=0,file="${TARGETDIR}"/windows.qcow2,if=virtio,format=qcow2 \
        -drive media=cdrom,index=2,file="${DRIVERS}",readonly=on \
        -pidfile "${TARGETDIR}/qemu.pid" \
        $NET $EXTRAS $DAEMONIZE \
        -vnc "$VNC" \
        -usb -usbdevice tablet -k "$KEYBOARD"
fi

retval="$?"
if [ "$retval" -lt 1 ] ; then
    echo "Successfully started, use"
    echo ""
    echo "    vncviewer localhost${VNC}"
    echo ""
    echo "to see the system console."
    if [ -n "$MAC" -a "$SKIPARP" -lt 1 ] ; then
        echo "Waiting $MACWAIT seconds for the MAC to appear..."
        sleep $MACWAIT
        # ip n | grep "${MAC}"
        IPV4=` ip n | grep "${MAC}" | awk '{print $1}'` 
        if [ -z "$IPV4" ] ; then
            echo "Could not find IPv4 address, you might need to install the guest tools from"
            echo "E:/virtio-win-gt-x64.msi"
        else
            echo "If you have configured RDP, you now should be able to access your Windows:"
            echo ""
            echo "    ${IPV4}"
            echo ""
        fi
    fi
else
    echo ""
    echo "Ooopsi."
    echo "Start failed, please check your configuration."
fi
