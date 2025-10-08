#!/bin/bash 

# Script for debootstrapping and running an Ubuntu, choose any recent Ubuntu.
# If installing a newer Ubuntu than the one you are running this script on,
# make sure you have installed the most recent debootstrap!
#
# (c) Mattias Schlenker
# License: GPL v2

# Defaults, overwrite in config.sh or quickdebuntu_config.sh in the target directory:

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
ARCH="amd64"
TARGETDIR="$1"

if [ -z "$TARGETDIR" ] ; then 
	echo "Please specify a target directory as first argument to this script."
	exit 1
fi

if [ "$UID" -lt 1 -a -f "${TARGETDIR}/.bootstrap.success" ] ; then
    echo "Bootstrap already seems to have succeeded."
    echo "Please run this script now as unprivileged user."
    exit 0
elif [ -f "${TARGETDIR}/.bootstrap.success" ] ; then
    echo "Bootstrap already seems to have succeeded. Trying to start..."
elif [ "$UID" -gt 0 ] ; then
	echo "Please run as root to install."
	exit 1
fi

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

if [ -z "$CFG" -a -f "${TARGETDIR}/quickdebuntu_config.sh" ] ; then
    CFG="quickdebuntu_config.sh"
elif [ -z "$CFG" -a -f "${TARGETDIR}/config.sh" ] ; then
    CFG="config.sh"
fi

if [ -f "${TARGETDIR}/${CFG}" ] ; then
	echo "Found config: ${TARGETDIR}/${CFG}, sourcing it..."
	. "${TARGETDIR}/${CFG}"
else
	echo "Could not find configuration file, please copy quickdebuntu_config.sh to the"
    echo "target directory, adjust it and try again."
    exit 1
fi

if [ -n "$PKGCACHE" ]; then
	if [ -n "$UBUEDITION" ] ; then
		mkdir -p "${PKGCACHE}/ubuntu/archives"
	elif [ -n "$DEBEDITION" ] ; then
		mkdir -p "${PKGCACHE}/debian/archives"
	else
		# Well that's not perfect, everything above the base
		# system should be taken from matching Debian!
		mkdir -p "${PKGCACHE}/devuan/archives"
	fi
fi

DISKSIZE=$(( $SYSSIZE + $SWAPSIZE ))
freeloop=""

# If a file .bootstrap.success is present, assume installation was OK.
# In this case do not check for tools:
neededtools="parted dmsetup kpartx debootstrap mkfs.btrfs qemu-system-x86_64"
if [ -f "${TARGETDIR}/.bootstrap.success" ] ; then
	echo "Found ${TARGETDIR}/.bootstrap.success, skipping checks for tools..."
else
	for tool in $neededtools ; do
		if which $tool > /dev/null ; then
			echo "Found: $tool"
		else
			echo "Missing: $tool, please install $neededtools"
			exit 1
		fi
	done
	for key in $SSHKEYS ; do
		if [ '!' -f "$key" ] ; then
			echo "Missing SSH key $key, you would not be able to login."
			exit 1
		fi
	done
	# Check whether using a fixed path really suits all Debian derivatives?
	CODENAME=""
	if [ -n "$UBUEDITION" ] ; then
		CODENAME="$UBUEDITION"
	elif [ -n "$DEBEDITION" ] ; then
		CODENAME="$DEBEDITION"
	else
		CODENAME="$DEVEDITION"
	fi
	if [ -z "$CODENAME" ] ; then
		echo "Please specify either UBUEDITION, DEBEDITION or DEVEDITION. Exiting."
		exit 1
	fi
	if [ '!' -f "/usr/share/debootstrap/scripts/${CODENAME}" ] ; then
		echo "Bootstrap script missing for ${CODENAME}. Exiting."
		exit 1
	fi
fi
# Create a hard disk and partition it:
mkdir -p "${TARGETDIR}"
if [ -f "${TARGETDIR}/disk.img" ] ; then
	echo "Disk exists, skipping creation of disk..."
