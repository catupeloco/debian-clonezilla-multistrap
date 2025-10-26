#!/bin/bash
SCRIPT_DATE=20251025-2354
echo ---------------------------------------------------------------------------
echo "now     "$(env TZ=America/Argentina/Buenos_Aires date +'%Y%m%d-%H%M') 
echo "script  "$SCRIPT_DATE
echo ---------------------------------------------------------------------------
sleep 7
reset # Re-Set terminal for multiple runs

set -e # Exit on error

LOG=/tmp/notebook.log
ERR=/tmp/notebook.err
exec &> >(tee -a "$LOG")

echo "Installing dependencies for this script ---------------------"
	cd /tmp
        apt update							 >/dev/null 2>&1
	apt install --fix-broken -y					 >/dev/null 2>&1
        apt install dosfstools parted gnupg2 unzip \
        wget curl openssh-server mmdebstrap xmlstarlet -y		 >/dev/null 2>&1
	systemctl start sshd						 >/dev/null 2>&1

#####################################################################################################
#Selections
#####################################################################################################
disk_list=$(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk"{print $1,$2}')
menu_options=()
while read -r name size; do
      menu_options+=("/dev/$name" "$size")
done <<< "$disk_list"
DEVICE=$(whiptail --title "Disk selection" --menu "Choose a disk from below and press enter to begin:" 20 60 10 "${menu_options[@]}" 3>&1 1>&2 2>&3)
#####################################################################################################
MIRROR_CLONEZILLA=$(whiptail --title "Select Clonezilla mirror" --menu "Choose one option:" 20 60 10 \
       "Official_Fast" "NCHC - Taiwan" \
       "Official_Slow" "SourceForge" \
       3>&1 1>&2 2>&3)
#####################################################################################################
FIREFOX_PACKAGE=$(whiptail --title "Select Firefox Package" --menu "Choose one option:" 20 60 10 \
       "firefox     firefox-l10n-es-ar    " "Firefox Rapid Release" \
       "firefox-esr firefox-esr-l10n-es-ar" "Firefox ESR          " \
       3>&1 1>&2 2>&3)
#####################################################################################################
username=$(whiptail --title "Local admin creation" --inputbox "Type a username:" 20 60  3>&1 1>&2 2>&3)
REPEAT=yes
while [ "$REPEAT" == "yes" ] ; do
	password=$( whiptail --title "Local admin creation" --passwordbox "Type a password:"                  20 60  3>&1 1>&2 2>&3)
	password2=$(whiptail --title "Local admin creation" --passwordbox "Just in case type it again:"       20 60  3>&1 1>&2 2>&3)
	if [ "$password" == "$password2" ] ; then
		REPEAT=no
	else
		#echo "ERROR: Passwords entered dont match"
		    whiptail --title "Local admin creation" \
			     --msgbox "ERROR: Passwords dont match, try again" 20 60  3>&1 1>&2 2>&3
	fi
done
#####################################################################################################
PART_OP_PERCENTAGE=$(whiptail --title "Overprovisioning partition size selecction" \
	                      --menu "Choose a recomended percentage or Other to enter manually:" 20 60 10 \
	                               7 "% More Read Intensive " \
				       25 "% More Write Intensive "  \
				       "x" "% Other Percentage" 3>&1 1>&2 2>&3)
if [ "$PART_OP_PERCENTAGE" == "x" ] ; then
	REPEAT=yes
	while [ "$REPEAT" == "yes" ] ; do
		PART_OP_PERCENTAGE=$(whiptail --title "Overprovisioning partition size selecction" --inputbox "Enter a positive integer, lower than 100:" 20 60  3>&1 1>&2 2>&3)
		if [[ "$PART_OP_PERCENTAGE" =~ ^[0-9]+$ ]] && (( "$PART_OP_PERCENTAGE" < 100 )); then
			REPEAT=no
		else
			whiptail --title "Overprovisioning partition size selection" --msgbox "ERROR: Wrong input, try again" 20 60  3>&1 1>&2 2>&3
		fi
	done
fi

#####################################################################################################
#VARIABLES 
#####################################################################################################

CACHE_FOLDER=/tmp/resources-fs
ROOTFS=/tmp/os-rootfs

PART_EFI_END=901
PART_CZ_END=12901

WIFI_DOMAIN="https://git.kernel.org"
WIFI_URL="${WIFI_DOMAIN}/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain" 
WIFI_MAX_PARALLEL=10

KEYBOARD_FIX_URL="https://mirrors.edge.kernel.org/pub/linux/utils/kbd/"
KEYBOARD_MAPS=$(curl -s ${KEYBOARD_FIX_URL} | grep tar.gz | cut -d'"' -f2 | tail -n1)

RECOVERYFS=/tmp/recovery-rootfs
CLONEZILLA_KEYBOARD=latam
DOWNLOAD_DIR_CLONEZILLA=${CACHE_FOLDER}/Clonezilla
BASEURL_CLONEZILLA_FAST="https://free.nchc.org.tw/clonezilla-live/stable/"
BASEURL_CLONEZILLA_SLOW="https://sourceforge.net/projects/clonezilla/files/latest/download"

DOWNLOAD_DIR_LO=${CACHE_FOLDER}/Libreoffice
LIBREOFFICE_URL="https://download.documentfoundation.org/libreoffice/stable/"
LO_LANG=es 
VERSION_LO=$(wget -qO- $LIBREOFFICE_URL | grep -oP '[0-9]+(\.[0-9]+)+' | sort -V | tail -1)
LIBREOFFICE_MAIN=${LIBREOFFICE_URL}${VERSION_LO}/deb/x86_64/LibreOffice_${VERSION_LO}_Linux_x86-64_deb.tar.gz
LIBREOFFICE_LAPA=${LIBREOFFICE_URL}${VERSION_LO}/deb/x86_64/LibreOffice_${VERSION_LO}_Linux_x86-64_deb_langpack_$LO_LANG.tar.gz
LIBREOFFICE_HELP=${LIBREOFFICE_URL}${VERSION_LO}/deb/x86_64/LibreOffice_${VERSION_LO}_Linux_x86-64_deb_helppack_$LO_LANG.tar.gz
LIBREOFFICE_UPDS="https://github.com/catupeloco/install-libreoffice-from-web"

#DRAWIO_URL=$(wget -qO- https://github.com/jgraph/drawio-desktop/releases/latest | cut -d \" -f2 | grep deb | grep amd64)
# TODAY : 10/25/2025 latest release (28.2.8) has not linux version yet, so I fix previous release url
DRAWIO_URL="https://github.com/jgraph/drawio-desktop/releases/download/v28.2.5/drawio-amd64-28.2.5.deb"
DRAWIO_FOLDER=${CACHE_FOLDER}/Draw.io
DRAWIO_DEB=${DRAWIO_URL##*/}

FLATPAK_REPO="https://dl.flathub.org/repo/flathub.flatpakrepo"

THIS_SCRIPT="https://github.com/catupeloco/debian-clonezilla-multistrap.git"

APT_CONFIG="`command -v apt-config 2> /dev/null`"
eval $("$APT_CONFIG" shell APT_TRUSTEDDIR 'Dir::Etc::trustedparts/d')

# NOTE: Fictional variables below are only for title proposes ########################################
INCLUDES_DEB="${RAMDISK_AND_SYSTEM_PACKAGES} \
apt initramfs-tools zstd gnupg systemd linux-image-amd64 login flatpak \
${XFCE_AND_DESKTOP_APPLICATIONS} \
xfce4 xorg dbus-x11 	   gvfs cups thunar-volman  system-config-printer    xarchiver vlc flameshot  mousepad                                       \
lm-sensors 		   qbittorrent  	    qpdfview		     keepassxc-full 	      light-locker             gnome-keyring         \
xfce4-battery-plugin       xfce4-clipman-plugin     xfce4-cpufreq-plugin     xfce4-cpugraph-plugin    xfce4-datetime-plugin    xfce4-diskperf-plugin \
xfce4-fsguard-plugin       xfce4-genmon-plugin      xfce4-mailwatch-plugin   xfce4-netload-plugin     xfce4-places-plugin      xfce4-sensors-plugin  \
xfce4-smartbookmark-plugin xfce4-systemload-plugin  xfce4-timer-plugin       xfce4-verve-plugin       xfce4-wavelan-plugin     xfce4-weather-plugin  \
xfce4-xkb-plugin           xfce4-whiskermenu-plugin xfce4-dict xfce4-notifyd xfce4-taskmanager        xfce4-indicator-plugin   xfce4-mpc-plugin      \
thunar-archive-plugin      thunar-media-tags-plugin ntfs-3g \
${FONTS_PACKAGES_AND_THEMES}  \
fonts-dejavu-core fonts-droid-fallback fonts-font-awesome fonts-lato fonts-liberation2 fonts-mathjax fonts-noto-mono fonts-opensymbol fonts-quicksand \
fonts-symbola fonts-urw-base35 gsfonts arc-theme \
task-xfce-desktop task-ssh-server task-laptop qterminal \
${COMMANDLINE_TOOLS} \
sudo vim wget curl dialog nano file less pciutils lshw usbutils bind9-dnsutils fdisk file git zenity build-essential ncdu \
whiptail \
${CRON_TOOLS} \
anacron cron cron-daemon-common \
${NETWORK_PACKAGES_AND_DRIVERS} \
blueman bluetooth bluez bluez-firmware bluez-alsa-utils \
bind9-host dfu-util dnsmasq-base ethtool ifupdown iproute2 iputils-ping isc-dhcp-client \
network-manager network-manager-gnome powermgmt-base util-linux wpasupplicant xfce4-power-manager xfce4-power-manager-plugins \
firmware-iwlwifi firmware-ath9k-htc firmware-linux-free firmware-ath9k-htc firmware-realtek \
network-manager-l10n \
${AUDIO_PACKAGES} \
pavucontrol pulseaudio audacity pulseaudio-module-bluetooth xfce4-pulseaudio-plugin \
alsa-topology-conf alsa-ucm-conf alsa-utils sound-icons \
${BOOT_PACKAGES}  \
grub2-common grub-efi grub-efi-amd64 \
${FIREFOX_AND_CHROME_DEPENDENCIES}  \
fonts-liberation libasound2 libnspr4 libnss3 libvulkan1 \
${LANGUAGE_PACKAGES}  \
console-data console-setup locales \
${SPANISH} \
task-spanish task-spanish-desktop qterminal-l10n \
${REMOTE_ACCESS} \
x11vnc ssvnc remmina remmina-plugin-rdp remmina-plugin-vnc remmina-plugin-x2go remmina-plugin-secret x2goclient \
${ENCRYPTION_PACKAGES}  \
ecryptfs-utils rsync lsof cryptsetup \
${LIBREOFFICE_DEPENDENCIES}  \
libxslt1.1 \
${UNATTENDED_UPGRADES_PACKAGES}  \
unattended-upgrades apt-utils apt-listchanges \
${VIRTUALIZATION_PACKAGES}  \
qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients bridge-utils virtinst libvirt-daemon virt-manager spice-vdagent \
qemu-guest-agent \
${OBS_STUDIO} \
ffmpeg obs-studio" #https://ppa.launchpadcontent.net/obsproject/obs-studio/ubuntu/pool/main/o/obs-studio/

DEBIAN_VERSION=trixie
REPOSITORY_DEB="http://deb.debian.org/debian/"
  SECURITY_DEB="http://security.debian.org/debian-security"
  SNAPSHOT_DEB="https://snapshot.debian.org/archive/debian/20250827T210843Z/"

# https://www.google.com/linuxrepositories/
#wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo tee /etc/apt/trusted.gpg.d/google.asc >/dev/null
 # NOTE: On systems with older versions of apt (i.e. versions prior to 1.4), the ASCII-armored
 # format public key must be converted to binary format before it can be used by apt.d
#wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/google.gpg >/dev/null
CHROME_REPOSITORY="https://dl.google.com/linux/chrome/deb/" 
CHROME_KEY="https://dl.google.com/linux/linux_signing_key.pub"
CHROME_TRUSTED="/etc/apt/trusted.gpg.d/google.asc"

# https://support.mozilla.org/es/kb/Instalar-firefox-linux#w_instalar-el-paquete-deb-de-firefox-para-distribuciones-basadas-en-debian
# wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
FIREFOX_REPOSITORY="https://packages.mozilla.org/apt"
FIREFOX_KEY="https://packages.mozilla.org/apt/repo-signing-key.gpg"
FIREFOX_TRUSTED="/etc/apt/keyrings/packages.mozilla.org.asc"

# https://www.spotify.com/es/download/linux/
# curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
# echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
SPOTIFY_REPOSITORY="https://repository.spotify.com"
SPOTIFY_KEYS="https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg"
SPOTIFY_TRUSTED="/etc/apt/trusted.gpg.d/spotify.gpg"

# https://apt.syncthing.net/
# sudo mkdir -p /etc/apt/keyrings
# sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
# echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" | sudo tee /etc/apt/sources.list.d/syncthing.list
# 
SYNCTHING_REPOSITORY="https://apt.syncthing.net"
SYNCTHING_KEYS="https://syncthing.net/release-key.gpg"
SYNCTHING_TRUSTED="/etc/apt/keyrings/syncthing-archive-keyring.gpg"
SYNCTHING_SERV_RESUME_TARGET="/etc/systemd/system/syncthing-resume.service" 
SYNCTHING_SERV_RESUME_URL="https://raw.githubusercontent.com/syncthing/syncthing/main/etc/linux-systemd/system/syncthing-resume.service"
SYNCTHING_SERV_ARROBA_TARGET="/etc/systemd/system/syncthing@.service"
SYNCTHING_SERV_ARROBA_URL="https://raw.githubusercontent.com/syncthing/syncthing/main/etc/linux-systemd/system/syncthing%40.service"

LOCALIP=$(ip -br a | grep -v ^lo | awk '{print $3}' | cut -d\/ -f1)

########################################################################################################################################################

# for clear screen on tty (clear doesnt work)
printf "\033c"

echo "============================================================="
echo "Installing on Device ${DEVICE} with ${username} as local admin
	- Debian ${DEBIAN_VERSION} with :
		- XFCE.
		- Firefox ESR.
		- OBS Studio.
		- Unattended upgrades.
		- Optional : encrypted home.
        	- Virtual Machine Manager (KVM/QEMU).
        	- Wifi drivers.
	- External latest :
		- Libreoffice.
		- Google Chrome. 
		- Clonezilla recovery.
		- Spotify.
	- With Overprovisioning partition ${PART_OP_PERCENTAGE} %
	Script Version=${SCRIPT_DATE}"

echo "To Follow extra details use: 
	tail -F $LOG or Ctrl + Alt + F2
	tail -F $ERR or Ctrl + Alt + F3"

grep iso /proc/cmdline >/dev/null && \
echo "For remote access during installation, you can connect via ssh
	---Connect via: ssh user@$LOCALIP
	---password is \"live\""

echo "============================================================="

echo "Inicializing logs tails -------------------------------------"
	touch $LOG
	touch $ERR
set +e
	if [ -z "$(ps fax | grep -v grep | grep tail | grep $LOG)" ] ; then
		setsid bash -c 'exec tail -f '$LOG' <> /dev/tty2 >&0 2>&1' &
		setsid bash -c 'exec tail -f '$ERR' <> /dev/tty3 >&0 2>&1' &
	fi
set -e


echo "Unmounting ${DEVICE}  ----------------------------------------"
        umount ${DEVICE}*                       2>/dev/null || true
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
        umount ${CACHEFOLDER}                   2>/dev/null || true


echo "Comparing partitions target scheme vs actual schema ---------"

	echo "---Calculating OS partition size"
		DISK_SIZE=$(parted ${DEVICE} --script unit MiB print | awk '/Disk/ {print $3}' | tr -d 'MiB')
		PART_OP_SIZE=$((DISK_SIZE / 100 * PART_OP_PERCENTAGE))
		PART_OS_START=$((PART_CZ_END + 1))
		PART_OS_END=$((DISK_SIZE - PART_OP_SIZE)) 
	
	echo "---Labels test"
		LABELS_MATCH=no
		blkid | grep ${DEVICE}2 | grep CLONEZILLA >/dev/null && \
		blkid | grep ${DEVICE}3 | grep LINUX      >/dev/null && \
		blkid | grep ${DEVICE}4 | grep RESOURCES  >/dev/null && \
		LABELS_MATCH=yes && echo ------They DO match || echo ------They DON\'T match

	echo "---Sizes test"
		PART_OP_SIZE_REAL=$( parted ${DEVICE} --script unit MiB print | awk '$1 == "4" {print $4}' | tr -d 'MiB')
		PART_OS_START_REAL=$(parted ${DEVICE} --script unit MiB print | awk '$1 == "3" {print $2}' | tr -d 'MiB')
		PART_OS_END_REAL=$(  parted ${DEVICE} --script unit MiB print | awk '$1 == "3" {print $3}' | tr -d 'MiB')

		if [ "$((PART_OP_SIZE - 1))" == "$PART_OP_SIZE_REAL" ] && [ "$PART_OS_START" == "$PART_OS_START_REAL" ] && [ "$PART_OS_END" == "$PART_OS_END_REAL" ] ; then
			echo ------They DO match
			SIZES_MATCH=yes
		else
			echo ------They DON\'T match
			SIZES_MATCH=no
		fi

	echo "---Reparted? :"
		if [ "$LABELS_MATCH" == "yes" ] && [ "$SIZES_MATCH" == "yes" ] ; then
			REPARTED=no
		else
			REPARTED=yes
		fi
		echo ------${REPARTED}

if [ "$REPARTED" == "yes" ] ; then
	echo "Setting partition table to GPT (UEFI) -----------------------"
		parted ${DEVICE} --script mktable gpt                         > /dev/null 2>&1

	echo "Creating EFI partition --------------------------------------"
		parted ${DEVICE} --script mkpart ESP fat32 1MiB ${PART_EFI_END}MiB > /dev/null 2>&1
		parted ${DEVICE} --script set 1 esp on                          > /dev/null 2>&1

	echo "Creating Clonezilla partition -------------------------------"
		parted ${DEVICE} --script mkpart CLONEZILLA ext4 ${PART_EFI_END}MiB ${PART_CZ_END}MiB > /dev/null 2>&1

	echo "Creating OS partition ---------------------------------------"
		parted ${DEVICE} --script mkpart LINUX ext4 ${PART_OS_START}MiB ${PART_OS_END}MiB >/dev/null 2>&1

	echo "Creating Resources/Cache partition --------------------------"
		parted ${DEVICE} --script mkpart RESOURCES ext4 ${PART_OS_END}MiB 100% >/dev/null 2>&1
		sleep 2
fi

echo "Formating partitions ----------------------------------------"
[ "$REPARTED" == yes ] && mkfs.vfat -n EFI        ${DEVICE}1 >/dev/null 2>&1 || true
[ "$REPARTED" == yes ] && mkfs.ext4 -L RESOURCES  ${DEVICE}4 >/dev/null 2>&1 || true
		 	  mkfs.ext4 -L CLONEZILLA ${DEVICE}2 >/dev/null 2>&1 || true
			  mkfs.ext4 -L LINUX      ${DEVICE}3 >/dev/null 2>&1 || true

echo "Mounting ----------------------------------------------------"
echo "---OS partition"
        mkdir -p ${ROOTFS}                                      > /dev/null 2>&1
        mount ${DEVICE}3 ${ROOTFS}                              > /dev/null 2>&1
	
echo "---Recovery partition"
        mkdir -p ${RECOVERYFS}                                  > /dev/null 2>&1
        mount ${DEVICE}2 ${RECOVERYFS}                          > /dev/null 2>&1

echo "---Resources/Cache partition"
	echo -n "-----"
        mkdir -vp ${CACHE_FOLDER}
        chown $SUDO_USER: -R ${CACHE_FOLDER}
	mount ${DEVICE}4 ${CACHE_FOLDER}
        #mkdir -p ${ROOTFS}/var/cache/apt/archives               > /dev/null 2>&1 
        #mount --bind ${CACHE_FOLDER} ${ROOTFS}/var/cache/apt/archives
echo "---Cleaning cache packages if necesary"
	set +e
	while [ ! -z "$(ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d)" ] ; do
		echo ---This packages have more than one version.
		ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d | while read line
        	do ls ${CACHE_FOLDER}/${line}* 
		done
		echo ---Removing older versions so multistrap wont fail
		ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d | while read line
        	do rm -v ${CACHE_FOLDER}/${line}* 
		done
	done
	set -e

echo "Downloading keyboard mappings -------------------------------"
	wget --show-progress -qcN -O ${CACHE_FOLDER}/${KEYBOARD_MAPS} ${KEYBOARD_FIX_URL}${KEYBOARD_MAPS}

echo "Downloading Libreoffice -------------------------------------"
	mkdir -p $DOWNLOAD_DIR_LO >/dev/null 2>&1
        wget --show-progress -qcN ${LIBREOFFICE_MAIN} -P $DOWNLOAD_DIR_LO
        wget --show-progress -qcN ${LIBREOFFICE_LAPA} -P $DOWNLOAD_DIR_LO
        wget --show-progress -qcN ${LIBREOFFICE_HELP} -P $DOWNLOAD_DIR_LO
	find $DOWNLOAD_DIR_LO/ -type f -name '*.deb' -exec rm {} \; || true
        tar -xzf $DOWNLOAD_DIR_LO/LibreOffice_${VERSION_LO}_Linux_x86-64_deb.tar.gz -C $DOWNLOAD_DIR_LO
        tar -xzf $DOWNLOAD_DIR_LO/LibreOffice_${VERSION_LO}_Linux_x86-64_deb_langpack_$LO_LANG.tar.gz -C $DOWNLOAD_DIR_LO
	tar -xzf $DOWNLOAD_DIR_LO/LibreOffice_${VERSION_LO}_Linux_x86-64_deb_helppack_$LO_LANG.tar.gz -C $DOWNLOAD_DIR_LO

echo "Downloading Draw.io -----------------------------------------"
	mkdir -p $DRAWIO_FOLDER >/dev/null 2>&1
        wget --show-progress -qcN ${DRAWIO_URL} -P ${DRAWIO_FOLDER}

echo "Downloading lastest clonezilla ------------------------------"
        mkdir -p $DOWNLOAD_DIR_CLONEZILLA 2>/dev/null || true
	echo "---Downloading from ${MIRROR_CLONEZILLA}"
        case ${MIRROR_CLONEZILLA} in
		Official_Fast )
			FILE_CLONEZILLA=$(curl -s "$BASEURL_CLONEZILLA_FAST" | grep -oP 'href="\Kclonezilla-live-[^"]+?\.zip(?=")' | head -n 1)
			wget --show-progress -qcN -O ${DOWNLOAD_DIR_CLONEZILLA}/${FILE_CLONEZILLA} ${BASEURL_CLONEZILLA_FAST}${FILE_CLONEZILLA} ;;
		Official_Slow )
			URL_CLONEZILLA=$(curl -S "$BASEURL_CLONEZILLA_SLOW" 2>/dev/null|grep https| cut -d \" -f 2)
			FILE_CLONEZILLA=$(echo $URL_CLONEZILLA | cut -f8 -d\/ | cut -f1 -d \?)
			wget --show-progress -qcN -O ${DOWNLOAD_DIR_CLONEZILLA}/${FILE_CLONEZILLA} ${URL_CLONEZILLA} ;;
        esac

	echo "---Extracting clonezilla"
	unzip -u ${DOWNLOAD_DIR_CLONEZILLA}/${FILE_CLONEZILLA} -d ${RECOVERYFS} >>$LOG 2>>$ERR
	cp -p ${RECOVERYFS}/boot/grub/grub.cfg ${RECOVERYFS}/boot/grub/grub.cfg.old
	sed -i '/menuentry[^}]*{/,/}/d' ${RECOVERYFS}/boot/grub/grub.cfg
	sed -i '/submenu[^}]*{/,/}/d' ${RECOVERYFS}/boot/grub/grub.cfg
	mv ${RECOVERYFS}/live ${RECOVERYFS}/live-hd

	echo "---Creating grub.cfg for clonezilla"
	set +e ###################################
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
	set -e ##################################
echo '
##PREFIX##
menuentry  --hotkey=s "Salvar imagen"{
  search --set -f /live-hd/vmlinuz
  linux /live-hd/vmlinuz boot=live union=overlay username=user config components quiet noswap edd=on nomodeset noprompt noeject locales= keyboard-layouts=%%KEYBOARD%% ocs_prerun="mount /dev/%%BASE%%2 /home/partimag" ocs_live_run="/usr/sbin/ocs-sr -q2 -b -j2 -z1p -i 4096 -sfsck -scs -enc -p poweroff saveparts debian_image %%BASE%%1 %%BASE%%3" ocs_postrun="/home/partimag/clean" ocs_live_extra_param="" keyboard-layouts="US" ocs_live_batch="yes" vga=788 toram=live-hd,syslinux,EFI ip= net.ifnames=0 i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1 live-media-path=/live-hd bootfrom=/dev/%%BASE%%2
  initrd /live-hd/initrd.img
}
##SUFIX##
menuentry  --hotkey=r "Restaurar imagen"{
  search --set -f /live-hd/vmlinuz
  linux /live-hd/vmlinuz boot=live union=overlay username=user config components quiet noswap edd=on nomodeset noprompt noeject locales= keyboard-layouts=%%KEYBOARD%% ocs_prerun="mount /dev/%%BASE%%2 /home/partimag" ocs_live_run="ocs-sr -g auto -e1 auto -e2 -t -r -j2 -b -k -scr -p reboot restoreparts debian_image %%BASE%%1 %%BASE%%3" ocs_live_extra_param="" keyboard-layouts="US" ocs_live_batch="yes" vga=788 toram=live-hd,syslinux,EFI ip= net.ifnames=0 i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1 live-media-path=/live-hd bootfrom=/dev/%%BASE%%2
  initrd /live-hd/initrd.img
}' >> ${RECOVERYFS}/boot/grub/grub.cfg

	echo "---Post image creation cleaning script"
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

sed -i 's/timeout=30/timeout=5/g'		 ${RECOVERYFS}/boot/grub/grub.cfg	
sed -i 's/%%KEYBOARD%%/'$CLONEZILLA_KEYBOARD'/g' ${RECOVERYFS}/boot/grub/grub.cfg
sed -i 's/%%BASE%%/'$BASE'/g'                    ${RECOVERYFS}/boot/grub/grub.cfg
sed -i 's/%%BASE%%/'$BASE'/g'                    ${RECOVERYFS}/clean

echo "Running mmdebstrap ------------------------------------------"
mmdebstrap --variant=apt --architectures=amd64 --mode=root --format=directory --skip=cleanup \
    --include="${INCLUDES_DEB} google-chrome-stable ${FIREFOX_PACKAGE} spotify-client syncthing" "${DEBIAN_VERSION}" "${ROOTFS}" \
    --setup-hook='mkdir -p "$1/var/cache/apt/archives"'  --setup-hook='mount --bind '$CACHE_FOLDER' "$1/var/cache/apt/archives"' \
	"deb [trusted=yes] ${REPOSITORY_DEB}   ${DEBIAN_VERSION}          main contrib non-free non-free-firmware" \
	"deb [trusted=yes] ${SECURITY_DEB}     ${DEBIAN_VERSION}-security main contrib non-free non-free-firmware" \
	"deb [trusted=yes] ${REPOSITORY_DEB}   ${DEBIAN_VERSION}-updates  main contrib non-free non-free-firmware" \
	"deb [trusted=yes] ${CHROME_REPOSITORY}                           stable  main"                            \
	"deb [trusted=yes] ${FIREFOX_REPOSITORY}                          mozilla main"                            \
	"deb [trusted=yes] ${SPOTIFY_REPOSITORY}                          stable  non-free"                        \
	"deb [trusted=yes] ${SYNCTHING_REPOSITORY}                        syncthing stable-v2"                     \
        > >(tee -a "$LOG") 2> >(tee -a "$ERR" >&2)

# https://apt.syncthing.net/
# sudo mkdir -p /etc/apt/keyrings
# sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
# echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" | sudo tee /etc/apt/sources.list.d/syncthing.list
# 
SYNCTHING_REPOSITORY="https://apt.syncthing.net"
SYNCTHING_KEYS="https://syncthing.net/release-key.gpg"
SYNCTHING_TRUSTED="/etc/apt/keyrings/syncthing-archive-keyring.gpg"



echo "Splitting sources.list's in sources.list.d ------------------"
 	echo -----Downloading keyrings
	wget -qO- ${CHROME_REPOSITORY} | tee                    ${ROOTFS}${CHROME_TRUSTED}    > /dev/null
	wget -qO- ${FIREFOX_KEY}       | tee                    ${ROOTFS}${FIREFOX_TRUSTED}   > /dev/null
	wget -qO- ${SPOTIFY_KEYS}      | gpg --dearmor --yes -o ${ROOTFS}${SPOTIFY_TRUSTED}   > /dev/null
	wget -qO- ${SYNCTHING_KEYS}    | tee                    ${ROOTFS}${SYNCTHING_TRUSTED} > /dev/null

	echo ----Generating each dot list file with signed-by
	 grep debian  ${ROOTFS}/etc/apt/sources.list > ${ROOTFS}/etc/apt/sources.list.d/debian.list
	 #grep chrome  ${ROOTFS}/etc/apt/sources.list > ${ROOTFS}/etc/apt/sources.list.d/google-chrome.list
	 #grep mozilla ${ROOTFS}/etc/apt/sources.list > ${ROOTFS}/etc/apt/sources.list.d/mozilla.list
	 #grep spotify ${ROOTFS}/etc/apt/sources.list > ${ROOTFS}/etc/apt/sources.list.d/spotify.list
	echo "deb [signed-by=${CHROME_TRUSTED}]    ${CHROME_REPOSITORY}     stable main"        > ${ROOTFS}/etc/apt/sources.list.d/google-chrome.list
	echo "deb [signed-by=${FIREFOX_TRUSTED}]   ${FIREFOX_REPOSITORY}   mozilla main"        > ${ROOTFS}/etc/apt/sources.list.d/mozilla.list
	echo "deb [signed-by=${SPOTIFY_TRUSTED}]   ${SPOTIFY_REPOSITORY}   stable non-free"     > ${ROOTFS}/etc/apt/sources.list.d/spotify.list
	echo "deb [signed-by=${SYNCTHING_TRUSTED}] ${SYNCTHING_REPOSITORY} syncthing stable-v2" > ${ROOTFS}/etc/apt/sources.list.d/syncthing.list
	
	rm ${ROOTFS}/etc/apt/sources.list 

echo "Setting build date in hostname and filesystem ---------------"
        echo "127.0.0.1       localhost"                     > ${ROOTFS}/etc/hosts
        echo "127.0.1.1       debian-$(date +'%Y-%m-%d')"   >> ${ROOTFS}/etc/hosts
        echo "::1     localhost ip6-localhost ip6-loopback" >> ${ROOTFS}/etc/hosts
        echo "ff02::1 ip6-allnodes"                         >> ${ROOTFS}/etc/hosts
        echo "ff02::2 ip6-allrouters"                       >> ${ROOTFS}/etc/hosts
        echo "debian-$(date +'%Y-%m-%d')"                    > ${ROOTFS}/etc/hostname
        touch ${ROOTFS}/ImageDate.$(date +'%Y-%m-%d')

echo "Generating fstab --------------------------------------------"
        root_uuid="$(blkid | grep ^$DEVICE | grep ' LABEL="LINUX" ' | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        efi_uuid="$(blkid  | grep ^$DEVICE | grep ' LABEL="EFI" '   | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        FILE=${ROOTFS}/etc/fstab
        echo "$root_uuid /        ext4  defaults 0 1"  > $FILE
        echo "$efi_uuid  /boot/efi vfat defaults 0 1" >> $FILE

echo "Setting Keyboard --------------------------------------------"
	echo "---For non graphical console"
        # FIX DEBIAN BUG
        cd /tmp
        tar xzvf ${CACHE_FOLDER}/${KEYBOARD_MAPS}   >>$LOG 2>>$ERR
        cd kbd-*/data/keymaps/
        mkdir -p ${ROOTFS}/usr/share/keymaps/
        cp -r * ${ROOTFS}/usr/share/keymaps/  >>$LOG 2>>$ERR

	echo "---For everything else"
	echo 'XKBLAYOUT="latam"' > ${ROOTFS}/etc/default/keyboard

echo "Fixing nm-applet from empty icon bug ------------------------"
	echo --Before
	grep Exec ${ROOTFS}/etc/xdg/autostart/nm-applet.desktop 
	sed -i '/^Exec=/c\Exec=nm-applet --indicator' ${ROOTFS}/etc/xdg/autostart/nm-applet.desktop 
	echo --After
	grep Exec ${ROOTFS}/etc/xdg/autostart/nm-applet.desktop

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


echo "Getting ready for chroot ------------------------------------"
	echo "---Mounting EFI partition"
        mkdir -p ${ROOTFS}/boot/efi
        mount ${DEVICE}1 ${ROOTFS}/boot/efi

	echo "---Mounting pseudo-filesystems"
        mount --bind /dev ${ROOTFS}/dev
        mount -t devpts /dev/pts ${ROOTFS}/dev/pts
        mount --bind /run  ${ROOTFS}/run
        mount -t sysfs sysfs ${ROOTFS}/sys
        mount -t tmpfs tmpfs ${ROOTFS}/tmp
	ln -s ${LOG} ${ROOTFS}/var/log/notebook.log
	ln -s ${ERR} ${ROOTFS}/var/log/notebook.err

echo "Entering chroot ---------------------------------------------"
        echo "#!/bin/bash
        export DOWNLOAD_DIR_LO=/var/cache/apt/archives/Libreoffice
        export VERSION_LO=${VERSION_LO}
        export LO_LANG=es  # Idioma para la instalación
        export LC_ALL=C LANGUAGE=C LANG=C
        export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
	export LOG=/var/log/notebook.log
	export ERR=/var/log/notebook.err
	echo nameserver 8.8.8.8 > /etc/resolv.conf
	set -e
        PROC_NEEDS_UMOUNT=0
        if [ ! -e /proc/uptime ]; then
                mount proc -t proc /proc 2>/dev/null
                PROC_NEEDS_UMOUNT=1
        fi
	
	echo ---Enabling virtual-networks
	/usr/sbin/libvirtd & 		>/dev/null 2>&1
	virsh net-autostart default	>/dev/null 2>&1
	pkill libvirtd			>/dev/null 2>&1

	echo ---Adding virtual-networks to kernel modules
	echo vhost_net >> /etc/modules

        echo ---Running tasksel for fixes
	tasksel install ssh-server laptop xfce --new-install                                    1>&2

	echo ---Installing Draw.io
	dpkg -i /var/cache/apt/archives/Draw.io/${DRAWIO_DEB}					1>&2

        #Installing Libreoffice in backgroupd
        dpkg -i \$(find \$DOWNLOAD_DIR_LO/ -type f -name \*.deb)				1>&2
        pid_LO=$!

        echo ---Installing grub
        update-initramfs -c -k all                                                              1>&2
        grub-install --target=x86_64-efi --efi-directory=/boot/efi \
	      --bootloader-id=debian --recheck --no-nvram --removable  				1>&2
        update-grub                                                                             1>&2

        echo ---Installing LibreOffice and its language pack
	echo -----Cloning script for future updates
	cd /opt
	git clone ${LIBREOFFICE_UPDS}
	chmod +x /opt/install-libreoffice-from-web/setup.sh
        wait $pid_LO
        apt install --fix-broken -y                                                             1>&2
        echo ------LibreOffice \$VERSION_LO installation done.

	echo ---Flatpak and Mission Center
	flatpak remote-add --if-not-exists flathub ${FLATPAK_REPO}				1>&2
	flatpak install flathub io.missioncenter.MissionCenter -y				1>&2

	echo ---Skel
	cd /opt	
	git clone ${THIS_SCRIPT}								1>&2
	cd debian-clonezilla-multistrap
	rsync -av --delete /opt/debian-clonezilla-multistrap/skel/ /etc/skel			1>&2

        echo ---Setting languaje and unattended-upgrades packages
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
        debconf-set-selections <<< \"unattended-upgrades unattended-upgrades/enable_auto_updates boolean true\"
        
	rm -f /etc/localtime /etc/timezone
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive tzdata			1>&1
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-data		#>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-setup		#>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive keyboard-configuration 	#>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive unattended-upgrades         #>>\$LOG 2>>\$ERR
        sed -i '/# es_AR.UTF-8 UTF-8/s/^# //g' /etc/locale.gen
        locale-gen 											#>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive locales 			#>>\$LOG 2>>\$ERR
	export LANG=es_AR.UTF-8
        update-locale LANG=es_AR.UTF-8									#>>\$LOG 2>>\$ERR
	localectl set-locale LANG=es_AR.UTF-8								#>>\$LOG 2>>\$ERR
        locale												#>>\$LOG 2>>\$ERR
	echo LANG=es_AR.UTF-8 >> /etc/environment
        if [ \$PROC_NEEDS_UMOUNT -eq 1 ]; then
                umount /proc
        fi
	rm /etc/resolv.conf
        exit" > ${ROOTFS}/root/chroot.sh
        chmod +x ${ROOTFS}/root/chroot.sh
        chroot ${ROOTFS} /bin/bash /root/chroot.sh 2>>$ERR 

echo "Unattended upgrades -----------------------------------------"
#https://github.com/mvo5/unattended-upgrades/blob/master/README.md

mv ${ROOTFS}/etc/apt/apt.conf.d/50unattended-upgrades ${ROOTFS}/root/50unattended-upgrades.bak
	echo "---Configuration files"
	echo '
Unattended-Upgrade::Origins-Pattern {
	"origin=Debian,codename=${distro_codename}-updates";
	"origin=Debian,codename=${distro_codename},label=Debian";
	"origin=Debian,codename=${distro_codename},label=Debian-Security";
	"origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
	"origin=Google LLC,codename=stable";

};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
//Unattended-Upgrade::InstallOnShutdown "true";' > ${ROOTFS}/etc/apt/apt.conf.d/50unattended-upgrades


	echo '
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";' >  ${ROOTFS}/etc/apt/apt.conf.d/10periodic

	echo "---Testing Scripts"
	echo '#!/bin/bash
echo Obteniendo lista---------------------
apt update
apt list --upgradable
sleep 3
echo Actualizando-------------------------
echo --Debian
apt upgrade -y
sleep 3
echo --Libreoffice
/opt/install-libreoffice-from-web/setup.sh
echo --Flatpak
flatpak update -y
echo Listo -------------------------------
sleep 10' > ${ROOTFS}/usr/local/bin/actualizar

	echo '#!/bin/bash
echo Asi empezamos ----------------------
dpkg -l | grep -E "firefox-esr|chrome"
rm /etc/apt/sources.list.d/debian.list                  
cp -p /root/old.list /etc/apt/sources.list.d/debian.list
echo Borramos ---------------------------
apt remove --purge firefox-esr google-chrome-stable -y
apt update                                               
CHROME_VERSION=131.0.6778.264-1
wget --show-progress -qcN -O /tmp/google-chrome-stable.deb \
https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${CHROME_VERSION}_amd64.deb

echo Instalamos -------------------------
apt install firefox-esr /tmp/google-chrome-stable.deb -y
echo Asi quedamos -----------------------
dpkg -l | grep -E "firefox-esr|chrome"
sleep 5
rm /etc/apt/sources.list.d/debian.list                   &>/dev/null
cp -p /root/new.list /etc/apt/sources.list.d/debian.list
apt update                                             
apt list --upgradable
sleep 10' > ${ROOTFS}/usr/local/bin/desactualizar

	echo '#!/bin/bash 
FOLDER=/etc/apt/apt.conf.d/ 
 for file in $(ls $FOLDER)
  do 
   echo ${FOLDER}${file} --------------------------
   cat ${FOLDER}${file}
  done
echo CUANTO FALTA-------------------------
systemctl list-timers --all | grep apt
echo ------------------------------------- 
sleep 30'                         > ${ROOTFS}/usr/local/bin/status


	echo "---Repositories for testing scripts"
	echo "deb [trusted=yes] ${REPOSITORY_DEB}   ${DEBIAN_VERSION}          main contrib non-free non-free-firmware"  > ${ROOTFS}/root/new.list
	echo "deb [trusted=yes] ${SECURITY_DEB}     ${DEBIAN_VERSION}-security main contrib non-free non-free-firmware" >> ${ROOTFS}/root/new.list
	echo "deb [trusted=yes] ${REPOSITORY_DEB}   ${DEBIAN_VERSION}-updates  main contrib non-free non-free-firmware" >> ${ROOTFS}/root/new.list
        echo "deb [trusted=yes] ${SNAPSHOT_DEB}     ${DEBIAN_VERSION}          main contrib non-free non-free-firmware"  > ${ROOTFS}/root/old.list
	echo "deb [trusted=yes] ${SNAPSHOT_DEB}     ${DEBIAN_VERSION}-updates  main contrib non-free non-free-firmware" >> ${ROOTFS}/root/old.list

	echo "---Sudoers file for testing scripts"
	echo "$username ALL=(ALL) NOPASSWD: /usr/local/bin/actualizar
$username ALL=(ALL) NOPASSWD: /usr/local/bin/desactualizar" > ${ROOTFS}/etc/sudoers.d/apt

	echo "---Shortcuts for testing scripts"
	echo '[Desktop Entry]
Type=Application
Icon=utilities-terminal
Exec=qterminal -e sudo /usr/local/bin/desactualizar
Terminal=false
Categories=Qt;System;TerminalEmulator;
Name=_Desactualizar '                              > ${ROOTFS}/usr/share/applications/_desactualizar.desktop

	echo '[Desktop Entry]
Type=Application
Icon=utilities-terminal
Exec=qterminal -e sudo /usr/local/bin/actualizar
Terminal=false
Categories=Qt;System;TerminalEmulator;
Name=_Actualizar '                                 > ${ROOTFS}/usr/share/applications/_actualizar.desktop

echo '[Desktop Entry]
Type=Application
Icon=utilities-terminal
Exec=qterminal -e /usr/local/bin/status
Terminal=false
Categories=Qt;System;TerminalEmulator;
Name=_Status '                                     > ${ROOTFS}/usr/share/applications/_status.desktop 

echo "
%updates ALL = NOPASSWD : /usr/local/bin/actualizar 
%updates ALL = NOPASSWD : /usr/local/bin/desactualizar " > ${ROOTFS}/etc/sudoers.d/updates

	echo "---Permissions for testing scripts"
	chmod +x  ${ROOTFS}/usr/local/bin/actualizar ${ROOTFS}/usr/local/bin/desactualizar ${ROOTFS}/usr/local/bin/status

	chmod 644 ${ROOTFS}/root/new.list            ${ROOTFS}/root/old.list \
	${ROOTFS}/usr/share/applications/_desactualizar.desktop \
	${ROOTFS}/usr/share/applications/_actualizar.desktop \
	${ROOTFS}/usr/share/applications/_status.desktop

	chmod 440 ${ROOTFS}/etc/sudoers.d/updates

echo "Setting up local admin account ------------------------------"
        echo 'export LC_ALL=C LANGUAGE=C LANG=C
	useradd -d /home/'$username' -G sudo -m -s /bin/bash '$username'
	groupadd updates
        adduser '$username' updates		>/dev/null
        adduser '$username' kvm			>/dev/null
	adduser '$username' libvirt		>/dev/null
	adduser '$username' libvirt-qemu	>/dev/null
	echo '${username}:${password}' | chpasswd
	rm /tmp/local_admin.sh' > ${ROOTFS}/tmp/local_admin.sh
        chmod +x ${ROOTFS}/tmp/local_admin.sh
        chroot ${ROOTFS} /bin/bash /tmp/local_admin.sh
        
echo "Encrypted user script creation ------------------------------"
	echo "
	echo Adding local user -------------------------------------------
        read -p \"What username do you want for local_encrypted_user ?: \" username
        sudo useradd -d /home/\$username -c local_encrypted_user -m -s /bin/bash \$username
        sudo adduser \$username updates
        sudo adduser \$username kvm
        sudo adduser \$username libvirt
        sudo adduser \$username libvirt-qemu
        
        sudo passwd \$username
        if [ \"\$?\" != \"0\" ] ; then echo Please repeat the password....; sudo passwd \$username ; fi

        echo Encrypting home ---------------------------------------------
	echo --Enabling encryption
		sudo modprobe ecryptfs
		echo ecryptfs | sudo tee -a /etc/modules-load.d/modules.conf

	echo --Migrating home
		sudo ecryptfs-migrate-home -u \$username
		sudo rm -rf /home/\${username}.*

	echo --Login via ssh to complete encryption
		ssh  -o StrictHostKeyChecking=no \${username}@localhost ls -la | grep -i password 
		
	echo --bye!!
		sleep 3
		sudo reboot
	" > ${ROOTFS}/usr/local/bin/useradd-encrypt
	chmod +x ${ROOTFS}/usr/local/bin/useradd-encrypt

echo "Replacing keybindings ----------------------------------------"
	FILE=${ROOTFS}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
	echo --Making Backup file
	cp ${FILE} ${FILE}.bak

	echo --Replacing screenshooter by flameshot
	sed -i \
	-e 's/xfce4-screenshooter -w/flameshot gui/g' \
	-e 's/xfce4-screenshooter -r/flameshot gui/g' \
	-e 's/xfce4-screenshooter/flameshot gui/g'    \
    	"$FILE"

	echo --Deleting lines that may conflict 
	sed -i '/tile_left_key/d'       $FILE 
	sed -i '/tile_right_key/d'      $FILE 
	sed -i '/tile_up_key/d'         $FILE 
	sed -i '/tile_down_key/d'       $FILE 
	sed -i '/tile_up_left_key/d'    $FILE 
	sed -i '/tile_up_right_key/d'   $FILE 
	sed -i '/tile_down_left_key/d'  $FILE 
	sed -i '/tile_down_right_key/d' $FILE 
	sed -i '/maximize_window_key/d' $FILE 

	echo --Ensuring custom keybinding section exists and applying new shortcuts
	if command -v xmlstarlet >/dev/null 2>&1; then
		if ! xmlstarlet sel -t -v "count(/channel/property[@name='xfwm4']/property[@name='custom'])" "$FILE" 2>/dev/null | grep -q '^1$'; then
		    echo "--Creating block customi"
		    xmlstarlet ed -L \
		    -s "/channel/property[@name='xfwm4']" -t elem -n "propertyTMP" -v "" \
		    -i "/channel/property[@name='xfwm4']/propertyTMP" -t attr -n "name" -v "custom" \
		    -i "/channel/property[@name='xfwm4']/propertyTMP" -t attr -n "type" -v "empty" \
		    -r "/channel/property[@name='xfwm4']/propertyTMP" -v "property" \
		    "$FILE"
		else
	    	    echo "--Custom block already exists"
	    	fi

		echo "--Mapping keys to Alt \+ ... "
		declare -A MAP=(
		    ["<Alt>a"]="tile_left_key"
		    ["<Alt>d"]="tile_right_key"
		    ["<Alt>w"]="tile_up_key"
		    ["<Alt>x"]="tile_down_key"
		    ["<Alt>q"]="tile_up_left_key"
		    ["<Alt>e"]="tile_up_right_key"
		    ["<Alt>z"]="tile_down_left_key"
		    ["<Alt>c"]="tile_down_right_key"
		    ["<Alt>s"]="maximize_window_key"
	    	)

		for key in "${!MAP[@]}"; do
		    action=${MAP[$key]}
		    echo -n "$key, "
		    if xmlstarlet sel -t -v "count(/channel/property[@name='xfwm4']/property[@name='custom']/property[@name='${key}'])" "$FILE" 2>/dev/null | grep -q '^1$'; then
			#echo "--Already Exists  : updateing value of    $key -> $action"
			xmlstarlet ed -L \
			    -u "/channel/property[@name='xfwm4']/property[@name='custom']/property[@name='${key}']/@value" \
			    -v "$action" "$FILE"
		    else
			#echo "--It doesnt exists: creating property for $key -> $action"
			xmlstarlet ed -L \
			    -s "/channel/property[@name='xfwm4']/property[@name='custom']"                     -t elem -n "propertyTMP" -v ""        \
			    -i "/channel/property[@name='xfwm4']/property[@name='custom']/propertyTMP[last()]" -t attr -n "name"        -v "$key"    \
			    -i "/channel/property[@name='xfwm4']/property[@name='custom']/propertyTMP[last()]" -t attr -n "type"        -v "string"  \
			    -i "/channel/property[@name='xfwm4']/property[@name='custom']/propertyTMP[last()]" -t attr -n "value"       -v "$action" \
			    -r "/channel/property[@name='xfwm4']/property[@name='custom']/propertyTMP[last()]" -v "property"                         \
			    "$FILE"
		    fi
		done
		echo -e "\n--Just in case replacing wrong characters"
		sed -i 's/&amp;\(lt;\|gt;\)/\1/g' "$FILE"
	fi

echo "Backing up logs ----------------------------------------------"
	cp ${LOG} ${ERR} ${ROOTFS}/

echo "Unmounting ${DEVICE} -----------------------------------------"
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
        umount ${CACHE_FOLDER}                  2>/dev/null || true
        umount ${CACHE_FOLDER}                  2>/dev/null || true

echo "END of the road!! keep up the good work ---------------------"
	mount | grep -E "${DEVICE}|${CACHE_FOLDER}|${ROOTFS}|${RECOVERYFS}" || true
	echo $SCRIPT_DATE
	exit

# time sudo netselect -t40 $(wget -qO- http://www.debian.org/mirror/list | grep '/debian/' | grep -v download | cut -d \" -f6 | sort -u)
# sudo nala fetch --debian trixie --auto --fetches 10 --non-free -c AR -c UR -c CL -c BR
# sudo nala fetch --debian trixie --auto              --non-free -c AR
# sudo nala fetch --debian trixie --auto --fetches 10 --non-free


# TODO
# Discover no abre la primera vez hasta que haces sudo apt update
	# Descartado
# Volumen siempre vuelve a cero
	# Pendiente
# Screenshot no anda por teclado xfce4-settings-editor
	# Listo
	# Teclas de control de ventanas
	# xfconf-query  -l
	# xfconf-query -c xfce4-panel -l

# /etc/xdg/xfce4/panel/default.xml

# lupa xfce4-appfinder
