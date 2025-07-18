#!/bin/bash
reset # Re-Set terminal for multiple runs
set -e # Exit on error

echo "Installing dependencies for this script ---------------------"
	MULTISTRAP_URL=http://ftp.debian.org/debian/pool/main/m/multistrap/multistrap_2.2.11_all.deb
	cd /tmp
        apt update							 >/dev/null 2>&1
	apt install --fix-broken -y					 >/dev/null 2>&1
        apt install dosfstools parted gnupg2 unzip \
		             wget curl openssh-server -y		 >/dev/null 2>&1
	systemctl start sshd						 >/dev/null 2>&1
	wget --show-progress -qcN -O /tmp/multistrap.deb ${MULTISTRAP_URL}
	apt install /tmp/multistrap.deb -y				 >/dev/null 2>&1

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
LOG=/tmp/notebook.log
ERR=/tmp/notebook.err

PART_EFI_END=901
PART_CZ_END=12901

WIFI_DOMAIN="https://git.kernel.org"
WIFI_URL="${WIFI_DOMAIN}/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain" 
WIFI_MAX_PARALLEL=10

KEYBOARD_FIX_URL=https://mirrors.edge.kernel.org/pub/linux/utils/kbd/
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

APT_CONFIG="`command -v apt-config 2> /dev/null`"
eval $("$APT_CONFIG" shell APT_TRUSTEDDIR 'Dir::Etc::trustedparts/d')

# NOTE: Fictional variables below are only for title proposes ########################################
INCLUDES_DEB="${RAMDISK_AND_SYSTEM_PACKAGES} \
apt initramfs-tools zstd gnupg systemd dkms \
${XFCE_AND_DESKTOP_APPLICATIONS} \
xfce4 xorg dbus-x11 gvfs cups system-config-printer thunar-volman synaptic xarchiver vlc flameshot mousepad lm-sensors \
xfce4-battery-plugin       xfce4-clipman-plugin     xfce4-cpufreq-plugin     xfce4-cpugraph-plugin    xfce4-datetime-plugin    xfce4-diskperf-plugin \
xfce4-fsguard-plugin       xfce4-genmon-plugin      xfce4-mailwatch-plugin   xfce4-netload-plugin     xfce4-places-plugin      xfce4-sensors-plugin  \
xfce4-smartbookmark-plugin xfce4-systemload-plugin  xfce4-timer-plugin       xfce4-verve-plugin       xfce4-wavelan-plugin     xfce4-weather-plugin  \
xfce4-xkb-plugin           xfce4-whiskermenu-plugin xfce4-dict xfce4-notifyd xfce4-taskmanager        xfce4-indicator-plugin   xfce4-mpc-plugin      \
thunar-archive-plugin      thunar-media-tags-plugin light-locker 	     gnome-keyring	      ntfs-3g                  \
${FONTS_PACKAGES_AND_THEMES}  \
fonts-dejavu-core fonts-droid-fallback fonts-font-awesome fonts-lato fonts-liberation2 fonts-mathjax fonts-noto-mono fonts-opensymbol fonts-quicksand \
fonts-symbola fonts-urw-base35 gsfonts arc-theme \
task-xfce-desktop task-ssh-server task-laptop qterminal \
${COMMANDLINE_TOOLS} \
sudo vim wget curl dialog nano file less pciutils lshw usbutils bind9-dnsutils fdisk file git zenity build-essential gcc \
${CRON_TOOLS} \
anacron cron cron-daemon-common \
${NETWORK_PACKAGES_AND_DRIVERS} \
network-manager iputils-ping util-linux iproute2 bind9-host isc-dhcp-client network-manager-gnome xfce4-power-manager powermgmt-base xfce4-power-manager-plugins ifupdown ethtool \
wpasupplicant amd64-microcode intel-microcode firmware-amd-graphics bluetooth bluez bluez-firmware blueman \
firmware-linux-free firmware-linux-nonfree firmware-misc-nonfree \
firmware-myricom firmware-netronome firmware-netxen firmware-qlogic \
firmware-ast firmware-ath9k-htc firmware-atheros firmware-bnx2 firmware-bnx2x firmware-brcm80211 firmware-cavium \
firmware-realtek-rtl8723cs-bt firmware-siano firmware-sof-signed firmware-tomu firmware-zd1211 hdmi2usb-fx2-firmware firmware-ipw2x00 firmware-ivtv \
firmware-libertas atmel-firmware dahdi-firmware-nonfree dfu-util dnsmasq-base \
${AUDIO_PACKAGES} \
pavucontrol pulseaudio firmware-intel-sound \
${BOOT_PACKAGES}  \
grub2-common grub-efi grub-efi-amd64 \
${FIREFOX_AND_CHROME_DEPENDENCIES}  \
fonts-liberation libasound2 libnspr4 libnss3 libvulkan1 firefox-esr \
${LANGUAGE_PACKAGES}  \
console-data console-setup locales \
${SPANISH} \
task-spanish task-spanish-desktop qterminal-l10n firefox-esr-l10n-es-ar ispanish wspanish \
${ENCRYPTION_PACKAGES}  \
ecryptfs-utils rsync lsof cryptsetup \
${LIBREOFFICE_DEPENDENCIES}  \
libxslt1.1 git \
${UNATTENDED_UPGRADES_PACKAGES}  \
unattended-upgrades apt-utils apt-listchanges software-properties-gtk \
${PLASMA_DISCOVER} \
plasma-discover plasma-discover-backend-flatpak plasma-discover-common plasma-discover-backend-fwupd \
${VIRTUALIZATION_PACKAGES}  \
qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients bridge-utils virtinst libvirt-daemon virt-manager \
${OBS_STUDIO} \
ffmpeg obs-studio" #https://ppa.launchpadcontent.net/obsproject/obs-studio/ubuntu/pool/main/o/obs-studio/