else
	dd if=/dev/zero bs=1M of="${TARGETDIR}/disk.img" count=1 seek=$(( ${DISKSIZE} * 1024 - 1 ))
	freeloop=` losetup -f `
	losetup $freeloop "${TARGETDIR}/disk.img"
	# Partition the disk
	parted -s $freeloop mklabel msdos
	parted -s $freeloop unit B mkpart primary ext4  $(( 1024 ** 2 )) $(( 1024 ** 3 * $SYSSIZE - 1 ))
	parted -s $freeloop unit B mkpart primary ext4  $(( 1024 ** 3 * $SYSSIZE )) 100%
	parted -s $freeloop unit B set 1 boot on
	parted -s $freeloop unit B print
fi

# Mount and debootstrap:

if [ -f "${TARGETDIR}/.bootstrap.success" ] ; then
	echo "Already bootstrapped, skipping debootstrap stage..."
else
	if [ -z "$freeloop" ] ; then
		freeloop=` losetup -f `
		losetup $freeloop "${TARGETDIR}/disk.img"
	fi
	sync
	sleep 5
	kpartx -a $freeloop
	mkdir -p "${TARGETDIR}/.target"
	# mkfs.ext4 /dev/mapper/${freeloop#/dev/}p1
	mkfs.${ROOTFS} /dev/mapper/${freeloop#/dev/}p1
	# When using btrfs create a subvolume _install and use as default to make versioning easier
	MOUNTOPTS="defaults"
	case ${ROOTFS} in 
		btrfs)
			mount -o rw /dev/mapper/${freeloop#/dev/}p1 "${TARGETDIR}/.target"
			btrfs subvolume create "${TARGETDIR}/.target/_install"
            btrfs subvolume set-default "${TARGETDIR}/.target/_install"
			umount /dev/mapper/${freeloop#/dev/}p1
			MOUNTOPTS='subvol=_install'
		;;
	esac
	mkswap /dev/mapper/${freeloop#/dev/}p2
	mount -o rw,"${MOUNTOPTS}" /dev/mapper/${freeloop#/dev/}p1 "${TARGETDIR}/.target"
	mkdir -p "${TARGETDIR}/.target/boot"
	# mount -o rw /dev/mapper/${freeloop#/dev/}p1 "${TARGETDIR}/.target/boot"
	# mkdir -p "${TARGETDIR}/.target/boot/modules"
	# mkdir -p "${TARGETDIR}/.target/boot/firmware"
	# mkdir -p "${TARGETDIR}/.target/lib"
	# ln -s /boot/modules "${TARGETDIR}/.target/lib/modules"
	# ln -s /boot/firmware "${TARGETDIR}/.target/lib/firmware"
	# This is the installation!
	archivedir=""
	if [ -n "$PKGCACHE" ]; then
		if [ -n "$UBUEDITION" ] ; then
			archivedir="${PKGCACHE}/ubuntu/archives"
		elif [ -n "$DEBEDITION" ] ; then
			archivedir="${PKGCACHE}/debian/archives"
		else
			archivedir="${PKGCACHE}/devuan/archives"
		fi
	fi
	mkdir -p "${TARGETDIR}/.target"/var/cache/apt/archives
	if [ -n "$PKGCACHE" ]; then
		mount --bind "$archivedir" "${TARGETDIR}/.target"/var/cache/apt/archives
	else
		mount -t tmpfs -o size=4G,mode=0755 tmpfs "${TARGETDIR}/.target"/var/cache/apt/archives
	fi
	if [ -n "$UBUEDITION" ] ; then
		debootstrap --arch $ARCH $UBUEDITION "${TARGETDIR}/.target" $UBUSERVER
	elif [ -n "$DEBEDITION" ] ; then
		debootstrap --arch $ARCH $DEBEDITION "${TARGETDIR}/.target" $DEBSERVER
	else
		debootstrap --arch $ARCH $DEVEDITION "${TARGETDIR}/.target" $DEVSERVER
	fi
	mount -t proc none "${TARGETDIR}/.target"/proc
	mount --bind /sys "${TARGETDIR}/.target"/sys
	mount --bind /dev "${TARGETDIR}/.target"/dev
	mount -t devpts none "${TARGETDIR}/.target"/dev/pts
	echo 'en_US.UTF-8 UTF-8' > "${TARGETDIR}/.target"/etc/locale.gen
    mkdir -p "${TARGETDIR}/.target"/etc/initramfs-tools
    echo btrfs >> "${TARGETDIR}/.target"/etc/initramfs-tools/modules
    echo ext4 >> "${TARGETDIR}/.target"/etc/initramfs-tools/modules
	chroot "${TARGETDIR}/.target" locale-gen
	chroot "${TARGETDIR}/.target" shadowconfig on
	if [ -n "$UBUEDITION" ] ; then
	
cat > "${TARGETDIR}/.target"/etc/apt/sources.list << EOF

deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} main restricted
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} main restricted
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates main restricted
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates main restricted
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} universe
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} universe
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates universe
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates universe
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} multiverse
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION} multiverse
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates multiverse
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-updates multiverse
deb http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-backports main restricted universe multiverse
deb-src http://de.archive.ubuntu.com/ubuntu/ ${UBUEDITION}-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${UBUEDITION}-security main restricted
deb-src http://security.ubuntu.com/ubuntu ${UBUEDITION}-security main restricted
deb http://security.ubuntu.com/ubuntu ${UBUEDITION}-security universe
deb-src http://security.ubuntu.com/ubuntu ${UBUEDITION}-security universe
deb http://security.ubuntu.com/ubuntu ${UBUEDITION}-security multiverse
deb-src http://security.ubuntu.com/ubuntu ${UBUEDITION}-security multiverse

