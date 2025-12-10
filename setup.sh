#!/bin/bash
SCRIPT_DATE=20251210-1324
set -e # Exit on error
LOG=/tmp/laptop.log
ERR=/tmp/laptop.err
SELECTIONS=/tmp/selections

echo ---------------------------------------------------------------------------
timedatectl set-timezone America/Argentina/Buenos_Aires
echo "now    $(date +'%Y%m%d-%H%M')"
# echo "now    $(env TZ=America/Argentina/Buenos_Aires date +'%Y%m%d-%H%M')"
echo "script $SCRIPT_DATE"
echo ---------------------------------------------------------------------------
echo "Installing dependencies for this script ---------------------"
	cd /tmp
        apt update							 >/dev/null 2>&1
	apt install --fix-broken -y					 >/dev/null 2>&1
        apt install dosfstools parted gnupg2 unzip \
        wget curl openssh-server mmdebstrap xmlstarlet \
	netselect-apt aria2  btrfs-progs		-y		 >/dev/null 2>&1
	systemctl start sshd						 >/dev/null 2>&1

#####################################################################################################
#Selections
#####################################################################################################
if [ -f $SELECTIONS ] ; then
	echo Skiping questions, you may delete $SELECTIONS if you change your mind
	source $SELECTIONS
else
	reset
	#Finding Fastest repo in the background
	netselect-apt -n -s -a amd64 trixie 2>&1 | grep -A1 "fastest valid for http" | tail -n1 > /tmp/fastest_repo &
	REPOSITORY_DEB_PID=$!
	
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
	echo "Detecting fastest debian mirror, please wait ----------------"
	#Waiting to background process to finish
	wait $REPOSITORY_DEB_PID
	REPOSITORY_DEB_FAST=$(cat /tmp/fastest_repo)
	REPOSITORY_DEB_FAST=${REPOSITORY_DEB_FAST// /}
	REPOSITORY_DEB_STANDARD="http://deb.debian.org/debian/"
	REPOSITORY_DEB=$(whiptail --title "Debian respository" --menu "Choose one option:" 20 60 10 \
                           "${REPOSITORY_DEB_FAST}" "Fastest detected" \
                       "${REPOSITORY_DEB_STANDARD}" "Default Debian"   \
               3>&1 1>&2 2>&3)

	#####################################################################################################
	echo export DEVICE="$DEVICE"				>  $SELECTIONS
	echo export MIRROR_CLONEZILLA="$MIRROR_CLONEZILLA"	>> $SELECTIONS
	echo export FIREFOX_PACKAGE=\"$FIREFOX_PACKAGE\"	>> $SELECTIONS
	echo export username="$username"			>> $SELECTIONS
	echo export password="$password"			>> $SELECTIONS
	echo export PART_OP_PERCENTAGE="$PART_OP_PERCENTAGE"	>> $SELECTIONS
	echo export REPOSITORY_DEB="${REPOSITORY_DEB}" 		>> $SELECTIONS

fi
#####################################################################################################
#VARIABLES 
#####################################################################################################

# Debian Variables 
DEBIAN_VERSION=trixie
SECURITY_DEB="http://security.debian.org/debian-security"
SNAPSHOT_DEB="https://snapshot.debian.org/archive/debian/20251031T203358Z/"
 
# Mount Points
CACHE_FOLDER=/tmp/resources-fs
ROOTFS=/tmp/os-rootfs

# Partition Fixed Sizes
PART_EFI_END=901
PART_CZ_END=12901

# Keyboard Language for TTY consoles
KEYBOARD_FIX_URL="https://mirrors.edge.kernel.org/pub/linux/utils/kbd"
KEYBOARD_MAPS=$(curl -s ${KEYBOARD_FIX_URL}/ | grep tar.gz | cut -d'"' -f2 | tail -n1)
KEYBOARD_MAPS_DOWNLOAD_DIR=${CACHE_FOLDER}/Keyboard_maps/

# Cloning software for recovery partition
RECOVERYFS=/tmp/recovery-rootfs
CLONEZILLA_KEYBOARD=latam
DOWNLOAD_DIR_CLONEZILLA=${CACHE_FOLDER}/Clonezilla
BASEURL_CLONEZILLA_FAST="https://free.nchc.org.tw/clonezilla-live/stable/"
BASEURL_CLONEZILLA_SLOW="https://sourceforge.net/projects/clonezilla/files/latest/download"

# Apt certificate repository folder
APT_CONFIG="$(command -v apt-config 2> /dev/null)"
eval "$("$APT_CONFIG" shell APT_TRUSTEDDIR 'Dir::Etc::trustedparts/d')"

# Apt packages list for installing with mmdebstrap
# NOTE: Fictional variables below are only for title purposes ########################################
INCLUDES_DEB="${RAMDISK_AND_SYSTEM_PACKAGES} \
apt initramfs-tools zstd gnupg systemd linux-image-amd64 login flatpak btrfs-progs \
${XFCE_AND_DESKTOP_APPLICATIONS} \
xfce4 xorg dbus-x11 	   gvfs cups thunar-volman  system-config-printer    xarchiver                vlc flameshot	       mousepad              \
lm-sensors 		   qbittorrent  	    qpdfview		     keepassxc-full 	      light-locker             gnome-keyring         \
xfce4-battery-plugin       xfce4-clipman-plugin     xfce4-cpufreq-plugin     xfce4-cpugraph-plugin    xfce4-datetime-plugin    xfce4-diskperf-plugin \
xfce4-fsguard-plugin       xfce4-genmon-plugin      xfce4-mailwatch-plugin   xfce4-netload-plugin     xfce4-places-plugin      xfce4-sensors-plugin  \
xfce4-smartbookmark-plugin xfce4-systemload-plugin  xfce4-timer-plugin       xfce4-verve-plugin       xfce4-wavelan-plugin     xfce4-weather-plugin  \
xfce4-xkb-plugin           xfce4-whiskermenu-plugin xfce4-dict 		     xfce4-notifyd            xfce4-indicator-plugin   xfce4-mpc-plugin      \
thunar-archive-plugin      thunar-media-tags-plugin ntfs-3g timeshift \
${BUG_FIXES_PACKAGES} \
at-spi2-core xinput gawk inotify-tools \
${FONTS_PACKAGES_AND_THEMES}  \
fonts-dejavu-core fonts-droid-fallback fonts-font-awesome fonts-lato fonts-liberation2 fonts-mathjax fonts-noto-mono fonts-opensymbol fonts-quicksand \
fonts-symbola fonts-urw-base35 gsfonts arc-theme \
task-xfce-desktop task-ssh-server task-laptop qterminal \
${COMMANDLINE_TOOLS} \
sudo vim wget curl dialog nano file less pciutils lshw usbutils bind9-dnsutils fdisk file git gh zenity build-essential ncdu \
whiptail \
${CRON_TOOLS} \
anacron cron cron-daemon-common \
${NETWORK_PACKAGES_AND_DRIVERS} \
blueman bluetooth bluez bluez-firmware bluez-alsa-utils \
bind9-host dfu-util dnsmasq-base ethtool ifupdown iproute2 iputils-ping isc-dhcp-client \
network-manager network-manager-applet network-manager-openconnect network-manager-l2tp network-manager-l10n \
powermgmt-base util-linux wpasupplicant xfce4-power-manager xfce4-power-manager-plugins \
firmware-ath9k-htc firmware-amd-graphics firmware-intel-graphics firmware-linux firmware-linux-free firmware-realtek \
amd64-microcode intel-microcode mesa-va-drivers mesa-vdpau-drivers mesa-vulkan-drivers firmware-iwlwifi network-manager-l10n \
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


# dbus-update-activation-environment --systemd --all > ~/.xinitrc	



# Linux Standard Office Suite
DOWNLOAD_DIR_LO=${CACHE_FOLDER}/Libreoffice
LIBREOFFICE_URL="https://download.documentfoundation.org/libreoffice/stable/"
LO_LANG=es 
VERSION_LO=$(wget -qO- $LIBREOFFICE_URL | grep -oP '[0-9]+(\.[0-9]+)+' | sort -V | tail -1)
LIBREOFFICE_MAIN_FILE=LibreOffice_${VERSION_LO}_Linux_x86-64_deb.tar.gz
LIBREOFFICE_LAPA_FILE=LibreOffice_${VERSION_LO}_Linux_x86-64_deb_langpack_$LO_LANG.tar.gz
LIBREOFFICE_HELP_FILE=LibreOffice_${VERSION_LO}_Linux_x86-64_deb_helppack_$LO_LANG.tar.gz
LIBREOFFICE_MAIN=${LIBREOFFICE_URL}${VERSION_LO}/deb/x86_64/${LIBREOFFICE_MAIN_FILE}
LIBREOFFICE_LAPA=${LIBREOFFICE_URL}${VERSION_LO}/deb/x86_64/${LIBREOFFICE_LAPA_FILE}
LIBREOFFICE_HELP=${LIBREOFFICE_URL}${VERSION_LO}/deb/x86_64/${LIBREOFFICE_HELP_FILE}
LIBREOFFICE_UPDS="https://github.com/catupeloco/install-libreoffice-from-web"

# Google Chrome Browser Repository
# https://www.google.com/linuxrepositories/
# wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo tee /etc/apt/trusted.gpg.d/google.asc >/dev/null
 # NOTE: On systems with older versions of apt (i.e. versions prior to 1.4), the ASCII-armored
 # format public key must be converted to binary format before it can be used by apt.d
# wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/google.gpg >/dev/null
CHROME_REPOSITORY="https://dl.google.com/linux/chrome/deb/" 
export CHROME_KEY="https://dl.google.com/linux/linux_signing_key.pub"
CHROME_TRUSTED="/etc/apt/trusted.gpg.d/google.asc"

# For Updating Testing Script
# https://www.ubuntuupdates.org/package/google_chrome/stable/main/base/google-chrome-stable
CHROME_OLD_VERSION=141.0.7390.65-1

# Mozilla Firefox Browser Repository for Firefox Rapid Release and Firefox ESR
# https://support.mozilla.org/es/kb/Instalar-firefox-linux#w_instalar-el-paquete-deb-de-firefox-para-distribuciones-basadas-en-debian
# wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
FIREFOX_REPOSITORY="https://packages.mozilla.org/apt"
FIREFOX_KEY="https://packages.mozilla.org/apt/repo-signing-key.gpg"
FIREFOX_TRUSTED="/etc/apt/keyrings/packages.mozilla.org.asc"

# Online Music player
# https://www.spotify.com/es/download/linux/
# curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
# echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
SPOTIFY_REPOSITORY="https://repository.spotify.com"
SPOTIFY_KEYS="https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg"
SPOTIFY_TRUSTED="/etc/apt/trusted.gpg.d/spotify.gpg"

# Cross platform app for syncing folders between devices
# https://apt.syncthing.net/
# sudo mkdir -p /etc/apt/keyrings
# sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
# echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" | sudo tee /etc/apt/sources.list.d/syncthing.list
SYNCTHING_REPOSITORY="https://apt.syncthing.net"
SYNCTHING_KEYS="https://syncthing.net/release-key.gpg"
SYNCTHING_TRUSTED="/etc/apt/keyrings/syncthing-archive-keyring.gpg"
export SYNCTHING_SERV_RESUME_TARGET="/etc/systemd/system/syncthing-resume.service" 
export SYNCTHING_SERV_RESUME_URL="https://raw.githubusercontent.com/syncthing/syncthing/main/etc/linux-systemd/system/syncthing-resume.service"
export SYNCTHING_SERV_ARROBA_TARGET="/etc/systemd/system/syncthing@.service"
export SYNCTHING_SERV_ARROBA_URL="https://raw.githubusercontent.com/syncthing/syncthing/main/etc/linux-systemd/system/syncthing%40.service"

# Diagram offline app	
# https://www.drawio.com/ https://app.diagrams.net/ https://get.diagrams.net/
DRAWIO_URL=$(wget -qO- https://github.com/jgraph/drawio-desktop/releases/latest | cut -d \" -f2 | grep deb | grep amd64)
DRAWIO_FOLDER=${CACHE_FOLDER}/Draw.io
DRAWIO_DEB=${DRAWIO_URL##*/}

# Mark Down syntax app
# https://www.marktext.cc/
# https://flathub.org/es/apps/com.github.marktext.marktext
MARKTEXT_FOLDER=${CACHE_FOLDER}/Marktext
MARKTEXT_URL_PREFIX=https://github.com/marktext/marktext/releases/download
MARKTEXT_RELEASE=$(curl --silent "https://api.github.com/repos/marktext/marktext/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
MARKTEXT_DEB=marktext-amd64.deb
MARKTEXT_URL="${MARKTEXT_URL_PREFIX}/${MARKTEXT_RELEASE}/${MARKTEXT_DEB}"

# For MissionCenter and others 
FLATPAK_REPO="https://dl.flathub.org/repo/flathub.flatpakrepo"

# For Taskbar Skel
THIS_SCRIPT="https://github.com/catupeloco/debian-clonezilla-multistrap.git"

# Auto entries on grub of snapshots made by btrfs and timeshift
GRUB_BTRFS="https://github.com/Antynea/grub-btrfs.git"

# Old Versions of this script used Debian 12 which didnt have drivers for my wifi, so I've 
# downloaded drivers from kernel.org, but this method is not recommended as it can't be
# updated as the files are not in a package. Newer option was to install backport package
# for wifi but it was discontinuated after migration to Debian 13 Trixie.
# 
# WIFI_DOMAIN="https://git.kernel.org"
# export WIFI_URL="${WIFI_DOMAIN}/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain" 
# export WIFI_MAX_PARALLEL=10

# For Cleaning Screen and progress bar
LOCALIP=$(ip -br a | grep -v ^lo | grep -i UP | awk '{print $3}' | cut -d\/ -f1)
export PROGRESS_BAR_MAX=45
export PROGRESS_BAR_WIDTH=43
export PROGRESS_BAR_CURRENT=0

########################################################################################################################################################
cleaning_screen (){
# for clear screen on tty (clear doesnt work)
printf "\033c"
echo "============================================================="
echo "Installing on Device ${DEVICE} with ${username} as local admin :
	- Debian ${DEBIAN_VERSION} from ${REPOSITORY_DEB} (FASTEST REPOSITORY at your location) with :
		- XFCE with custom skel (for taskbar) and keybindings (for window manager).
		- BTRFS, GRUB-BTRFS and Timeshift for snapshots of root file system.
		- Flameshot (replace for screenshots), Qterminal (replace for xfce terminal).
		- Mousepad, VLC, QBittorrent, OBS Studio, KeePassXC.
		- X2goclient, Remmina, x11vnc and ssvnc.
		- Unattended upgrades, Virtual Machine Manager (KVM/QEMU).
        	- Wifi and bluetooth drivers. NTFS support (to read Windows Partitions).
		- Optional : 
		  --Firefox ESR (from Mozilla repository).
		  --encrypted home.
	- External latest :
		- Libreoffice, Google Chrome, Clonezilla recovery, Spotify.
		- Flatpak: Mission Center (task manager).
		- SyncThing, X2Go Client, Draw.io, MarkText.
		- Keymaps for tty.
		- Optional : Firefox Rapid Release (from Mozilla repository).
	- With Overprovisioning partition ${PART_OP_PERCENTAGE} %

To follow extra details, use: Alt plus left or right arrows"
grep iso /proc/cmdline >/dev/null && \
echo "For remote access during installation, you can connect remotely : ssh user@$LOCALIP (password is \"live\") "

######## PROGRESS BAR ###################################################
echo "============================================================="
set +e
if [ $PROGRESS_BAR_CURRENT -eq $PROGRESS_BAR_MAX ]; then
	let "PROGRESS_BAR_PERCENT = 100"
	let "PROGRESS_BAR_FILLED_LEN = PROGRESS_BAR_WIDTH"
else
	let "PROGRESS_BAR_PERCENT = PROGRESS_BAR_CURRENT * 100 / PROGRESS_BAR_MAX"
	let "PROGRESS_BAR_FILLED_LEN = PROGRESS_BAR_CURRENT * PROGRESS_BAR_WIDTH / PROGRESS_BAR_MAX"
fi
let "PROGRESS_BAR_EMPTY_LEN = PROGRESS_BAR_WIDTH - PROGRESS_BAR_FILLED_LEN"
PROGRESS_BAR_FILLED_BAR=$(printf "%${PROGRESS_BAR_FILLED_LEN}s" | tr ' ' '#')
PROGRESS_BAR_EMPTY_BAR=$(printf "%${PROGRESS_BAR_EMPTY_LEN}s" | tr ' ' '-')
printf "\rProgress: [%s%s] %3d%% \033[K" "$PROGRESS_BAR_FILLED_BAR" "$PROGRESS_BAR_EMPTY_BAR" "$PROGRESS_BAR_PERCENT"
let "PROGRESS_BAR_CURRENT += 1"
sleep 0.05
printf "\n=============================================================\n"
set -e
#########################################################################
}

cleaning_screen
echo "Inicializing logs tails -------------------------------------"
	touch $LOG
	touch $ERR
set +e
	# RUNNING TAILS ON SECOND AND THIRD TTYs
	if ! pgrep tail ; then
		setsid bash -c 'exec watch sudo fdisk -l										<> /dev/tty2 >&0 2>&1' &
		setsid bash -c 'exec watch sudo df -h   										<> /dev/tty3 >&0 2>&1' &
		setsid bash -c 'exec watch sudo lsblk -f										<> /dev/tty4 >&0 2>&1' &
		setsid bash -c 'exec watch sudo ls -larth '${CACHE_FOLDER}'/{Draw.io,Marktext,Keyboard_maps,Clonezilla,Libreoffice}/	<> /dev/tty5 >&0 2>&1' &
		setsid bash -c 'exec tail -f '$LOG'											<> /dev/tty6 >&0 2>&1' &
		setsid bash -c 'exec tail -f '$ERR' 											<> /dev/tty7 >&0 2>&1' &
	fi
set -e

cleaning_screen
echo "Unmounting ${DEVICE}  ----------------------------------------"
	# JUST IN CASE KILLING GPG PROCESSES FOR MULTIPLE RUNS
	pgrep gpg | while read -r line
	do kill -9 "$line" 			2>/dev/null || true
	done
	# REPEATING UNMOUNT COMMANDS JUST IN CASE
        umount "${DEVICE}"*                     2>/dev/null || true
        umount "${DEVICE}"*                     2>/dev/null || true
        umount ${ROOTFS}/dev/pts                2>/dev/null || true
        umount ${ROOTFS}/dev/pts                2>/dev/null || true
        umount ${ROOTFS}/dev                    2>/dev/null || true
        umount ${ROOTFS}/dev                    2>/dev/null || true
        umount ${ROOTFS}/proc                   2>/dev/null || true
        umount ${ROOTFS}/proc                   2>/dev/null || true
        umount ${ROOTFS}/run                    2>/dev/null || true
        umount ${ROOTFS}/run                    2>/dev/null || true
        umount ${ROOTFS}/sys                    2>/dev/null || true
        umount ${ROOTFS}/sys                    2>/dev/null || true
        umount ${ROOTFS}/tmp                    2>/dev/null || true
        umount ${ROOTFS}/tmp                    2>/dev/null || true
        umount ${ROOTFS}/boot/efi               2>/dev/null || true
        umount ${ROOTFS}/boot/efi               2>/dev/null || true
        umount          /var/cache/apt/archives 2>/dev/null || true
        umount ${ROOTFS}/var/cache/apt/archives 2>/dev/null || true
        umount ${ROOTFS}/var/cache/apt/archives 2>/dev/null || true
        umount ${ROOTFS}/var/log                2>/dev/null || true
        umount ${ROOTFS}/var/log                2>/dev/null || true
        umount ${ROOTFS}/home                   2>/dev/null || true
        umount ${ROOTFS}/home                   2>/dev/null || true
        umount ${ROOTFS}                        2>/dev/null || true
        umount ${ROOTFS}                        2>/dev/null || true
        umount ${ROOTFS}                        2>/dev/null || true
        umount ${RECOVERYFS}                    2>/dev/null || true
        umount ${RECOVERYFS}                    2>/dev/null || true
        umount ${CACHE_FOLDER}                  2>/dev/null || true
        umount ${CACHE_FOLDER}                  2>/dev/null || true

cleaning_screen
echo "Comparing partitions target scheme vs actual schema ---------"

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Calculating OS partition size"
		DISK_SIZE=$(parted "${DEVICE}" --script unit MiB print | awk '/Disk/ {print $3}' | tr -d 'MiB')
		PART_OP_SIZE=$((DISK_SIZE * PART_OP_PERCENTAGE / 100))
		PART_OS_START=$((PART_CZ_END + 1))
		PART_OS_END=$((DISK_SIZE - PART_OP_SIZE)) 
	
	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Labels test"
		LABELS_MATCH=no
		blkid | grep "${DEVICE}"2 | grep CLONEZILLA >/dev/null && \
		blkid | grep "${DEVICE}"3 | grep LINUX      >/dev/null && \
		blkid | grep "${DEVICE}"4 | grep RESOURCES  >/dev/null && \
		LABELS_MATCH=yes && echo ------They DO match || echo ------They DON\'T match

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Sizes test"
		PART_OP_SIZE_REAL=$( parted "${DEVICE}" --script unit MiB print | awk '$1 == "4" {print $4}' | tr -d 'MiB')
		PART_OS_START_REAL=$(parted "${DEVICE}" --script unit MiB print | awk '$1 == "3" {print $2}' | tr -d 'MiB')
		PART_OS_END_REAL=$(  parted "${DEVICE}" --script unit MiB print | awk '$1 == "3" {print $3}' | tr -d 'MiB')

		if [ "$((PART_OP_SIZE - 1))" == "$PART_OP_SIZE_REAL" ] && [ "$PART_OS_START" == "$PART_OS_START_REAL" ] && [ "$PART_OS_END" == "$PART_OS_END_REAL" ] ; then
			echo ------They DO match
			SIZES_MATCH=yes
		else
			echo ------They DON\'T match
			SIZES_MATCH=no
		fi

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Repartitioning needed? :"
		# SKIPPING REPARTED ONLY IF LABELS AND SIZES MATCH
		if [ "$LABELS_MATCH" == "yes" ] && [ "$SIZES_MATCH" == "yes" ] ; then
			REPARTED=no
		else
			REPARTED=yes
		fi
		echo ------${REPARTED}

cleaning_screen 
if [ "$REPARTED" == "yes" ] ; then
	echo "Setting partition table to GPT (UEFI) -----------------------"
		if ! parted "${DEVICE}" --script mktable gpt         ; then           			# > /dev/null 2>&1 ; then
			echo Error you should reboot and start again && exit
		fi

	let "PROGRESS_BAR_CURRENT += 1"
	echo "Creating EFI partition --------------------------------------"
		parted "${DEVICE}" --script mkpart ESP fat32 1MiB ${PART_EFI_END}MiB			# > /dev/null 2>&1
		parted "${DEVICE}" --script set 1 esp on                          			# > /dev/null 2>&1

	let "PROGRESS_BAR_CURRENT += 1"
	echo "Creating Clonezilla partition -------------------------------"
		parted "${DEVICE}" --script mkpart CLONEZILLA ext4 ${PART_EFI_END}MiB ${PART_CZ_END}MiB # > /dev/null 2>&1

	let "PROGRESS_BAR_CURRENT += 1"
	echo "Creating OS partition ---------------------------------------"
	#	Changed to btfs for snapshots with timeshift
	#	parted "${DEVICE}" --script mkpart LINUX ext4 ${PART_OS_START}MiB ${PART_OS_END}MiB 	# >/dev/null 2>&1
		parted "${DEVICE}" --script mkpart LINUX btrfs ${PART_OS_START}MiB ${PART_OS_END}MiB 	# >/dev/null 2>&1

	let "PROGRESS_BAR_CURRENT += 1"
	echo "Creating Resources/Cache partition --------------------------"
		parted "${DEVICE}" --script mkpart RESOURCES ext4 ${PART_OS_END}MiB 100% 		# >/dev/null 2>&1
fi

cleaning_screen
echo "Formating partitions ----------------------------------------"
	if echo ${DEVICE} | grep -i nvme > /dev/null ; then
		DEVICE=${DEVICE}p
	fi
		# EVEN IF THE PARTITION IS FORMATTED I TRY TO CHECK THE FILESYSTEM
			  fsck -y "${DEVICE}"1				 >/dev/null 2>&1 || true
			  fsck -y "${DEVICE}"2				 >/dev/null 2>&1 || true
			  fsck -y "${DEVICE}"3				 >/dev/null 2>&1 || true
			  fsck -y "${DEVICE}"4				 >/dev/null 2>&1 || true
[ "$REPARTED" == yes ] && mkfs.vfat  -n EFI        "${DEVICE}"1 -F	                 || true
[ "$REPARTED" == yes ] && mkfs.ext4  -L RESOURCES  "${DEVICE}"4	-F	                 || true 
		 	  mkfs.ext4  -L CLONEZILLA "${DEVICE}"2 -F	                 || true
			  mkfs.btrfs -L LINUX      "${DEVICE}"3 -f	                 || true

#[ "$REPARTED" == yes ] && mkfs.vfat  -n EFI        "${DEVICE}"1 	                 || true
#[ "$REPARTED" == yes ] && mkfs.ext4  -L RESOURCES  "${DEVICE}"4	                 || true 
#		 	   mkfs.ext4  -L CLONEZILLA "${DEVICE}"2 	                 || true
#			   mkfs.btrfs -L LINUX      "${DEVICE}"3 	                 || true
		     # Disabled because it formats even if REPARTED = no
		     # || mkfs.vfat  -n EFI        "${DEVICE}"1          >/dev/null 2>&1 || true
		     # || mkfs.ext4  -L RESOURCES  "${DEVICE}"4          >/dev/null 2>&1 || true
		     # || mkfs.ext4  -L CLONEZILLA "${DEVICE}"2          >/dev/null 2>&1 || true
		     # || mkfs.btrfs -L LINUX      "${DEVICE}"3          >/dev/null 2>&1 || true

			# Changed to btrs for snapshots with timeshift 
			# mkfs.ext4  -L LINUX      "${DEVICE}"3		 >/dev/null 2>&1 || true

cleaning_screen
echo "Mounting ----------------------------------------------------"
echo "---OS partition"
        mkdir -p ${ROOTFS}                                      > /dev/null 2>&1
        mount "${DEVICE}"3 ${ROOTFS}                            > /dev/null 2>&1
#####################################################################################
        btrfs subvolume create  ${ROOTFS}/@         2>/dev/null || true
        btrfs subvolume create  ${ROOTFS}/@home     2>/dev/null || true
        btrfs subvolume create  ${ROOTFS}/@varlog   2>/dev/null || true
        #btrfs subvolume create  ${ROOTFS}/@varcache 2>/dev/null || true
        umount ${ROOTFS}
	mount -o compress=zstd,noatime,ssd,space_cache=v2,discard=async,subvol=@     "${DEVICE}"3 ${ROOTFS}
        #mount -o subvol=@,compress=zstd,noatime         "${DEVICE}"3 ${ROOTFS}
	#mkdir -p ${ROOTFS}/{home,{var/log,var/cache}}
        #mount -o subvol=@home,compress=zstd,noatime     "${DEVICE}"3 ${ROOTFS}/home
        #mount -o subvol=@varlog,compress=zstd,noatime   "${DEVICE}"3 ${ROOTFS}/var/log
        #mount -o subvol=@varcache,compress=zstd,noatime "${DEVICE}"3 ${ROOTFS}/var/cache

#####################################################################################

	let "PROGRESS_BAR_CURRENT += 1"
echo "----Cleaning files just in case"
	# I DON'T KNOW WHY BUT FORMAT SOME TIMES DOESN'T WORK, SO RM FOR THE WIN
	find ${ROOTFS} -type f -exec rm -rf {} \; 		> /dev/null 2>&1
	find ${ROOTFS} -type d -exec rm -rf {} \; 		> /dev/null 2>&1
	
echo "---Recovery partition"
        mkdir -p ${RECOVERYFS}                                  > /dev/null 2>&1
        mount "${DEVICE}"2 ${RECOVERYFS}                        > /dev/null 2>&1

	let "PROGRESS_BAR_CURRENT += 1"
echo "----Cleaning files just in case"
	# I DON'T KNOW WHY BUT FORMAT SOME TIMES DOESN'T WORK, SO RM FOR THE WIN
	find ${RECOVERYFS} -type f -exec rm -rf {} \; 		> /dev/null 2>&1 
	find ${RECOVERYFS} -type d -exec rm -rf {} \;		> /dev/null 2>&1

	let "PROGRESS_BAR_CURRENT += 1"
echo "---Resources/Cache partition"
	echo -n "-----"
        mkdir -vp ${CACHE_FOLDER}
        chown "${SUDO_USER}": -R ${CACHE_FOLDER}
	mount "${DEVICE}"4 ${CACHE_FOLDER}

	let "PROGRESS_BAR_CURRENT += 1"
echo "---Cleaning cache packages if necesary"
	set +e
	# CONSECUENCIES OF NOT FORMATING RESOURCE PARTITION TAKES TO HAVE 
	# MORE THAN ONE DEB FILE FOR EACH PACKAGE. IN THIS CASES BOOTSTRAP
	# MAY TRAY TO INSTALL EACH FILE FOR SOME PACKAGE AND FAILS
	while [ -n "$(ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d)" ] ; do
		echo ---This packages have more than one version.
		ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d | while read -r linopo
        	do find ${CACHE_FOLDER}/"${line}"*
		done
		echo ---Removing older versions so mmdebstrap wont fail
		ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d | while read -r line
        	do rm -v ${CACHE_FOLDER}/"${line}"* 
		done
	done
	set -e

###########################Parallel Downloads fixes############################################
cleaning_screen
echo "Downloading external software -------------------------------"
	echo "---Pretasks"
	mkdir -p $KEYBOARD_MAPS_DOWNLOAD_DIR	>/dev/null 2>&1
	mkdir -p $DOWNLOAD_DIR_LO		>/dev/null 2>&1
	mkdir -p $DRAWIO_FOLDER			>/dev/null 2>&1
	mkdir -p $MARKTEXT_FOLDER		>/dev/null 2>&1
        mkdir -p $DOWNLOAD_DIR_CLONEZILLA	>/dev/null 2>&1 || true
        case ${MIRROR_CLONEZILLA} in
		Official_Fast )
			FILE_CLONEZILLA=$(curl -s "$BASEURL_CLONEZILLA_FAST" | grep -oP 'href="\Kclonezilla-live-[^"]+?\.zip(?=")' | head -n 1)
			CLONEZILLA_ORIGIN=${BASEURL_CLONEZILLA_FAST}${FILE_CLONEZILLA} ;;
		Official_Slow )
			URL_CLONEZILLA=$(curl -S "$BASEURL_CLONEZILLA_SLOW" 2>/dev/null|grep https| cut -d \" -f 2)
			FILE_CLONEZILLA=$(echo "$URL_CLONEZILLA" | cut -f8 -d\/ | cut -f1 -d \?)
			CLONEZILLA_ORIGIN=${URL_CLONEZILLA} ;;
        esac
	#FILE_CLONEZILLA=$(curl -s "$BASEURL_CLONEZILLA_FAST" | grep -oP 'href="\Kclonezilla-live-[^"]+?\.zip(?=")' | head -n 1)
	#URL_CLONEZILLA=$(curl -S "$BASEURL_CLONEZILLA_SLOW" 2>/dev/null|grep https| cut -d \" -f 2)
	#${BASEURL_CLONEZILLA_FAST}${FILE_CLONEZILLA} ${URL_CLONEZILLA}

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Parallel Downloading of Keyboard Maps, Libreoffice, Draw.io, MarkText and Clonezilla"
FILES_TO_DOWNLOAD=(
"${KEYBOARD_MAPS_DOWNLOAD_DIR}/${KEYBOARD_MAPS}"
           "${DOWNLOAD_DIR_LO}/${LIBREOFFICE_MAIN_FILE}"
           "${DOWNLOAD_DIR_LO}/${LIBREOFFICE_LAPA_FILE}"
           "${DOWNLOAD_DIR_LO}/${LIBREOFFICE_HELP_FILE}"
             "${DRAWIO_FOLDER}/${DRAWIO_DEB}"
           "${MARKTEXT_FOLDER}/${MARKTEXT_DEB}"
   "${DOWNLOAD_DIR_CLONEZILLA}/${FILE_CLONEZILLA}"
)

# List of origins and destinations parallel downloads
cat << EOF > /tmp/downloads.list
${KEYBOARD_FIX_URL}/${KEYBOARD_MAPS}
  dir=${KEYBOARD_MAPS_DOWNLOAD_DIR}
  out=${KEYBOARD_MAPS}
${LIBREOFFICE_MAIN}
  dir=${DOWNLOAD_DIR_LO}
  out=${LIBREOFFICE_MAIN_FILE}
${LIBREOFFICE_LAPA}
  dir=${DOWNLOAD_DIR_LO}
  out=${LIBREOFFICE_LAPA_FILE}
${LIBREOFFICE_HELP}
  dir=${DOWNLOAD_DIR_LO}
  out=${LIBREOFFICE_HELP_FILE}
${DRAWIO_URL}
  dir=${DRAWIO_FOLDER}
  out=${DRAWIO_DEB}
${MARKTEXT_URL}
  dir=${MARKTEXT_FOLDER}
  out=${MARKTEXT_DEB}
${CLONEZILLA_ORIGIN}
  dir=${DOWNLOAD_DIR_CLONEZILLA}
  out=${FILE_CLONEZILLA}
EOF
PENDING="SOMETHING"
while [ ! -z "$PENDING" ] ; do
	# -i                         		: Read URLs from input file
	# -j 5                      		: Run 5 paralell downloads
	# -x 4                      		: Uses up to 4 connections per server on each file
	# -c                        		: Resume broken downloads
	# --allow-overwrite=true    		: Always redownload
	# --allow-overwrite=false    		: NOT redownload
	# --continue=true			: Resumes interrupted downloads
	# --auto-file-renaming=false 		: With this out works as expected
	# --truncate-console-readout=true 	: Single line output
	# --console-log-level=warn   		: Minimize verbose output
	# --download-result=hide 		: Minimize verbose output
	# --summary-interval=0			: Minimize verbose output
	aria2c \
	-i /tmp/downloads.list \
	-j 5 \
	-x 4 \
	-c \
	--allow-overwrite=true \
	--auto-file-renaming=false \
	--truncate-console-readout=true \
	--console-log-level=warn \
	--download-result=hide \
	--summary-interval=0 
	set +e
	PENDING=""
   	for FILE in "${FILES_TO_DOWNLOAD[@]}"; do
		if [[ ! -f "$FILE" ]]; then
		    PENDING+=("$FILE")
		fi
	done
	ls -la "${FILES_TO_DOWNLOAD[@]}" >/dev/null || true
	set -e
	sleep 5
done
	let "PROGRESS_BAR_CURRENT += 1"
	echo -e "\n---Posttasks"

	# Uncompress Libreoffice
	find $DOWNLOAD_DIR_LO/ -type f -name '*.deb' -exec rm {} \; || true
        tar -xzf ${DOWNLOAD_DIR_LO}/${LIBREOFFICE_MAIN_FILE} -C $DOWNLOAD_DIR_LO
        tar -xzf ${DOWNLOAD_DIR_LO}/${LIBREOFFICE_LAPA_FILE} -C $DOWNLOAD_DIR_LO
        tar -xzf ${DOWNLOAD_DIR_LO}/${LIBREOFFICE_HELP_FILE} -C $DOWNLOAD_DIR_LO

###########################Parallel Downloads fixes############################################

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Extracting clonezilla"
	unzip -u ${DOWNLOAD_DIR_CLONEZILLA}/${FILE_CLONEZILLA} -d ${RECOVERYFS} >>$LOG 2>>$ERR
	cp -p ${RECOVERYFS}/boot/grub/grub.cfg ${RECOVERYFS}/boot/grub/grub.cfg.old
	sed -i '/menuentry[^}]*{/,/}/d' ${RECOVERYFS}/boot/grub/grub.cfg
	sed -i '/submenu[^}]*{/,/}/d' ${RECOVERYFS}/boot/grub/grub.cfg
	mv ${RECOVERYFS}/live ${RECOVERYFS}/live-hd

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Creating grub.cfg for clonezilla"
	set +e ###################################
	if   fdisk -l | grep -c nvme0n1 | grep 5 >/dev/null ; then BASE=nvme0n1p
	elif fdisk -l | grep -c sda     | grep 5 >/dev/null ; then BASE=sda
	elif fdisk -l | grep -c xvda    | grep 5 >/dev/null ; then BASE=xvda
	elif fdisk -l | grep -c vda     | grep 5 >/dev/null ; then BASE=vda
	fi
	set -e ##################################

# Recovery Grub Menu
echo '
##PREFIX##
menuentry  --hotkey=s "Salvar imagen"{
  search --set -f /live-hd/vmlinuz
  linux /live-hd/vmlinuz boot=live union=overlay username=user config components quiet noswap edd=on nomodeset noprompt noeject locales=en_US.UTF-8 keyboard-layouts=%%KEYBOARD%% ocs_prerun="mount /dev/%%BASE%%2 /home/partimag" ocs_live_run="/usr/sbin/ocs-sr -q2 -b -j2 -z1p -i 4096 -sfsck -scs -enc -p poweroff saveparts debian_image %%BASE%%1 %%BASE%%3" ocs_postrun="/home/partimag/clean" ocs_live_extra_param="" keyboard-layouts="%%KEYBOARD%%" ocs_live_batch="yes" vga=788 toram=live-hd,syslinux,EFI ip= net.ifnames=0 i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1 live-media-path=/live-hd bootfrom=/dev/%%BASE%%2
  initrd /live-hd/initrd.img
}
##SUFIX##
menuentry  --hotkey=r "Restaurar imagen"{
  search --set -f /live-hd/vmlinuz
  linux /live-hd/vmlinuz boot=live union=overlay username=user config components quiet noswap edd=on nomodeset noprompt noeject locales=en_US.UTF-8 keyboard-layouts=%%KEYBOARD%% ocs_prerun="mount /dev/%%BASE%%2 /home/partimag" ocs_live_run="ocs-sr -g auto -e1 auto -e2 -t -r -j2 -b -k -scr -p reboot restoreparts debian_image %%BASE%%1 %%BASE%%3" ocs_live_extra_param="" keyboard-layouts="%%KEYBOARD%%" ocs_live_batch="yes" vga=788 toram=live-hd,syslinux,EFI ip= net.ifnames=0 i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1 live-media-path=/live-hd bootfrom=/dev/%%BASE%%2
  initrd /live-hd/initrd.img
}' >> ${RECOVERYFS}/boot/grub/grub.cfg

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Post image creation cleaning script"
echo "
mkdir /mnt/%%BASE%%3 /mnt/%%BASE%%4 2>/dev/null
mount /dev/%%BASE%%3 /mnt/%%BASE%%3 2>/dev/null
mount /dev/%%BASE%%4 /mnt/%%BASE%%4 2>/dev/null

cd /mnt/%%BASE%%3/
rm -rf \$(ls /mnt/%%BASE%%3/ | grep -v boot)
FILES=\$(find /mnt/%%BASE%%4/ -type f | wc -l) 
answer=empty
echo Do you wish to purge resources filesystem\? \(y\/n\)
read answer
if [ \"\$answer\" != \"n\" ] && [ \"\$answer\" != \"N\" ] ; then
	echo Cleaning \$FILES files
	rm -rf /mnt/%%BASE%%4/*
else
	echo NOT\!\! Cleaning \$FILES files
fi

sed -i 's/timeout=30/timeout=0/g'									/mnt/%%BASE%%3/boot/grub/grub.cfg
sed -i 's/timeout=5/timeout=0/g'									/mnt/%%BASE%%3/boot/grub/grub.cfg
sed -i '/### BEGIN \/etc\/grub.d\/10_linux ###/,/### END \/etc\/grub.d\/10_linux ###/d'			/mnt/%%BASE%%3/boot/grub/grub.cfg
sed -i '/### BEGIN \/etc\/grub.d\/30_uefi-firmware ###/,/### END \/etc\/grub.d\/30_uefi-firmware ###/d' /mnt/%%BASE%%3/boot/grub/grub.cfg
sed -i '/##PREFIX##/,/##SUFIX##/d' /home/partimag/boot/grub/grub.cfg
umount /dev/%%BASE%%3
umount /dev/%%BASE%%4
"> ${RECOVERYFS}/clean
chmod +x ${RECOVERYFS}/clean

# Customizing Clonezilla Menu
sed -i 's/timeout=30/timeout=5/g'		 ${RECOVERYFS}/boot/grub/grub.cfg	
sed -i 's/%%KEYBOARD%%/'$CLONEZILLA_KEYBOARD'/g' ${RECOVERYFS}/boot/grub/grub.cfg
sed -i 's/%%BASE%%/'$BASE'/g'                    ${RECOVERYFS}/boot/grub/grub.cfg
sed -i 's/%%BASE%%/'$BASE'/g'                    ${RECOVERYFS}/clean

cleaning_screen
echo "Running mmdebstrap (please be patient, longest step) --------"
ls -a ${ROOTFS}
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

cleaning_screen	
echo "Splitting sources.list\'s in sources.list.d ------------------"
 	echo -----Downloading keyrings
	wget -qO- ${CHROME_KEY}        | tee                    ${ROOTFS}${CHROME_TRUSTED}    > /dev/null
	wget -qO- ${FIREFOX_KEY}       | tee                    ${ROOTFS}${FIREFOX_TRUSTED}   > /dev/null
	wget -qO- ${SPOTIFY_KEYS}      | gpg --dearmor --yes -o ${ROOTFS}${SPOTIFY_TRUSTED}   > /dev/null
	wget -qO- ${SYNCTHING_KEYS}    | tee                    ${ROOTFS}${SYNCTHING_TRUSTED} > /dev/null

	let "PROGRESS_BAR_CURRENT += 1"
	echo ----Generating each dot list file with signed-by
	grep debian  ${ROOTFS}/etc/apt/sources.list > ${ROOTFS}/etc/apt/sources.list.d/debian.list
	rm ${ROOTFS}/etc/apt/sources.list 
	echo "deb [signed-by=${CHROME_TRUSTED}]    ${CHROME_REPOSITORY}     stable main"        > ${ROOTFS}/etc/apt/sources.list.d/google-chrome.list
	echo "deb [signed-by=${FIREFOX_TRUSTED}]   ${FIREFOX_REPOSITORY}   mozilla main"        > ${ROOTFS}/etc/apt/sources.list.d/mozilla.list
	echo "deb [signed-by=${SPOTIFY_TRUSTED}]   ${SPOTIFY_REPOSITORY}   stable non-free"     > ${ROOTFS}/etc/apt/sources.list.d/spotify.list
	echo "deb [signed-by=${SYNCTHING_TRUSTED}] ${SYNCTHING_REPOSITORY} syncthing stable-v2" > ${ROOTFS}/etc/apt/sources.list.d/syncthing.list

cleaning_screen	
echo "Setting build date in hostname and filesystem ---------------"

cat <<EOF > ${ROOTFS}/etc/hosts
127.0.0.1       localhost
127.0.1.1       debian-$(date +'%Y-%m-%d')
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
        echo "debian-$(date +'%Y-%m-%d')"                    > ${ROOTFS}/etc/hostname
        touch ${ROOTFS}/ImageDate."$(date +'%Y-%m-%d')"

cleaning_screen	
echo "Generating fstab and mounting more btrfs subvols ------------"
        root_uuid="$(blkid | grep ^"$DEVICE" | grep ' LABEL="LINUX" ' | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        efi_uuid="$(blkid  | grep ^"$DEVICE" | grep ' LABEL="EFI" '   | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        FILE=${ROOTFS}/etc/fstab
	#echo "$root_uuid /        ext4  defaults 0 1"  > $FILE
        ############################################################################
	mkdir -p ${ROOTFS}/{home,{var/log,var/cache}}

	# Commented because I change command order to be more beautiful for the eyes (?)
        #mount -o subvol=@home,compress=zstd,noatime     "${DEVICE}"3 ${ROOTFS}/home
        #mount -o subvol=@varlog,compress=zstd,noatime   "${DEVICE}"3 ${ROOTFS}/var/log
        #echo "$root_uuid /          btrfs subvol=@,compress=zstd,noatime 0 0        "  > $FILE
        #echo "$root_uuid /home      btrfs subvol=@home,compress=zstd,noatime 0 0    " >> $FILE
        #echo "$root_uuid /var/log   btrfs subvol=@varlog,compress=zstd,noatime 0 0  " >> $FILE

	mount -o compress=zstd,noatime,ssd,space_cache=v2,discard=async,subvol=@home     "${DEVICE}"3 ${ROOTFS}/home
        mount -o compress=zstd,noatime,ssd,space_cache=v2,discard=async,subvol=@varlog   "${DEVICE}"3 ${ROOTFS}/var/log
        echo "$root_uuid /          btrfs compress=zstd,noatime,ssd,space_cache=v2,discard=async,subvol=@	 0 0"  > $FILE
        echo "$root_uuid /home      btrfs compress=zstd,noatime,ssd,space_cache=v2,discard=async,subvol=@home	 0 0" >> $FILE
        echo "$root_uuid /var/log   btrfs compress=zstd,noatime,ssd,space_cache=v2,discard=async,subvol=@varlog	 0 0" >> $FILE
        
	# Disabled maybe for boot bug
	#mount -o subvol=@varcache,compress=zstd,noatime "${DEVICE}"3 ${ROOTFS}/var/cache
        #echo "$root_uuid /var/cache btrfs subvol=@varcache,compress=zstd,noatime 0 0" >> $FILE
        ############################################################################
        echo "$efi_uuid  /boot/efi vfat defaults 0 1                                " >> $FILE

cleaning_screen	
echo "Setting Keyboard --------------------------------------------"
	echo "---For non graphical console"
        # FIX DEBIAN BUG
        cd /tmp
        tar xzvf ${KEYBOARD_MAPS_DOWNLOAD_DIR}/"${KEYBOARD_MAPS}"   >>$LOG 2>>$ERR
        cd kbd-*/data/keymaps/
        mkdir -p ${ROOTFS}/usr/share/keymaps/
        cp -r ./* ${ROOTFS}/usr/share/keymaps/  >>$LOG 2>>$ERR

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---For everything else"
	echo 'XKBLAYOUT="latam"' > ${ROOTFS}/etc/default/keyboard

cleaning_screen	
echo "Fixing nm-applet from empty icon bug ------------------------"
	echo --Before
	grep Exec ${ROOTFS}/etc/xdg/autostart/nm-applet.desktop 
	sed -i '/^Exec=/c\Exec=nm-applet --indicator' ${ROOTFS}/etc/xdg/autostart/nm-applet.desktop 
	echo --After
	grep Exec ${ROOTFS}/etc/xdg/autostart/nm-applet.desktop

cleaning_screen	
echo "Creating recovery -------------------------------------------"
# Grub shortcut to Clonezilla Grub
echo '#!/bin/sh
exec tail -n +3 $0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the exec tail line above.

# Particion para restaurar
menuentry "Restaurar" {
   insmod chain
   search --no-floppy --set=root -f /live-hd/vmlinuz
   chainloader ($root)/EFI/boot/grubx64.efi
}'> ${ROOTFS}/etc/grub.d/40_custom

cleaning_screen	
echo "Getting ready for chroot ------------------------------------"
	echo "---Mounting EFI partition"
        mkdir -p ${ROOTFS}/boot/efi
        mount "${DEVICE}"1 ${ROOTFS}/boot/efi

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Mounting pseudo-filesystems"
        mount --bind /dev ${ROOTFS}/dev
        mount -t devpts /dev/pts ${ROOTFS}/dev/pts
        mount --bind /run  ${ROOTFS}/run
        mount -t sysfs sysfs ${ROOTFS}/sys
        mount -t tmpfs tmpfs ${ROOTFS}/tmp

cleaning_screen	
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
	set -x
        PROC_NEEDS_UMOUNT=0
        if [ ! -e /proc/uptime ]; then
                mount proc -t proc /proc 2>/dev/null
                PROC_NEEDS_UMOUNT=1
        fi
	
	echo ---Enabling virtual-networks and kernel modules
	# Adding Virtual networks
	/usr/sbin/libvirtd & 		>/dev/null 2>&1
	virsh net-autostart default	>/dev/null 2>&1
	pkill libvirtd			>/dev/null 2>&1
	# Adding virtual-networks to kernel modules
	echo vhost_net >> /etc/modules

        echo ---Running tasksel for fixes
	tasksel install ssh-server laptop xfce --new-install                                    1>&3

	echo ---Installing Draw.io and MarkText
	dpkg -i /var/cache/apt/archives/Draw.io/${DRAWIO_DEB} \
	        /var/cache/apt/archives/Marktext/${MARKTEXT_DEB} 				1>&3

        #Installing Libreoffice in backgroupd
        dpkg -i \$(find \$DOWNLOAD_DIR_LO/ -type f -name \*.deb)				1>&3
        pid_LO=\$!

        echo ---Installing grub and Grub-BTRFS
        update-initramfs -c -k all                                                              1>&3
        grub-install --target=x86_64-efi --efi-directory=/boot/efi \
	      --bootloader-id=debian --recheck --no-nvram --removable  				1>&3
        update-grub                                                                             1>&3
	# Grub-btrfs
	cd /opt
	git clone ${GRUB_BTRFS}									1>&3
	cd grub-btrfs
	make install										1>&3
	cd -
	systemctl enable --now grub-btrfsd || true

        echo ---Installing LibreOffice, its language pack and upgrade script
	cd /opt
	git clone ${LIBREOFFICE_UPDS} 								1>&3
	chmod +x /opt/install-libreoffice-from-web/setup.sh
        wait \$pid_LO || true
        apt install --fix-broken -y   	                                                        1>&3
        echo ------LibreOffice \$VERSION_LO installation done.

	echo ---Flatpak and Mission Center
	flatpak remote-add --if-not-exists flathub ${FLATPAK_REPO}				1>&2
	flatpak install flathub io.missioncenter.MissionCenter -y				1>&3

	echo ---Skel
	cd /opt	
	git clone ${THIS_SCRIPT}								1>&3
	cd debian-clonezilla-multistrap
	rsync -av --delete /opt/debian-clonezilla-multistrap/skel/ /etc/skel			1>&3
	set +e
	if ls /usr/bin/firefox-esr >/dev/null ; then
		sed -i 's/Icon\=firefox/Icon\=firefox\-esr/' /etc/skel/.config/xfce4/panel/launcher-4/17645275222.desktop
	fi
	set -e
	
	# echo ---Kernel
	# This is not read for prime time lol
	cd /opt	
	git clone https://github.com/alexiarstein/kernelinstall.git				1>&3


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
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive tzdata			1>&3
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-data		1>&3
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-setup		1>&3
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive keyboard-configuration 	1>&3
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive unattended-upgrades         1>&3
        sed -i '/# es_AR.UTF-8 UTF-8/s/^# //g' /etc/locale.gen
        locale-gen 											1>&3
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive locales 			1>&3
	export LANG=es_AR.UTF-8
        update-locale LANG=es_AR.UTF-8									1>&3 || true
	localectl set-locale LANG=es_AR.UTF-8								1>&3 || true
        locale												1>&3 || true

	echo LANG=es_AR.UTF-8 >> /etc/environment
        if [ \$PROC_NEEDS_UMOUNT -eq 1 ]; then
                umount /proc
        fi
	rm /etc/resolv.conf
        exit" > ${ROOTFS}/root/chroot.sh
        chmod +x ${ROOTFS}/root/chroot.sh
        chroot ${ROOTFS} /bin/bash /root/chroot.sh 2>>$ERR 3>>$LOG

cleaning_screen	
echo "Unattended upgrades -----------------------------------------"
#https://github.com/mvo5/unattended-upgrades/blob/master/README.md

mv ${ROOTFS}/etc/apt/apt.conf.d/50unattended-upgrades ${ROOTFS}/root/50unattended-upgrades.bak
	echo "---Configuration files"

# The best configurations I've read and tested
cat << EOF > ${ROOTFS}/etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Origins-Pattern {
	"origin=Debian,codename=\${distro_codename}-updates";
	"origin=Debian,codename=\${distro_codename},label=Debian";
	"origin=Debian,codename=\${distro_codename},label=Debian-Security";
	"origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
	"origin=Google LLC,codename=stable";

};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
//Unattended-Upgrade::InstallOnShutdown "true";
EOF

# The best configurations I've read and tested
cat << EOF >  ${ROOTFS}/etc/apt/apt.conf.d/10periodic
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

	echo "---Testing Scripts"

# As unattended upgrades only upgrade packages from standard repositories 
# I've added my script for libreoffice, flatpak, external git debs and
# packages of Firefox and Chrome I've downgraded for testing purposes.
cat << EOF > ${ROOTFS}/usr/local/bin/System_Upgrade
#!/bin/bash
wget -qO- ${CHROME_KEY} | tee              ${CHROME_TRUSTED}                     > /dev/null
echo "deb [signed-by=${CHROME_TRUSTED}]    ${CHROME_REPOSITORY}     stable main" > /etc/apt/sources.list.d/google-chrome.list

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

echo --Firefox, Google Chrome, Draw.io and Marktext
	for package in jgraph/drawio-desktop marktext/marktext; do
		cd /tmp
		GH_HOST=github.com gh release download -R \$package --pattern '*amd64*.deb'
	done
	apt install ./drawio-amd64*.deb ./marktext-amd64.deb $FIREFOX_PACKAGE google-chrome-stable -y

echo Listo -------------------------------
	sleep 10
EOF

# For testing Unattended upgrades I've added an option to downgrade Firefox and Chrome
# Not to use in normal cases.
cat << EOF > ${ROOTFS}/usr/local/bin/System_Downgrade
#!/bin/bash
echo Asi empezamos ----------------------
	dpkg -l | grep -E "firefox-esr|chrome"
	rm /etc/apt/sources.list.d/debian.list                  
	cp -p /root/old.list /etc/apt/sources.list.d/debian.list

echo Borramos ---------------------------
	apt remove --purge firefox-esr google-chrome-stable -y
	apt update                                               
	CHROME_OLD_VERSION=$CHROME_OLD_VERSION
	wget --show-progress -qcN -O /tmp/google-chrome-stable.deb \
	https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_\${CHROME_OLD_VERSION}_amd64.deb

echo Instalamos -------------------------
	apt install firefox-esr /tmp/google-chrome-stable.deb -y

echo Asi quedamos -----------------------
	dpkg -l | grep -E "firefox-esr|chrome"
	sleep 5
	rm /etc/apt/sources.list.d/debian.list                   &>/dev/null
	cp -p /root/new.list /etc/apt/sources.list.d/debian.list
	apt update                                             
	apt list --upgradable
	sleep 10
EOF

# To get an estimated time of upgrade I've added this script
# Not to use in normal cases.
cat << EOF > ${ROOTFS}/usr/local/bin/System_Status 
#!/bin/bash 
FOLDER=/etc/apt/apt.conf.d/ 
 for file in \$(ls \$FOLDER)
  do 
   echo \${FOLDER}\${file} --------------------------
   cat \${FOLDER}\${file}
  done
echo CUANTO FALTA-------------------------
systemctl list-timers --all | grep apt
echo ------------------------------------- 
sleep 30
EOF

# The scripts above uses this testing repositories
# Not to use in normal cases.
	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Repositories for testing scripts"
	echo "deb [trusted=yes] ${REPOSITORY_DEB}   ${DEBIAN_VERSION}          main contrib non-free non-free-firmware"  > ${ROOTFS}/root/new.list
	echo "deb [trusted=yes] ${SECURITY_DEB}     ${DEBIAN_VERSION}-security main contrib non-free non-free-firmware" >> ${ROOTFS}/root/new.list
	echo "deb [trusted=yes] ${REPOSITORY_DEB}   ${DEBIAN_VERSION}-updates  main contrib non-free non-free-firmware" >> ${ROOTFS}/root/new.list
        echo "deb [trusted=yes] ${SNAPSHOT_DEB}     ${DEBIAN_VERSION}          main contrib non-free non-free-firmware"  > ${ROOTFS}/root/old.list
	echo "deb [trusted=yes] ${SNAPSHOT_DEB}     ${DEBIAN_VERSION}-updates  main contrib non-free non-free-firmware" >> ${ROOTFS}/root/old.list

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Sudoers file for testing scripts"

# To run testing scripts without user password prompt
cat << EOF > ${ROOTFS}/etc/sudoers.d/updates
%updates ALL = NOPASSWD : /usr/local/bin/System_Upgrade 
%updates ALL = NOPASSWD : /usr/local/bin/System_Downgrade
EOF

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Shortcuts for testing scripts"

# Next three shortcuts are for easy access of testing scripts
cat << EOF > ${ROOTFS}/usr/share/applications/System_Upgrade.desktop
[Desktop Entry]
Type=Application
Icon=utilities-terminal
Exec=qterminal -e sudo /usr/local/bin/System_Upgrade
Terminal=false
Categories=Qt;System;TerminalEmulator;
Name=System_Upgrade
EOF

# Next two are not for normal use.
cat << EOF > ${ROOTFS}/usr/share/applications/System_Downgrade.desktop
[Desktop Entry]
Type=Application
Icon=utilities-terminal
Exec=qterminal -e sudo /usr/local/bin/System_Downgrade
Terminal=false
Categories=Qt;System;TerminalEmulator;
Name=System_Downgrade
EOF

cat << EOF > ${ROOTFS}/usr/share/applications/System_Status.desktop 
[Desktop Entry]
Type=Application
Icon=utilities-terminal
Exec=qterminal -e /usr/local/bin/System_Status
Terminal=false
Categories=Qt;System;TerminalEmulator;
Name=System_Status 
EOF

	let "PROGRESS_BAR_CURRENT += 1"
	echo "---Permissions for testing scripts"
	chmod +x  ${ROOTFS}/usr/local/bin/System_Upgrade \
	          ${ROOTFS}/usr/local/bin/System_Downgrade \
		  ${ROOTFS}/usr/local/bin/System_Status

	chmod 644 ${ROOTFS}/root/new.list            ${ROOTFS}/root/old.list \
	${ROOTFS}/usr/share/applications/System_Upgrade.desktop \
	${ROOTFS}/usr/share/applications/System_Downgrade.desktop \
	${ROOTFS}/usr/share/applications/System_Status.desktop

	chmod 440 ${ROOTFS}/etc/sudoers.d/updates

cleaning_screen	
echo "Fixing volumen on startup because of software bug -----------"

# Another annoying but, volumen keeps shutting down on logon.
# For months I've searched for reason but I didn't found one.
# So I've came out with a script that runs on start up until
# microphone and speakers are unmutted and at 100% volumen
cat << EOF > ${ROOTFS}/usr/local/bin/volumen
#!/bin/bash
while ! pactl info &>/dev/null; do
    sleep 1 
done
sleep 5
while [ -z "\$(pactl get-sink-volume @DEFAULT_SINK@ | grep 100)" ] ; do
             pactl set-sink-volume @DEFAULT_SINK@ 100%
             sleep 2
done &
while [ -z "\$(pactl get-sink-mute @DEFAULT_SINK@ | grep no )" ] ; do
             pactl set-sink-mute @DEFAULT_SINK@ 0
             sleep 2
done &
while [ -z "\$(pactl get-source-volume @DEFAULT_SOURCE@ | grep 100)" ] ; do
             pactl set-source-volume @DEFAULT_SOURCE@ 100%
             sleep 2
done &
while [ -z "\$(pactl get-source-mute @DEFAULT_SOURCE@ | grep no )" ] ; do
             pactl set-source-mute @DEFAULT_SOURCE@ 0
             sleep 2
done &
EOF
chmod +x ${ROOTFS}/usr/local/bin/volumen

# In this folder every user created will be fixed on logon
echo '[Desktop Entry]
Type=Application
Name=Set volumen
Comment=Fixing volumen from mutting
Exec=/usr/local/bin/volumen
NoDisplay=true
Terminal=false
X-GNOME-Autostart-enabled=true'> ${ROOTFS}/etc/xdg/autostart/volumen.desktop




cleaning_screen	
echo "Final touches for timeshift snapshots -----------------------"
# To run snapshots without user password prompt
cat << EOF > ${ROOTFS}/etc/sudoers.d/timeshift
%timeshift ALL = NOPASSWD : /usr/bin/timeshift-gtk
EOF

cleaning_screen	
echo "Setting up local admin account ------------------------------"
# I create default admin user with password and groups for upgrades and virtmanager
        echo "export LC_ALL=C LANGUAGE=C LANG=C
	useradd -d /home/$username -G sudo -m -s /bin/bash $username
	groupadd updates
	groupadd timeshift
        adduser $username updates		>/dev/null
        adduser $username timeshift		>/dev/null
        adduser $username kvm			>/dev/null
	adduser $username libvirt		>/dev/null
	adduser $username libvirt-qemu	        >/dev/null
	echo ${username}:${password} | chpasswd
	rm /tmp/local_admin.sh" > ${ROOTFS}/tmp/local_admin.sh
        chmod +x ${ROOTFS}/tmp/local_admin.sh
        chroot ${ROOTFS} /bin/bash /tmp/local_admin.sh
        
cleaning_screen	
echo "Encrypted user script creation ------------------------------"
# If you choose to encrypt your home you may use this script to automatically
# create a user with all groups and password. This script must be run outside of iso.
cat <<EOF > ${ROOTFS}/usr/local/bin/useradd-encrypt
	echo Adding local user -------------------------------------------
        read -p "What username do you want for local_encrypted_user ?: " username
        sudo useradd -d /home/\$username -c local_encrypted_user -m -s /bin/bash \$username
        sudo adduser \$username updates
        sudo adduser \$username timeshift
        sudo adduser \$username kvm
        sudo adduser \$username libvirt
        sudo adduser \$username libvirt-qemu
        
        sudo passwd \$username
        if [ "\$?" != "0" ] ; then echo Please repeat the password....; sudo passwd \$username ; fi

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
EOF
	chmod +x ${ROOTFS}/usr/local/bin/useradd-encrypt

cleaning_screen	
echo "Replacing keybindings ----------------------------------------"
# First I need to replace screenshooter app so the keybinds must be replaced.
# Second I've got used to manage windows with my key bindings. The idea is use Alt and
# Q W E   : each Key to fix selected window position as the keys represents window
# A S D   : positions. Corners for quarter screen. Middle ones to split in two the screen.
# Z X C   : Finally S to maximize.
	FILE=${ROOTFS}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
	echo --Making Backup file
	cp ${FILE} ${FILE}.bak

	let "PROGRESS_BAR_CURRENT += 1"
	echo --Replacing screenshooter for flameshot
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

	let "PROGRESS_BAR_CURRENT += 1"
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

		echo "--Mapping keys to Alt \+ ... and Super_L to Whisker menu"
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
		    ["Super_L"]="xfce4-popup-whiskermenu"
	    	)

		for key in "${!MAP[@]}"; do
		    action=${MAP[$key]}
		    echo -n "$key, "
		    if xmlstarlet sel -t -v "count(/channel/property[@name='xfwm4']/property[@name='custom']/property[@name='${key}'])" "$FILE" 2>/dev/null | grep -q '^1$'; then
			xmlstarlet ed -L \
			    -u "/channel/property[@name='xfwm4']/property[@name='custom']/property[@name='${key}']/@value" \
			    -v "$action" "$FILE"
		    else
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

cleaning_screen	
echo "Backing up logs ----------------------------------------------"
	cp ${LOG} ${ERR} ${ROOTFS}/

cleaning_screen	
echo "Unmounting ${DEVICE} -----------------------------------------"
	pgrep gpg | while read -r line
	do kill -9 "$line"			2>/dev/null || true
	done
        umount ${ROOTFS}/dev/pts                2>/dev/null || true
        umount ${ROOTFS}/proc                   2>/dev/null || true
        umount ${ROOTFS}/run                    2>/dev/null || true
        umount ${ROOTFS}/sys                    2>/dev/null || true
        umount ${ROOTFS}/tmp                    2>/dev/null || true
        umount ${ROOTFS}/tmp                    2>/dev/null || true
        umount ${ROOTFS}/dev                    2>/dev/null || true
        umount ${ROOTFS}/dev                    2>/dev/null || true
        umount ${ROOTFS}/boot/efi               2>/dev/null || true
        umount          /var/cache/apt/archives 2>/dev/null || true
        umount ${ROOTFS}/var/cache/apt/archives 2>/dev/null || true
        umount ${ROOTFS}/home                   2>/dev/null || true
        umount ${ROOTFS}/*                      2>/dev/null || true
        umount ${ROOTFS}                                    || true
	sleep 3
        umount ${ROOTFS}                                    || true
        umount ${RECOVERYFS}                    2>/dev/null || true
        umount ${CACHE_FOLDER}                  2>/dev/null || true
        umount ${CACHE_FOLDER}                  2>/dev/null || true
        umount "${DEVICE}"*                     2>/dev/null || true


PROGRESS_BAR_CURRENT=$PROGRESS_BAR_MAX
PROGRESS_BAR_FILLED_LEN=$PROGRESS_BAR_CURRENT
PROGRESS_BAR_EMPTY_LEN=0
	
cleaning_screen	
echo "END of the road!! keep up the good work ---------------------"
	mount | grep -E "${DEVICE}|${CACHE_FOLDER}|${ROOTFS}|${RECOVERYFS}" || true
	exit

######################################################################################################################################################
# TODO
# Volumen siempre vuelve a cero
	# Listo
# Nala, seleccion de repositorio optimo
	# Desde setup
	  # Listo
		# time sudo netselect -t40 $(wget -qO- http://www.debian.org/mirror/list | grep '/debian/' | grep -v download | cut -d \" -f6 | sort -u)
		# sudo nala fetch --debian trixie --auto --fetches 10 --non-free -c AR -c UR -c CL -c BR
		# sudo nala fetch --debian trixie --auto              --non-free -c AR
		# sudo nala fetch --debian trixie --auto --fetches 10 --non-free
	# Desde XFCE4
# lupa xfce4-appfinder

##########################################################################
# Discover no abre la primera vez hasta que haces sudo apt update
	# Descartado
# Mover salida principal a F2
	# Dejar en F1, lista de tareas y la tarea actual
	# Crear funcion front end
	# Listo
# Verificar progress bar en descargas desde cero
	# Listo
# Screenshot no anda por teclado xfce4-settings-editor
	# Listo
# Teclas de control de ventanas
	# Listo
	# xfconf-query  -l
	# xfconf-query -c xfce4-panel -l
	# /etc/xdg/xfce4/panel/default.xml
##########################################################################
<<BYPASS
cleaning_screen	
echo "Downloading keyboard mappings -------------------------------"
	wget --show-progress -qcN -O ${CACHE_FOLDER}/"${KEYBOARD_MAPS}" ${KEYBOARD_FIX_URL}"${KEYBOARD_MAPS}"

cleaning_screen
echo "Downloading Libreoffice -------------------------------------"
	mkdir -p $DOWNLOAD_DIR_LO >/dev/null 2>&1
        wget --show-progress -qcN -O "${DOWNLOAD_DIR_LO}/${LIBREOFFICE_MAIN_FILE}" "${LIBREOFFICE_MAIN}"
        wget --show-progress -qcN -O "${DOWNLOAD_DIR_LO}/${LIBREOFFICE_LAPA_FILE}" "${LIBREOFFICE_LAPA}"
        wget --show-progress -qcN -O "${DOWNLOAD_DIR_LO}/${LIBREOFFICE_HELP_FILE}" "${LIBREOFFICE_HELP}"
	find $DOWNLOAD_DIR_LO/ -type f -name '*.deb' -exec rm {} \; || true
        tar -xzf $DOWNLOAD_DIR_LO/LibreOffice_"${VERSION_LO}"_Linux_x86-64_deb.tar.gz -C $DOWNLOAD_DIR_LO
        tar -xzf $DOWNLOAD_DIR_LO/LibreOffice_"${VERSION_LO}"_Linux_x86-64_deb_langpack_$LO_LANG.tar.gz -C $DOWNLOAD_DIR_LO
	tar -xzf $DOWNLOAD_DIR_LO/LibreOffice_"${VERSION_LO}"_Linux_x86-64_deb_helppack_$LO_LANG.tar.gz -C $DOWNLOAD_DIR_LO

cleaning_screen
echo "Downloading Draw.io -----------------------------------------"
	mkdir -p $DRAWIO_FOLDER >/dev/null 2>&1
        wget --show-progress -qcN -O ${DRAWIO_FOLDER}/${DRAWIO_DEB} ${DRAWIO_URL}

cleaning_screen
echo "Downloading MarkText-----------------------------------------"
	mkdir -p $MARKTEXT_FOLDER >/dev/null 2>&1
        wget --show-progress -qcN -O ${MARKTEXT_FOLDER}/${MARKTEXT_DEB} ${MARKTEXT_URL}

cleaning_screen
echo "Downloading lastest clonezilla ------------------------------"
        mkdir -p $DOWNLOAD_DIR_CLONEZILLA 2>/dev/null || true
	echo "---Downloading from ${MIRROR_CLONEZILLA}"
        case ${MIRROR_CLONEZILLA} in
		Official_Fast )
			FILE_CLONEZILLA=$(curl -s "$BASEURL_CLONEZILLA_FAST" | grep -oP 'href="\Kclonezilla-live-[^"]+?\.zip(?=")' | head -n 1)
			wget --show-progress -qcN -O ${DOWNLOAD_DIR_CLONEZILLA}/"${FILE_CLONEZILLA}" ${BASEURL_CLONEZILLA_FAST}"${FILE_CLONEZILLA}" ;;
		Official_Slow )
			URL_CLONEZILLA=$(curl -S "$BASEURL_CLONEZILLA_SLOW" 2>/dev/null|grep https| cut -d \" -f 2)
			FILE_CLONEZILLA=$(echo "$URL_CLONEZILLA" | cut -f8 -d\/ | cut -f1 -d \?)
			wget --show-progress -qcN -O ${DOWNLOAD_DIR_CLONEZILLA}/"${FILE_CLONEZILLA}" "${URL_CLONEZILLA}" ;;
        esac

BYPASS