#aspell-es aspell os-prober

DEBIAN_VERSION=bookworm
INCLUDES_BACKPORTS="linux-image-amd64/${DEBIAN_VERSION}-backports firmware-iwlwifi/${DEBIAN_VERSION}-backports"
REPOSITORY_DEB="http://deb.debian.org/debian/"

CHROME_REPOSITORY="https://dl.google.com/linux/chrome/deb/"
CHROME_KEY="https://dl.google.com/linux/linux_signing_key.pub"

# https://www.spotify.com/es/download/linux/
SPOTIFY_REPOSITORY="https://repository.spotify.com"
SPOTIFY_KEYS="https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg"

LOCALIP=$(ip -br a | grep -v ^lo | awk '{print $3}' | cut -d\/ -f1)

########################################################################################################################################################

# for clear screen on tty (clear doesnt work)
printf "\033c"

echo "============================================================="
echo "Installing on Device ${DEVICE} with ${username} as local admin
	- Debian ${DEBIAN_VERSION} with :
		- XFCE.
		- Firefox ESR.
		- Virtual Machine Manager (KVM/QEMU).
		- OBS Studio.
		- Unattended upgrades.
		- Optional : encrypted home.
        - Backport kernel for newer HW compatibility.
        - Backport Wifi drivers.
	- External latest :
		- Libreoffice.
		- Google Chrome. 
		- Clonezilla recovery.
		- Spotify.
	- With Overprovisioning partition ${PART_OP_PERCENTAGE} %"

echo "To Follow extra details use: 
	tail -F $LOG or Ctrl + Alt + F2
	tail -F $ERR or Ctrl + Alt + F3"

grep iso /proc/cmdline >/dev/null && \
echo "For remote access during installation, you can connect via ssh
	---Connect via: ssh user@$LOCALIP
	---password is \"live\""

echo "============================================================="