EOF

	elif [ -n "$DEBEDITION" ] ; then

cat > "${TARGETDIR}/.target"/etc/apt/sources.list << EOF

deb http://deb.debian.org/debian/ ${DEBEDITION} main contrib non-free
deb https://security.debian.org/debian-security ${DEBEDITION}-security main contrib non-free
deb http://deb.debian.org/debian/ ${DEBEDITION}-updates main contrib non-free
deb http://deb.debian.org/debian ${DEBEDITION}-proposed-updates main contrib non-free
deb http://deb.debian.org/debian-security/ ${DEBEDITION}-security main contrib non-free
# deb http://deb.debian.org/debian/ ${DEBEDITION}-backports main contrib non-free

EOF
	
	else
cat > "${TARGETDIR}/.target"/etc/apt/sources.list << EOF

deb http://deb.devuan.org/merged ${DEVEDITION}          main
deb http://deb.devuan.org/merged ${DEVEDITION}-updates  main
deb http://deb.devuan.org/merged ${DEVEDITION}-security main
	
EOF

	fi
	# Devuan users shall manually adjust their sources.list, since they mix in matching Debian! 
	
	chroot "${TARGETDIR}/.target" apt-get -y install ca-certificates
	chroot "${TARGETDIR}/.target" apt-get -y update
    [ -z "$LINUXIMAGE" ] && LINUXIMAGE=linux-image-generic
	chroot "${TARGETDIR}/.target" apt-get -y install screen $LINUXIMAGE openssh-server \
		rsync btrfs-progs openntpd ifupdown net-tools locales grub-pc os-prober
    chroot "${TARGETDIR}/.target" apt-get -y install grub-gfxpayload-lists
	chroot "${TARGETDIR}/.target" apt-get -y dist-upgrade
	extlinux -i "${TARGETDIR}/.target/boot"
	if [ -z "$UBUEDITION" ] ; then
		kernel=` ls "${TARGETDIR}/.target/boot/" | grep vmlinuz- | tail -n 1 `
		initrd=` ls "${TARGETDIR}/.target/boot/" | grep initrd.img- | tail -n 1 `
		ln -s $kernel "${TARGETDIR}/.target/boot/vmlinuz"
		ln -s $initrd "${TARGETDIR}/.target/boot/initrd.img"
		chroot "${TARGETDIR}/.target" locale-gen
	fi
	for d in $EXTRADEBS ; do
		chroot "${TARGETDIR}/.target" apt-get -y install $d
	done
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="net.ifnames=0"' >> "${TARGETDIR}/.target/etc/default/grub"
    chroot "${TARGETDIR}/.target" update-grub
    chroot "${TARGETDIR}/.target" grub-install --recheck --target=i386-pc --boot-directory=/boot $freeloop
	rm "${TARGETDIR}/.target"/etc/resolv.conf
	echo "nameserver $NAMESERVER" > "${TARGETDIR}/.target"/etc/resolv.conf
	echo "$HOSTNAME" > "${TARGETDIR}/.target"/etc/hostname
	# echo btrfs >> "${TARGETDIR}/.target"/etc/initramfs-tools/modules # Brauchen wir das?
	mkdir -m 0600 "${TARGETDIR}/.target/root/.ssh"
	for key in $SSHKEYS ; do
		[ -f "$key" ] && cat "$key" >> "${TARGETDIR}/.target/root/.ssh/authorized_keys"
	done
	#eval ` blkid -o udev /dev/mapper/${freeloop#/dev/}p1 `
	#UUID_BOOT=$ID_FS_UUID
	eval ` blkid -o udev /dev/mapper/${freeloop#/dev/}p2 `
	UUID_SWAP=$ID_FS_UUID
	eval ` blkid -o udev /dev/mapper/${freeloop#/dev/}p1 `
	UUID_ROOT=$ID_FS_UUID
