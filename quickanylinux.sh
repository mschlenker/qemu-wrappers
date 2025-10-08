#!/bin/bash 
# encoding: utf-8
#
# (c) Mattias Schlenker
# License: GPL v2

# Script to run Ubuntu and Debian cloud-init images in vanilla Qemu/KVM.

# Parameters for setting up the image:

DISKSIZE=32

# General parameters for running, overwrite in quickvirt_config.sh you place into the VM dir.

CPUS=2
MEM=4096
CPU="-cpu host" # For maximum compatibility
VNC=":23"
DAEMONIZE="-daemonize" # set to empty string to run in foreground

# Networking parameters, simple:

# Default networking requires the dummybridge script being run in advance, thus the vmtap
# interfaces are available and owned by the user running the script.
TAPDEV="vmtap1"
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

####################### SNIP HERE ############################################

MAC=""
NET=""
TARGETDIR="$1"
INSTALLISO="$2"
SEED=""

if [ -z "$TARGETDIR" ] ; then 
    echo "Please specify a target directory as first argument to this script."
    exit 1
fi

if [ "$UID" -lt 1 ] ; then
    echo "Please run this script as unprivileged user."
    exit 0
fi

# Check prerequisites:

neededtools="qemu-img qemu-system-x86_64"
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

if [ -z "$CFG" -a -f "${TARGETDIR}/quickanylinux_config.sh" ] ; then
    CFG="quickanylinux_config.sh"
elif [ -z "$CFG" -a -f "${TARGETDIR}/config.sh" ] ; then
    CFG="config.sh"
fi

if [ -f "${TARGETDIR}/${CFG}" ] ; then
    echo "Found config: ${TARGETDIR}/${CFG}, sourcing it..."
    . "${TARGETDIR}/${CFG}"
else
    echo "Could not find configuration file, please copy quickanylinux_config.sh to the"
    echo "target directory, adjust it and try again."
    exit 1
fi

if [ -f "${TARGETDIR}/disk.qcow2" ] ; then
    echo "Found disk image: ${TARGETDIR}/disk.qcow2..."
elif [ -z "$INSTALLISO" ] ; then
    # Exit if no disk image is present and no install ISO has been passed.
    echo "For the first run provide an installation ISO (can be a http:// URL) as second parameter."
    exit 1
else
    # Create the disk image:
    qemu-img create -f qcow2 "${TARGETDIR}/disk.qcow2" "${DISKSIZE}G"
fi

# Copy the OVMF files:

for f in OVMF_VARS_4M.fd OVMF_CODE_4M.fd ; do
    if [ -f "${TARGETDIR}/${f}" ] ; then
        echo "Found ${TARGETDIR}/${f}"
    else
        cp -v /usr/share/OVMF/${f} ${TARGETDIR}/${f}
        retval="$?"
        if [ "$retval" -gt 0 ] ; then
            echo "Could not find OVMF files, you might want to install the package ovmf or"
            echo "manually place OVMF_VARS.fd and OVMF_CODE.fd in ${TARGETDIR}"
            exit 1
        fi
    fi
done

# Create the network settings and run:
if [ -n "$TAPDEV" ] ; then
    if ip a show dev "$TAPDEV" ; then
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

if [ -n "$INSTALLISO" ] ; then
    echo "Running in installation mode, booting from the supplied ISO image."
    echo "Connect via VNC to localhost${VNC} to finish installation, then shutdown."
    echo "When done, start again without the ISO file as parameter."
    # We are in installation mode, boot from ISO:
    qemu-system-x86_64 -enable-kvm -smp cpus="$CPUS" -m "$MEM" \
        -drive file="${TARGETDIR}/OVMF_CODE_4M.fd",if=pflash,format=raw,readonly=on \
        -drive file="${TARGETDIR}/OVMF_VARS_4M.fd",if=pflash,format=raw \
        -drive file="${TARGETDIR}/disk.qcow2",if=virtio,format=qcow2 \
        -drive media=cdrom,index=1,file="${INSTALLISO}",readonly=on \
        -boot d \
        -pidfile "${TARGETDIR}/qemu.pid" \
        $CPU $NET $EXTRAS \
        -vnc "$VNC"
        exit 0
else
    qemu-system-x86_64 -enable-kvm -smp cpus="$CPUS" -m "$MEM" \
        -drive file="${TARGETDIR}/OVMF_CODE_4M.fd",if=pflash,format=raw,readonly=on \
        -drive file="${TARGETDIR}/OVMF_VARS_4M.fd",if=pflash,format=raw \
        -drive file="${TARGETDIR}/disk.qcow2",if=virtio,format=qcow2 \
        -pidfile "${TARGETDIR}/qemu.pid" \
        $CPU $NET $DAEMONIZE $EXTRAS \
        -vnc "$VNC"
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
            echo "Could not find IPv4 address, you might need to adjust the network configuration in the console."
        else
            echo "You should now be able to run"
            echo ""
            echo "    ssh username@${IPV4}"
            echo ""
        fi
    fi
else
    echo ""
    echo "Ooopsi."
    echo "Start failed, please check your configuration."
fi