echo "Inicializing logs tails -------------------------------------"
	# TODO make symbolic link for chroot
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
[ "$REPARTED" == yes ] && mkfs.vfat -n EFI        ${DEVICE}1    > /dev/null 2>&1
[ "$REPARTED" == yes ] && mkfs.ext4 -L RESOURCES  ${DEVICE}4    > /dev/null 2>&1
		 	  mkfs.ext4 -L CLONEZILLA ${DEVICE}2    > /dev/null 2>&1
			  mkfs.ext4 -L LINUX      ${DEVICE}3    > /dev/null 2>&1

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
        mkdir -p ${ROOTFS}/var/cache/apt/archives               > /dev/null 2>&1 
        mount --bind ${CACHE_FOLDER} ${ROOTFS}/var/cache/apt/archives

echo "---Cleaning cache packages if necesary"
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

echo "Downloading keyrings ----------------------------------------"
        echo ---Creating Directories in ${ROOTFS}
        mkdir -p ${ROOTFS}/etc/apt/sources.list.d/
        mkdir -p ${ROOTFS}${APT_TRUSTEDDIR}  
	
	echo "---Google Chrome"
        wget -qO - ${CHROME_KEY} \
        | awk '/-----BEGIN PGP PUBLIC KEY BLOCK-----/ {inBlock++} inBlock == 1 {print} /-----END PGP PUBLIC KEY BLOCK-----/ && inBlock == 1 {exit}' \
        | gpg --dearmor > ${ROOTFS}${APT_TRUSTEDDIR}google-chrome.gpg
        echo deb [arch=amd64] ${CHROME_REPOSITORY} stable main    > ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list

	echo "---Spotify"
	curl -sS ${SPOTIFY_KEYS} | gpg --dearmor --yes -o ${ROOTFS}/etc/apt/trusted.gpg.d/spotify.gpg
	echo "deb ${SPOTIFY_REPOSITORY} stable non-free" > ${ROOTFS}/etc/apt/sources.list.d/multistrap-spotify.list

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

<<'BYPASS'
echo "Downloading Wifi Drivers ------------------------------------"
	mkdir ${CACHE_FOLDER}/firmware 2>/dev/null || true
	cd ${CACHE_FOLDER}/firmware
