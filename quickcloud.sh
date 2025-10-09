#!/bin/bash 
# encoding: utf-8
#
# (c) Mattias Schlenker
# License: GPL v2

# Script to run Ubuntu and Debian cloud-init images in vanilla Qemu/KVM.

# Parameters for setting up the image:

DISTRO="ubuntu" # Currently must be one of ubuntu/debian
VERSION="noble" # Can be any supported, tested only with noble/jammy and trixie/bookworm so far
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
TAPDEV="vmtap1"
# You might specify a MAC address, for example generated with randmac:
# MAC="b2:d5:18:8d:01:7b"
# If no MAC is specified, one is created from the $HOSTNAME and appended to the config:
# MAC="00:08:25:"`echo $HOSTNAME | md5sum | awk -F '' '{print $1$2":"$3$4":"$5$6}'`
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
SEED=""
SNAPSHOT="_fresh_image"

if [ -z "$TARGETDIR" ] ; then 
    echo "Please specify a target directory as first argument to this script."
    exit 1
fi

if [ "$UID" -lt 1 ] ; then
    echo "Please run this script as unprivileged user."
    exit 0
fi

# Check prerequisites:

neededtools="qemu-img qemu-system-x86_64 xorriso wget"
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

if [ -z "$CFG" -a -f "${TARGETDIR}/quickcloud_config.sh" ] ; then
    CFG="quickcloud_config.sh"
elif [ -z "$CFG" -a -f "${TARGETDIR}/config.sh" ] ; then
    CFG="config.sh"
fi

if [ -f "${TARGETDIR}/${CFG}" ] ; then
    echo "Found config: ${TARGETDIR}/${CFG}, sourcing it..."
    . "${TARGETDIR}/${CFG}"
else
    echo "Could not find configuration file, please copy quickcloud_config.sh to the"
    echo "target directory, adjust it and try again."
    exit 1
fi

# If no seed image is specified and no seed image is found, create one:
if [ -z "$SEED" ] ; then
    if [ -f "${TARGETDIR}/seed.iso" ] ; then
        echo "Found ${TARGETDIR}/seed.iso..."
    else
        mkdir "${TARGETDIR}/.seed"
        touch "${TARGETDIR}/.seed/meta-data"
        if [ "$DISTRO" = debian -o "$DISTRO" = ubuntu ] ; then
            touch "${TARGETDIR}/.seed/network-data"
        fi
        echo '#cloud-config' > "${TARGETDIR}/.seed/user-data"
        echo "hostname: ${HOSTNAME}" >> "${TARGETDIR}/.seed/user-data"
        echo "create_hostname_file: true" >> "${TARGETDIR}/.seed/user-data"
        echo 'ssh_authorized_keys:' >> "${TARGETDIR}/.seed/user-data"
        for f in $SSHKEYS ; do
            k=` cat $f`
            echo -n '  - ' >> "${TARGETDIR}/.seed/user-data"
            echo "$k" >> "${TARGETDIR}/.seed/user-data"
        done
        xorriso -as mkisofs -joliet -V CIDATA -o "${TARGETDIR}/seed.iso" -r "${TARGETDIR}/.seed"
    fi
    SEED="${TARGETDIR}/seed.iso"
fi

URL=''
# Create the URL and download the image if not already present:
if [ -f "${TARGETDIR}/disk.qcow2" ] ; then
    echo "Found ${TARGETDIR}/disk.qcow2..."
else
    case $DISTRO in
        almalinux)
            URL="https://repo.almalinux.org/almalinux/${VERSION}/cloud/x86_64/images/AlmaLinux-${VERSION}-GenericCloud-latest.x86_64.qcow2"
        ;;
        debian)
            NUM=13
            [ "$VERSION" = "trixie" ] && NUM=13
            [ "$VERSION" = "bookworm" ] && NUM=12
            [ "$VERSION" = "bullseye" ] && NUM=11
            URL="https://cdimage.debian.org/images/cloud/${VERSION}/latest/debian-${NUM}-generic-amd64.qcow2"
        ;;
        rocky)
            URL="http://dl.rockylinux.org/pub/rocky/${VERSION}/images/x86_64/Rocky-${VERSION}-GenericCloud-Base.latest.x86_64.qcow2"
        ;;
        ubuntu)
            URL="https://cloud-images.ubuntu.com/${VERSION}/current/${VERSION}-server-cloudimg-amd64.img"
        ;;
        *)
            echo "Unsupported distro ${DISTRO}. Allowed: debian, rocky, ubuntu."
            echo "Exiting."
            exit 1
        ;;
    esac
    wget -O "${TARGETDIR}/disk.qcow2" "$URL"
    if [ "$?" -gt 0 ] ; then
        rm -f "${TARGETDIR}/disk.qcow2"
        echo "Download of ${URL} failed. Please check."
        exit 1
    fi
    qemu-img resize "${TARGETDIR}/disk.qcow2" "${RESIZE}G"
fi

# Check for the snapshot or create one:
snapfound=0
if [ -n "$SNAPSHOT" ] ; then
    qemu-img snapshot -l "${TARGETDIR}/disk.qcow2" | grep -e '^[0-9]' | awk '{print $2}' | while read snapname ; do
        [ "$snapname" = "$SNAPSHOT" ] && snapfound=1
    done
    if [ "$snapfound" -lt 1 ] ; then
        echo "Creating snapshot: $SNAPSHOT"
        qemu-img snapshot -c "$SNAPSHOT" "${TARGETDIR}/disk.qcow2"
    fi
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

qemu-system-x86_64 -enable-kvm -cpu host -smp cpus="$CPUS" -m "$MEM" \
    -drive file="${TARGETDIR}/OVMF_CODE_4M.fd",if=pflash,format=raw,readonly=on \
    -drive file="${TARGETDIR}/OVMF_VARS_4M.fd",if=pflash,format=raw \
    -drive file="${TARGETDIR}/disk.qcow2",if=virtio,format=qcow2 \
    -drive file="${SEED}",index=1,media=cdrom,readonly=on \
    -pidfile "${TARGETDIR}/qemu.pid" \
    $NET $DAEMONIZE $EXTRAS \
    -vnc "$VNC"

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
        elif [ "$LOGMEIN" -gt 0 ] ; then
            ssh "${DISTRO}@${IPV4}"
        else
            echo "You should now be able to run"
            echo ""
            echo "    ssh ${DISTRO}@${IPV4}"
            echo ""
        fi
    fi
        
else 	
    echo ""
    echo "Ooopsi."
    echo "Start failed, please check your configuration."
fi