cat > "${TARGETDIR}/.target"/etc/fstab << EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=${UUID_ROOT} /               ${ROOTFS}   ${MOUNTOPTS} 0       1
UUID=${UUID_SWAP} none            swap        sw       0       0

EOF

if [ "$TMPSIZE" -gt 0 ] ; then
	echo "tmpfs /tmp tmpfs size=${TMPSIZE}M 0 0" >> "${TARGETDIR}/.target"/etc/fstab
fi

cat > "${TARGETDIR}/.target"/etc/network/interfaces << EOF
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
# allow-hotplug eth0
auto eth0
iface eth0 inet dhcp

EOF

cat > "${TARGETDIR}/.target"/etc/rc.local << EOF
#!/bin/bash

ping -c 1 $NAMESERVER
exit 0

EOF

	chmod 0755 "${TARGETDIR}/.target"/etc/rc.local
	if [ -n "$ADDUSER" ] ; then
		echo "Adding user $ADDUSER"
		chroot "${TARGETDIR}/.target" adduser "$ADDUSER"
	fi
	if [ "$ROOTPASS" -gt 0 ] ; then
		echo "Adding a root password for console login"
		chroot "${TARGETDIR}/.target" passwd
	fi
	for d in dev/pts dev sys proc boot var/cache/apt/archives ; do umount -f "${TARGETDIR}/.target"/$d ; done 
	umount "${TARGETDIR}/.target"
	# dmsetup remove /dev/mapper/${freeloop#/dev/}p3
	dmsetup remove /dev/mapper/${freeloop#/dev/}p2
	dmsetup remove /dev/mapper/${freeloop#/dev/}p1
	losetup -d $freeloop && touch "${TARGETDIR}/.bootstrap.success"
    
    chown -R "${SUDO_USER}:${SUDO_USER}" "${TARGETDIR}"
fi

if [ "$UID" -lt 1 -a -f "${TARGETDIR}/.bootstrap.success" ] ; then
    echo "Please run this script now as unprivileged user, e.g. without sudo."
    exit 0
fi

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

# Calculate a MAC address from the hostname if none has been given:
[ -z "$MAC" ] && MAC="00:08:25:"`echo $HOSTNAME | md5sum | awk -F '' '{print $1$2":"$3$4":"$5$6}'`

# Create a NET variable unless already specified:
if [ -z "$NET" -a -n "$TAPDEV" ] ; then
    NET="-device virtio-net-pci,netdev=net23,mac=${MAC} -netdev tap,id=net23,ifname=${TAPDEV},script=no,downscript=no"
elif [ -z "$NET" ] ; then
    NET="-net nic,model=e1000 -net user,hostfwd=tcp::8000-:80,hostfwd=tcp::2222-:22"
fi

# apt install qemu-system-x86 qemu 
qemu-system-x86_64 -enable-kvm -smp cpus="$CPUS" -m "$MEM" -drive \
	file="${TARGETDIR}"/disk.img,if=virtio,format=raw \
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
            echo "Could not find IPv4 address, please investigate..."
        else
            echo "You should now be able to run"
            echo ""
            echo "    ssh root@${IPV4}"
            echo ""
        fi
    fi
        
else 	
	echo ""
	echo "Ooopsi."
	echo "Start failed, please check your configuration."
fi