set +e
	echo ---Building list
	mapfile -t files < <(curl -s $WIFI_URL | grep iwlwifi | grep href | cut -d \' -f 2 | grep -v LICENCE)

	total=${#files[@]}
	done_count=0

	show_progress() {
	  percent=$(( done_count * 100 / total ))
	  echo -ne "---Downloading: ${percent}%      (${done_count}/${total})\r"
	}
	
	for line in "${files[@]}"; do
	  wget -qc "${WIFI_DOMAIN}/${line}" &
	  while [[ $(jobs -rp | wc -l) -ge $WIFI_MAX_PARALLEL ]]; do
		sleep 0.1
		show_progress
	  done
	  done_count=$((done_count + 1))
	  show_progress
	done
	
	echo -e "\n---Download complete"
	mkdir -p ${ROOTFS}/lib/firmware/ 2>/dev/null || true
	cp ${CACHE_FOLDER}/firmware/* ${ROOTFS}/lib/firmware/ 
set -e
BYPASS
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

echo "Multistrap --------------------------------------------------"
echo "---Creating configuration file"
echo "[General]
arch=amd64
directory=${ROOTFS}
cleanup=false
unpack=true
omitdebsrc=true
bootstrap=Debian GoogleChrome Backports Spotify
aptsources=Debian Spotify Backports

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
components=main non-free-firmware
noauth=true

[GoogleChrome]
arch=amd64
packages=google-chrome-stable
source=${CHROME_REPOSITORY}
suite=stable
noauth=true
components=main

[Spotify]
arch=amd64
packages=spotify-client
source=${SPOTIFY_REPOSITORY}
suite=stable
components=non-free
noauth=true" > ${CACHE_FOLDER}/multistrap.conf

echo "---Running multistrap"
	mkdir ${ROOTFS}/proc  2>/dev/null || true
	umount ${ROOTFS}/proc 2>/dev/null || true
        mount --bind /proc ${ROOTFS}/proc || true
        SILENCE="Warning: unrecognised value 'no' for Multi-Arch field in|multistrap-googlechrome.list"
        set +e ####################################################
	multistrap -f ${CACHE_FOLDER}/multistrap.conf >$LOG 2> >(grep -vE "$SILENCE" > $ERR)
	if [ "$?" != "0" ] ; then
		echo "------It failed but don\'t worry"
		echo "---Removing older versions AGAIN so multistrap wont fail"
                ls ${CACHE_FOLDER}/ | awk -F'_' '{print $1}' | sort | uniq -d | while read line
                do rm -v ${CACHE_FOLDER}/${line}*
                done
		echo "---Running multistrap AGAIN"
		rm -rf ${ROOTFS}/var/lib/dpkg
		set -e ############################################
		multistrap -f ${CACHE_FOLDER}/multistrap.conf >$LOG 2> >(grep -vE "$SILENCE" > $ERR)
	fi
	set -e ####################################################

        #FIXES
        if [ -f ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list ] ; then
                rm ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list
        fi

# TODO: Next big change migration to mmdebstrap for multistrap discontinuation :( SAD FACE	
# mmdebstrap --variant=apt --architectures=amd64 --mode=root --format=directory \
#                --include="${INCLUDES_DEB}"                    "${DEBIAN_VERSION}" "${ROOTFS}" \
#  "deb [trusted=yes] http://deb.debian.org/debian               ${DEBIAN_VERSION}           main contrib non-free" \
#  "deb [trusted=yes] http://security.debian.org/debian-security ${DEBIAN_VERSION}-security  main contrib non-free" \
#  "deb [trusted=yes] http://deb.debian.org/debian               ${DEBIAN_VERSION}-updates   main contrib non-free" \
#  "deb [trusted=yes] http://deb.debian.org/debian               ${DEBIAN_VERSION}-backports main" \
#  "deb [arch=amd64]  https://dl.google.com/linux/chrome/deb/    stable                      main"

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

        PROC_NEEDS_UMOUNT=0
        if [ ! -e /proc/uptime ]; then
                mount proc -t proc /proc
                PROC_NEEDS_UMOUNT=1
        fi
	
	echo ---Enabling virtual-networks
	/usr/sbin/libvirtd & 		>/dev/null 2>&1
	#virsh net-list
	virsh net-autostart default	>/dev/null 2>&1
	#virsh net-list
	pkill libvirtd			>/dev/null 2>&1

	echo ---Adding virtual-networks to kernel modules
	echo vhost_net >> /etc/modules

        echo ---Running tasksel for fixes
	tasksel install ssh-server laptop xfce --new-install                                    >>\$LOG 2>>\$ERR
        #apt remove --purge xfce4-terminal                                                      >>\$LOG 2>>\$ERR

        #Installing Libreoffice in backgroupd
        dpkg -i \$(find \$DOWNLOAD_DIR_LO/ -type f -name \*.deb)				>>\$LOG 2>>\$ERR &
        pid_LO=$!

        echo ---Installing grub
        update-initramfs -c -k all                                                              >>\$LOG 2>>\$ERR
        grub-install --target=x86_64-efi --efi-directory=/boot/efi \
	      --bootloader-id=debian --recheck --no-nvram --removable  				>>\$LOG 2>>\$ERR 
        update-grub                                                                             >>\$LOG 2>>\$ERR

        echo ---Installing LibreOffice and its language pack
	echo -----Cloning script for future updates
	cd /opt
	echo nameserver 8.8.8.8 > /etc/resolv.conf
	git clone https://github.com/catupeloco/install-libreoffice-from-web 			>>\$LOG 2>>\$ERR
	chmod +x /opt/install-libreoffice-from-web/setup.sh
	rm /etc/resolv.conf
        wait $pid_LO
        apt install --fix-broken -y                                                             >>\$LOG 2>>\$ERR
        echo ------LibreOffice \$VERSION_LO installation done.

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
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive tzdata			>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-data		>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-setup		>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive keyboard-configuration 	>>\$LOG 2>>\$ERR
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive unattended-upgrades         >>\$LOG 2>>\$ERR
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
sleep 1
echo Actualizando-------------------------
echo --Debian
apt upgrade -y
echo --Libreoffice
/opt/install-libreoffice-from-web/setup.sh
echo Listo -------------------------------
sleep 5'                                                             > ${ROOTFS}/usr/local/bin/actualizar

	echo '#!/bin/bash
rm /etc/apt/sources.list.d/multistrap-debian.list        &>/dev/null
cp -p /root/old.list /etc/apt/sources.list.d/multistrap-debian.list
apt remove --purge firefox-esr google-chrome-stable -y   &>/dev/null
apt update                                               &>/dev/null
CHROME_VERSION=131.0.6778.264-1
wget --show-progress -qcN -O /tmp/google-chrome-stable.deb \
https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${CHROME_VERSION}_amd64.deb

apt install firefox-esr /tmp/google-chrome-stable.deb -y &>/dev/null
dpkg -l | grep -E "firefox-esr|chrome"
sleep 5
rm /etc/apt/sources.list.d/multistrap-debian.list        &>/dev/null
cp -p /root/new.list /etc/apt/sources.list.d/multistrap-debian.list
apt update                                               &>/dev/null ' > ${ROOTFS}/usr/local/bin/desactualizar

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
	echo 'deb [arch=amd64] http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware'                                > ${ROOTFS}/root/new.list

	echo 'deb [arch=amd64] https://snapshot.debian.org/archive/debian/20250101T023759Z/ bookworm main contrib non-free non-free-firmware
deb-src https://snapshot.debian.org/archive/debian/20250101T023759Z/ bookworm main contrib non-free non-free-firmware' > ${ROOTFS}/root/old.list

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
Name=_Desactualizar '                              > ${ROOTFS}/usr/share/applications/desactualizar.desktop

	echo '[Desktop Entry]
Type=Application
Icon=utilities-terminal
Exec=qterminal -e sudo /usr/local/bin/actualizar
Terminal=false
Categories=Qt;System;TerminalEmulator;
Name=_Actualizar '                                 > ${ROOTFS}/usr/share/applications/actualizar.desktop

echo '[Desktop Entry]
Type=Application
Icon=utilities-terminal
Exec=qterminal -e /usr/local/bin/status
Terminal=false
Categories=Qt;System;TerminalEmulator;
Name=_Status '                                     > ${ROOTFS}/usr/share/applications/status.desktop 

echo "
%updates ALL = NOPASSWD : /usr/local/bin/actualizar 
%updates ALL = NOPASSWD : /usr/local/bin/desactualizar " > ${ROOTFS}/etc/sudoers.d/updates

	echo "---Permissions for testing scripts"
	chmod +x  ${ROOTFS}/usr/local/bin/actualizar ${ROOTFS}/usr/local/bin/desactualizar ${ROOTFS}/usr/local/bin/status

	chmod 644 ${ROOTFS}/root/new.list            ${ROOTFS}/root/old.list \
	${ROOTFS}/usr/share/applications/desactualizar.desktop \
	${ROOTFS}/usr/share/applications/actualizar.desktop \
	${ROOTFS}/usr/share/applications/status.desktop

	chmod 440 ${ROOTFS}/etc/sudoers.d/updates

echo "Setting up local admin account ------------------------------"
        echo 'export LC_ALL=C LANGUAGE=C LANG=C
	useradd -d /home/'$username' -c local_admin_user -G sudo -m -s /bin/bash '$username'
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
	mount | grep -E "${DEVICE}|${CACHE_FOLDER}|${ROOTFS}|${RECOVERYFS}"
