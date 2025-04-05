#!/bin/bash
#VARIABLES
if [ -z $1 ] ; then
        disk_list=$(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk"{print $1,$2}')

        menu_options=()
        while read -r name size; do
            menu_options+=("/dev/$name" "$size")
        done <<< "$disk_list"
	
        DEVICE=$(whiptail --title "Select a Disk" --menu "Choose a disk:" 20 60 10 "${menu_options[@]}" 3>&1 1>&2 2>&3)
else
	DEVICE=$1
fi

set -e # Exit on error
cd /tmp
MULTISTRAP_URL=http://ftp.debian.org/debian/pool/main/m/multistrap/multistrap_2.2.11_all.deb

CACHE_FOLDER=/home/$SUDO_USER/.multistrap
LOG=${CACHE_FOLDER}/multistrap.log
ERR=${CACHE_FOLDER}/multistrap.err
ROOTFS=/tmp/installing-rootfs
RECOVERYFS=/tmp/recovery-rootfs
CLONEZILLA_KEYBOARD=latam
APT_CONFIG="`command -v apt-config 2> /dev/null`"
eval $("$APT_CONFIG" shell APT_TRUSTEDDIR 'Dir::Etc::trustedparts/d')

INCLUDES_DEB="apt initramfs-tools zstd gnupg systemd \
xfce4 task-xfce-desktop xorg dbus-x11 gvfs cups system-config-printer thunar-volman synaptic xarchiver vlc \
fonts-dejavu-core fonts-droid-fallback fonts-font-awesome fonts-lato fonts-liberation2 fonts-mathjax fonts-noto-mono fonts-opensymbol fonts-quicksand fonts-symbola fonts-urw-base35 gsfonts \
task-web-server task-ssh-server task-laptop qterminal qterminal-l10n \
sudo vim wget curl \
network-manager iputils-ping util-linux iproute2 bind9-host isc-dhcp-client network-manager-gnome xfce4-power-manager xfce4-power-manager-plugins \
pavucontrol pulseaudio \
grub2-common grub-efi grub-efi-amd64 \
fonts-liberation libasound2 libnspr4 libnss3 libvulkan1 firefox-esr firefox-esr-l10n-es-ar \
console-data console-setup locales \
ecryptfs-utils rsync lsof cryptsetup \
libxslt1.1"
#Kernel, initrd, basics
#xfce (xfce4-goodies removed), x11, trashbin, printers, external devices, synaptic, xarchiver, vlc
#fonts
#command line tools
#network
#sound
#boot
#chrome deps and firefox
#languaje and terminal tty languaje
#home and swap encryption
#libreoffice dependency

#default themes
#gcr gnome-keyring gnome-keyring-pkcs11 libpam-gnome-keyring libgail-common libgail18 libsoup-gnome2.4-1 libxml2 pinentry-gnome3 policykit-1-gnome xdg-desktop-portal-gtk \
#adwaita-icon-theme gnome-accessibility-themes gnome-icon-theme gnome-themes-extra gnome-themes-extra-data tango-icon-theme \

DEBIAN_VERSION=bookworm
INCLUDES_BACKPORTS="linux-image-amd64/${DEBIAN_VERSION}-backports"
REPOSITORY_DEB="http://deb.debian.org/debian/"
REPOSITORY_CHROME="https://dl.google.com/linux/chrome/deb/"


echo "Installing dependencies for this script ---------------------"
        apt update							 >/dev/null 2>&1
	apt install --fix-broken -y					 >/dev/null 2>&1
        apt install dosfstools parted gnupg2 unzip \
		             wget curl openssh-server -y		 >/dev/null 2>&1
	systemctl start sshd						 >/dev/null 2>&1
	wget --show-progress -q -O /tmp/multistrap.deb ${MULTISTRAP_URL}
	apt install /tmp/multistrap.deb -y				 >/dev/null 2>&1

echo "============================================================="
echo "
Installing on Device ${DEVICE}
	- Debian ${DEBIAN_VERSION}
        - Backport kernel for newer HW compatibility
	- Latest Libreoffice
        - Latest Google Chrome 
	- Latest XFCE 
	- Latest Firefox ESR
	- Latest Clonezilla recovery

To Follow extra details use: 
	tail -F $LOG or
	tail -F $ERR

For remote access during installation, you can connect via ssh" 
ip -br a | grep -v ^lo
grep iso /proc/cmdline >/dev/null && \
echo ISO Detected. Hint username is \"user\" and password is \"live\"

echo "============================================================="

echo "Unmounting ${DEVICE}  ----------------------------------------"
        umount ${DEVICE}*                       2>/dev/null || true
        umount ${ROOTFS}/dev/pts                2>/dev/null || true
        umount ${ROOTFS}/dev                    2>/dev/null || true
        umount ${ROOTFS}/proc                   2>/dev/null || true
        umount ${ROOTFS}/run                    2>/dev/null || true
        umount ${ROOTFS}/sys                    2>/dev/null || true
        umount ${ROOTFS}/tmp                    2>/dev/null || true
        umount ${ROOTFS}/boot/efi               2>/dev/null || true
        umount          /var/cache/apt/archives 2>/dev/null || true
        umount ${ROOTFS}/var/cache/apt/archives 2>/dev/null || true
        umount ${ROOTFS}                        2>/dev/null || true
        umount ${RECOVERYFS}                    2>/dev/null || true
        umount ${CACHEFOLDER}                   2>/dev/null || true


echo "Full reparted or not? ---------------------------------------"
	REPARTED=yes
	blkid | grep ${DEVICE}2 | grep CLONEZILLA >/dev/null && \
	blkid | grep ${DEVICE}3 | grep LINUX      >/dev/null && \
	blkid | grep ${DEVICE}4 | grep RESOURCES  >/dev/null && \
	REPARTED=no
	echo ${REPARTED}

if [ "$REPARTED" == yes ] ; then
	echo "Setting partition table to GPT (UEFI) -----------------------"
		parted ${DEVICE} --script mktable gpt                         > /dev/null 2>&1

	echo "Creating EFI partition --------------------------------------"
		parted ${DEVICE} --script mkpart ESP fat32 1MiB 901MiB        > /dev/null 2>&1
		parted ${DEVICE} --script set 1 esp on                        > /dev/null 2>&1

	echo "Creating Clonezilla partition -------------------------------"
		parted ${DEVICE} --script mkpart CLONEZILLA ext4 901MiB 12901MiB > /dev/null 2>&1

	echo "Calculating OS partition size -------------------------------"
		DISK_SIZE=$(parted ${DEVICE} --script unit MiB print | awk '/Disk/ {print $3}' | tr -d 'MiB')
		START_X_PART=$((12901 + 1))
		END_X_PART=$((DISK_SIZE - 20480)) 

	echo "Creating OS partition ---------------------------------------"
		parted ${DEVICE} --script mkpart LINUX ext4 ${START_X_PART}MiB ${END_X_PART}MiB >/dev/null 2>&1

	echo "Creating Resources partition --------------------------------"
		parted ${DEVICE} --script mkpart RESOURCES ext4 ${END_X_PART}MiB 100% >/dev/null 2>&1
		sleep 2
fi

echo "Formating partitions ----------------------------------------"
[ "$REPARTED" == yes ] && mkfs.vfat -n EFI ${DEVICE}1           > /dev/null 2>&1
[ "$REPARTED" == no  ] && mkfs.ext4 -L CLONEZILLA ${DEVICE}2    > /dev/null 2>&1
[ "$REPARTED" == no  ] && mkfs.ext4 -L LINUX ${DEVICE}3         > /dev/null 2>&1
[ "$REPARTED" == yes ] && mkfs.ext4 -L RESOURCES ${DEVICE}4     > /dev/null 2>&1

echo "Mounting OS partition ---------------------------------------"
        mkdir -p ${ROOTFS}                                      > /dev/null 2>&1
        mount ${DEVICE}3 ${ROOTFS}                              > /dev/null 2>&1
	
echo "Mounting Recovery partition ---------------------------------"
        mkdir -p ${RECOVERYFS}                                  > /dev/null 2>&1
        mount ${DEVICE}2 ${RECOVERYFS}                          > /dev/null 2>&1

echo "Creating cache folder ---------------------------------------"
        mkdir -vp ${CACHE_FOLDER}
        chown $SUDO_USER: -R ${CACHE_FOLDER}
	mount ${DEVICE}4 ${CACHE_FOLDER}
        mkdir -p ${ROOTFS}/var/cache/apt/archives               > /dev/null 2>&1
        mount --bind ${CACHE_FOLDER} ${ROOTFS}/var/cache/apt/archives
	touch $LOG
	touch $ERR

echo "Cleaning cache packages if necesary -------------------------"
if [ ! -z "$(ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d)" ] ; then
		echo ---This packages have more than one version.
		ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d | while read line
        	do ls ${CACHE_FOLDER}/${line}* 
		done
		echo ---Removing older versions so multistrap wont fail
		ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d | while read line
        	do rm -v ${CACHE_FOLDER}/${line}* 
		done
	fi

echo "Downloading Google Chrome keyrings --------------------------"
        echo ---------Creating Directories in ${ROOTFS}
        mkdir -p ${ROOTFS}/etc/apt/sources.list.d/
        mkdir -p ${ROOTFS}${APT_TRUSTEDDIR}  

        echo ---------Installing chrome keyring in ${ROOTFS}
        wget -qO - https://dl.google.com/linux/linux_signing_key.pub \
        | awk '/-----BEGIN PGP PUBLIC KEY BLOCK-----/ {inBlock++} inBlock == 2 {print} /-----END PGP PUBLIC KEY BLOCK-----/ && inBlock == 2 {exit}' \
        | gpg --dearmor > ${ROOTFS}${APT_TRUSTEDDIR}google-chrome.gpg
        echo deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main    > ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list

echo "Downloading lastest clonezilla ------------------------------"
	BASEURL_CLONEZILLA=https://sourceforge.net/projects/clonezilla/files/latest/download
	DOWNLOAD_DIR_CLONEZILLA=${CACHE_FOLDER}/Clonezilla
	mkdir -p $DOWNLOAD_DIR_CLONEZILLA 2>/dev/null
	URL_CLONEZILLA=$(curl -S $BASEURL_CLONEZILLA 2>/dev/null|grep https| cut -d \" -f 2)
	FILE_CLONEZILLA=$(echo $URL_CLONEZILLA | cut -f8 -d\/ | cut -f1 -d \?)
	wget --show-progress -qcN -O ${DOWNLOAD_DIR_CLONEZILLA}/${FILE_CLONEZILLA} ${URL_CLONEZILLA}

echo "Extracting clonezilla ---------------------------------------"
	unzip ${DOWNLOAD_DIR_CLONEZILLA}/${FILE_CLONEZILLA} -d ${RECOVERYFS} >>$LOG 2>>$ERR
	cp -p ${RECOVERYFS}/boot/grub/grub.cfg ${RECOVERYFS}/boot/grub/grub.cfg.old
	sed -i '/menuentry[^}]*{/,/}/d' ${RECOVERYFS}/boot/grub/grub.cfg
	sed -i '/submenu[^}]*{/,/}/d' ${RECOVERYFS}/boot/grub/grub.cfg
	mv ${RECOVERYFS}/live ${RECOVERYFS}/live-hd

echo "Creating grub.cfg for clonezilla ----------------------------"
set +e
fdisk -l | grep nvme0n1 | wc -l | grep 5                         >/dev/null
if [ "$?" == "0" ] ; then 
	BASE=nvme0n1p
else
	fdisk -l | grep sda | wc -l | grep 5                     >/dev/null
	if [ "$?" == "0" ]; then
		BASE=sda
       	else
		fdisk -l | grep xvda | wc -l | grep 5            >/dev/null
		if [ "$?" == "0" ]; then
			BASE=xvda
		else	
			fdisk -l | grep vda | wc -l | grep 5     >/dev/null
			if [ "$?" == "0" ]; then
				BASE=vda
			fi
		fi
	fi
fi
echo '
##PREFIX##
menuentry  --hotkey=s "Salvar imagen"{
  search --set -f /live-hd/vmlinuz
  linux /live-hd/vmlinuz boot=live union=overlay username=user config components noquiet noswap edd=on nomodeset noprompt noeject locales= keyboard-layouts=%%KEYBOARD%% ocs_prerun="mount /dev/%%BASE%%2 /home/partimag" ocs_live_run="/usr/sbin/ocs-sr -q2 -c -j2 -z1p -i 4096 -sfsck -scs -enc -p poweroff saveparts debian_image %%BASE%%1 %%BASE%%3" ocs_postrun="/home/partimag/clean" ocs_live_extra_param="" keyboard-layouts="US" ocs_live_batch="no" vga=788 toram=live,syslinux,EFI ip= net.ifnames=0  nosplash i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1
  initrd /live-hd/initrd.img
}
##SUFIX##
menuentry  --hotkey=r "Restaurar imagen"{
  search --set -f /live-hd/vmlinuz
  linux /live-hd/vmlinuz boot=live union=overlay username=user config components noquiet noswap edd=on nomodeset noprompt noeject locales= keyboard-layouts=%%KEYBOARD%% ocs_prerun="mount /dev/%%BASE%%2 /home/partimag" ocs_live_run="ocs-sr -g auto -e1 auto -e2 -t -r -j2 -c -k -scr -p reboot restoreparts debian_image %%BASE%%1 %%BASE%%3" ocs_live_extra_param="" keyboard-layouts="US" ocs_live_batch="no" vga=788 toram=live,syslinux,EFI ip= net.ifnames=0  nosplash i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1
  initrd /live-hd/initrd.img
}

' >> ${RECOVERYFS}/boot/grub/grub.cfg

echo "
mkdir /mnt/%%BASE%%3 /mnt/%%BASE%%4 2>/dev/null
mount /dev/%%BASE%%3 /mnt/%%BASE%%3 2>/dev/null
mount /dev/%%BASE%%4 /mnt/%%BASE%%4 2>/dev/null

cd /mnt/%%BASE%%3/
rm -rf \$(ls /mnt/%%BASE%%3/ | grep -v boot)
rm -rf /mnt/%%BASE%%4/*

sed -i 's/timeout=30/timeout=0/g'									/mnt/%%BASE%%3/boot/grub/grub.cfg
sed -i 's/timeout=5/timeout=0/g'									/mnt/%%BASE%%3/boot/grub/grub.cfg
sed -i '/### BEGIN \/etc\/grub.d\/10_linux ###/,/### END \/etc\/grub.d\/10_linux ###/d'			/mnt/%%BASE%%3/boot/grub/grub.cfg
sed -i '/### BEGIN \/etc\/grub.d\/30_uefi-firmware ###/,/### END \/etc\/grub.d\/30_uefi-firmware ###/d' /mnt/%%BASE%%3/boot/grub/grub.cfg
sed -i '/##PREFIX##/,/##SUFIX##/d' /home/partimag/boot/grub/grub.cfg
umount /dev/%%BASE%%3
umount /dev/%%BASE%%4
"> ${RECOVERYFS}/clean
chmod +x ${RECOVERYFS}/clean

sed -i 's/%%KEYBOARD%%/'$CLONEZILLA_KEYBOARD'/g' ${RECOVERYFS}/boot/grub/grub.cfg
sed -i 's/%%BASE%%/'$BASE'/g'                    ${RECOVERYFS}/boot/grub/grub.cfg
sed -i 's/%%BASE%%/'$BASE'/g'                    ${RECOVERYFS}/clean
set -e

echo "Creating configuration file for multistrap ------------------"
echo "[General]
arch=amd64
directory=${ROOTFS}
cleanup=false
unpack=true
omitdebsrc=true
bootstrap=Debian GoogleChrome Backports
aptsources=Debian 

[Debian]
packages=${INCLUDES_DEB}
source=${REPOSITORY_DEB}
keyring=debian-archive-keyring
suite=${DEBIAN_VERSION}
components=main contrib non-free non-free-firmware

[Backports]
packages=${INCLUDES_BACKPORTS}
source=${REPOSITORY_DEB}
suite=${DEBIAN_VERSION}-backports
components=main
noauth=true

[GoogleChrome]
arch=amd64
packages=google-chrome-stable
source=${REPOSITORY_CHROME}
suite=stable
noauth=true

components=main" > multistrap.conf

echo "Running multistrap ------------------------------------------"
        SILENCE="Warning: unrecognised value 'no' for Multi-Arch field in|multistrap-googlechrome.list"
        multistrap -f multistrap.conf >$LOG 2> >(grep -vE "$SILENCE" > $ERR)
        #FIXES
        if [ -f ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list ] ; then
                rm ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list
        fi

echo "Configurating the network -----------------------------------"
        cp /etc/resolv.conf ${ROOTFS}/etc/resolv.conf
        mkdir -p ${ROOTFS}/etc/network/interfaces.d/            > /dev/null 2>&1
        echo "allow-hotplug enp1s0"                          > ${ROOTFS}/etc/network/interfaces.d/enp1s0
        echo "iface enp1s0 inet dhcp"                       >> ${ROOTFS}/etc/network/interfaces.d/enp1s0
        echo "debian-$(date +'%Y-%m-%d')"                    > ${ROOTFS}/etc/hostname
        echo "127.0.0.1       localhost"                     > ${ROOTFS}/etc/hosts
        echo "127.0.1.1       debian-$(date +'%Y-%m-%d')"   >> ${ROOTFS}/etc/hosts
        echo "::1     localhost ip6-localhost ip6-loopback" >> ${ROOTFS}/etc/hosts
        echo "ff02::1 ip6-allnodes"                         >> ${ROOTFS}/etc/hosts
        echo "ff02::2 ip6-allrouters"                       >> ${ROOTFS}/etc/hosts
        touch ${ROOTFS}/ImageDate.$(date +'%Y-%m-%d')

echo "Mounting EFI partition --------------------------------------"
        mkdir -p ${ROOTFS}/boot/efi
        mount ${DEVICE}1 ${ROOTFS}/boot/efi

echo "Generating fstab --------------------------------------------"
        root_uuid="$(blkid | grep ^$DEVICE | grep ' LABEL="LINUX" ' | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        efi_uuid="$(blkid  | grep ^$DEVICE | grep ' LABEL="EFI" '   | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        FILE=${ROOTFS}/etc/fstab
        echo "$root_uuid /        ext4  defaults 0 1"  > $FILE
        echo "$efi_uuid  /boot/efi vfat defaults 0 1" >> $FILE

echo "Getting ready for chroot ------------------------------------"
        mount --bind /dev ${ROOTFS}/dev
        mount -t devpts /dev/pts ${ROOTFS}/dev/pts
        mount --bind /proc ${ROOTFS}/proc
        mount --bind /run  ${ROOTFS}/run
        mount -t sysfs sysfs ${ROOTFS}/sys
        mount -t tmpfs tmpfs ${ROOTFS}/tmp

echo "Downloading Libreoffice -------------------------------------"
        # Variables
        LO_LANG=es  # Idioma para la instalación
        DOWNLOAD_DIR_LO=${CACHE_FOLDER}/Libreoffice
        LIBREOFFICE_URL="https://download.documentfoundation.org/libreoffice/stable/"
        VERSION_LO=$(wget -qO- $LIBREOFFICE_URL | grep -oP '[0-9]+(\.[0-9]+)+' | sort -V | tail -1)

        mkdir -p $DOWNLOAD_DIR_LO >/dev/null 2>&1
        wget -qN ${LIBREOFFICE_URL}${VERSION_LO}/deb/x86_64/LibreOffice_${VERSION_LO}_Linux_x86-64_deb.tar.gz -P $DOWNLOAD_DIR_LO
        wget -qN ${LIBREOFFICE_URL}${VERSION_LO}/deb/x86_64/LibreOffice_${VERSION_LO}_Linux_x86-64_deb_langpack_$LO_LANG.tar.gz -P $DOWNLOAD_DIR_LO
        tar -xzf $DOWNLOAD_DIR_LO/LibreOffice_${VERSION_LO}_Linux_x86-64_deb.tar.gz -C $DOWNLOAD_DIR_LO
        tar -xzf $DOWNLOAD_DIR_LO/LibreOffice_${VERSION_LO}_Linux_x86-64_deb_langpack_$LO_LANG.tar.gz -C $DOWNLOAD_DIR_LO

echo "Setting Keyboard maps for non graphical console -------------"
        # FIX DEBIAN BUG
        keyboard_maps=$(curl -s https://mirrors.edge.kernel.org/pub/linux/utils/kbd/ | grep tar.gz | cut -d'"' -f2 | tail -n1)
        wget --show-progress -qcN -O $keyboard_maps https://mirrors.edge.kernel.org/pub/linux/utils/kbd/$keyboard_maps 
	where_am_i=$PWD
        cd /tmp
        tar xzvf $where_am_i/$keyboard_maps   >>$LOG 2>>$ERR
        cd kbd-*/data/keymaps/
        mkdir -p ${ROOTFS}/usr/share/keymaps/
        cp -r * ${ROOTFS}/usr/share/keymaps/  >>$LOG 2>>$ERR

echo "Setting Keyboard maps for everything else -------------------"
	echo 'XKBLAYOUT="latam"' > ${ROOTFS}/etc/default/keyboard

echo "Creating recovery -------------------------------------------"
echo '#!/bin/sh
exec tail -n +3 $0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the 'exec tail' line above.

# Particion para restaurar
menuentry "Restaurar" {
   insmod chain
   search --no-floppy --set=root -f /live-hd/vmlinuz
   chainloader ($root)/EFI/boot/grubx64.efi
}'> ${ROOTFS}/etc/grub.d/40_custom



echo "Entering chroot ---------------------------------------------"
        echo "#!/bin/bash
        export DOWNLOAD_DIR_LO=/var/cache/apt/archives/Libreoffice
        export VERSION_LO=${VERSION_LO}
        export LO_LANG=es  # Idioma para la instalación
        export LC_ALL=C LANGUAGE=C LANG=C
        export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
	export LOG=/var/cache/apt/archives/multistrap.log
	export ERR=/var/cache/apt/archives/multistrap.err


        PROC_NEEDS_UMOUNT=0
        if [ ! -e /proc/uptime ]; then
                mount proc -t proc /proc
                PROC_NEEDS_UMOUNT=1
        fi

        echo Setting up additional packages ------------------------------
        tasksel install ssh-server laptop xfce --new-install                                    >>\$LOG 2>>\$ERR
        apt remove --purge xfce4-terminal -y                                                    >>\$LOG 2>>\$ERR


        #Installing Libreoffice in backgroupd
        dpkg -i \$(find \$DOWNLOAD_DIR_LO/ -type f -name \*.deb)				>>\$LOG 2>>\$ERR &
        pid_LO=$!

        echo Installing grub ---------------------------------------------
        update-initramfs -c -k all                                                              >>\$LOG 2>>\$ERR
        grub-install --target=x86_64-efi --efi-directory=/boot/efi \
	      --bootloader-id=debian --recheck --no-nvram --removable  				>>\$LOG 2>>\$ERR 
        update-grub                                                                             >>\$LOG 2>>\$ERR

        echo Installing LibreOffice and its language pack ----------------
        wait $pid_LO
        apt install --fix-broken -y                                                             >>\$LOG 2>>\$ERR
        echo LibreOffice \$VERSION_LO installation done.

        echo Setting languaje --------------------------------------------
        debconf-set-selections <<< \"tzdata                  tzdata/Areas                                              select America\"
        debconf-set-selections <<< \"tzdata                  tzdata/Zones/America                                      select Argentina/Buenos_Aires\"
        debconf-set-selections <<< \"console-data  console-data/keymap/policy      select  Select keymap from full list\"
        debconf-set-selections <<< \"console-data  console-data/keymap/full        select  la-latin1\"
        debconf-set-selections <<< \"console-data  console-data/bootmap-md5sum     string  102c60ee2ad4688765db01cfa2d2da21\"
        debconf-set-selections <<< \"console-setup console-setup/charmap47 select  UTF-8\"
        debconf-set-selections <<< \"console-setup   console-setup/codeset47 select  Guess optimal character set\"
        debconf-set-selections <<< \"console-setup   console-setup/fontface47        select  Fixed\"
        debconf-set-selections <<< \"console-setup   console-setup/fontsize-fb47     select  8x16\"
        debconf-set-selections <<< \"console-setup   console-setup/fontsize  string  8x16\"
        debconf-set-selections <<< \"console-setup   console-setup/fontsize-text47   select  8x16\"
        debconf-set-selections <<< \"keyboard-configuration  keyboard-configuration/model    select  PC genérico 105 teclas\"
        debconf-set-selections <<< \"keyboard-configuration        keyboard-configuration/layout   select  Spanish (Latin American)\"
        debconf-set-selections <<< \"keyboard-configuration        keyboard-configuration/layoutcode       string  latam\"
        debconf-set-selections <<< \"keyboard-configuration        keyboard-configuration/variant  select  Spanish (Latin American)\"
        debconf-set-selections <<< \"keyboard-configuration  keyboard-configuration/altgr    select  The default for the keyboard layout\"
        debconf-set-selections <<< \"keyboard-configuration  keyboard-configuration/compose  select  No compose key\"
        debconf-set-selections <<< \"locales       locales/locales_to_be_generated multiselect     es_AR.UTF-8 UTF-8\"

        rm -f /etc/localtime /etc/timezone
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive tzdata			>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-data		>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-setup		>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive keyboard-configuration 	>>\$LOG 2>>\$ERR
        sed -i '/# es_AR.UTF-8 UTF-8/s/^# //g' /etc/locale.gen
        locale-gen 											>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive locales 			>>\$LOG 2>>\$ERR
	export LANG=es_AR.UTF-8
        update-locale LANG=es_AR.UTF-8									>>\$LOG 2>>\$ERR
	localectl set-locale LANG=es_AR.UTF-8								>>\$LOG 2>>\$ERR
        locale												>>\$LOG 2>>\$ERR
	echo LANG=es_AR.UTF-8 >> /etc/environment
        if [ \$PROC_NEEDS_UMOUNT -eq 1 ]; then
                umount /proc
        fi
        exit" > ${ROOTFS}/root/chroot.sh
        chmod +x ${ROOTFS}/root/chroot.sh
        chroot ${ROOTFS} /bin/bash /root/chroot.sh

        echo Adding local admin ------------------------------------------
        read -p "What username do you want for local_admin_user ?: " username
        chroot ${ROOTFS} useradd -d /home/$username -c local_admin_user -G sudo -m -s /bin/bash $username
        
	REPEAT=yes
	while [ "$REPEAT" == "yes" ] ; do
		read -sp "What password do you want for local_admin_user ${username} ?" password && echo "."
		read -sp "to be sure, please repeat the password: " password2                    && echo "."
		if [ "$password" == "$password2" ] ; then
			echo ${username}:${password} | chroot ${ROOTFS} chpasswd                 && echo "."
			REPEAT=no
		else
			echo "ERROR: Passwords entered dont match"
		fi
	done
	
	echo "
	echo Adding local user -------------------------------------------
        read -p \"What username do you want for local_encrypted_user ?: \" username
        sudo useradd -d /home/\$username -c local_encrypted_user -m -s /bin/bash \$username
        
        sudo passwd \$username
        if [ \"\$?\" != \"0\" ] ; then echo Please repeat the password....; sudo passwd \$username ; fi

        echo Encrypting home ---------------------------------------------
	echo --Enabling encryption
		sudo modprobe ecryptfs
		echo ecryptfs | sudo tee -a /etc/modules-load.d/modules.conf

	echo --Migrating home
		sudo ecryptfs-migrate-home -u \$username 2>&1 | grep -i passphrase
		sudo rm -rf /home/\${username}.*

	echo --Login via ssh to complete encryption
		ssh  -o StrictHostKeyChecking=no \${username}@localhost ls -la | grep -i password 
		
	echo --bye!!
		sleep 3
		sudo reboot
	" > ${ROOTFS}/usr/local/bin/useradd-encrypt
	chmod +x ${ROOTFS}/usr/local/bin/useradd-encrypt

	

echo "Unmounting ${DEVICE} -----------------------------------------"
        umount ${DEVICE}*                         2>/dev/null || true
        umount ${ROOTFS}/dev/pts                  2>/dev/null || true
        umount ${ROOTFS}/dev                      2>/dev/null || true
        umount ${ROOTFS}/proc                     2>/dev/null || true
        umount ${ROOTFS}/run                      2>/dev/null || true
        umount ${ROOTFS}/sys                      2>/dev/null || true
        umount ${ROOTFS}/tmp                      2>/dev/null || true
        umount ${ROOTFS}/boot/efi                 2>/dev/null || true
        umount ${ROOTFS}/var/cache/apt/archives   2>/dev/null || true
        umount ${ROOTFS}                          2>/dev/null || true
        umount ${RECOVERYFS}                      2>/dev/null || true

echo "END of the road!! keep up the good work ---------------------"
