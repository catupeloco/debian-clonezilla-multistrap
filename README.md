# debian-clonezilla-multistrap

# Introduction

This project builds upon my previous work, ***"debian-multistrap"***, which was designed to set up an X2go server.
In this instance, the goal is to build a laptop/desktop image with the following components :

- Debian Trixie with :
  - XFCE.
    - With custom skel for task bar.
    - With custom keybindings for windows manager.
  - Flameshot (replace for screenshots).
  - Qterminal (replace for xfce terminal).
  - Mousepad.
  - VLC.
  - QBittorrent.
  - OBS Studio.
  - KeePassXC.
  - Remmina, x11vnc and ssvnc.
  - Unattended upgrades.
  - Virtual Machine Manager (KVM/QEMU).
  - Wifi and bluetooth drivers.
  - NTFS support (to read Windows Partitions).
  - Optional : 
    - Firefox ESR.
    - encrypted home.
- External latest :
  - Libreoffice.
  - Google Chrome. 
  - Clonezilla recovery.
  - Spotify.
  - Flatpak
    - Mission Center (task manager).
  - SyncThing.
  - X2Go Client.
  - Draw.io.
  - Keymaps for tty.
  - Optional : Firefox Rapid Release (from Mozilla repository).

# Requirements

- ***Internet :*** wired connections is easier, but Wi-Fi setup steps are included below.
  - Libreoffice, Google Chrome and Clonezilla will be downloaded directly.
- ***USB thumb drive :*** if you choose to use ```dd``` command, it will be formatted.
- ***Laptop or desktop with:***
  - UEFI support.
  - 32 GB or more storage. The drive will be partitioned as follows :
    1. EFI partition
    2. Clonezilla + Recovery partition
    3. System partition
    4. Temporary partition to download resources (can be deleted afterward to allow for [Over-provisioning](https://www.kingston.com/en/blog/pc-performance/overprovisioning)

# Installation Steps.

## Step 1 : Download Debian Live ISO (Standard).

- [For brand-new devices (Weekly build)](https://cdimage.debian.org/cdimage/weekly-live-builds/amd64/iso-hybrid/debian-live-testing-amd64-standard.iso)

- [For everything else (Current build)](https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/)

## Step 2 : Copy ISO to USB Drive using Ventoy or ```dd```.

- [Download Ventoy](https://www.ventoy.net/en/download.html)
  
  - [Ventoy guide](https://www.ventoy.net/en/doc_start.html)

- To create a bootable USB from the iso file, replace the file path and USB device as needed :
  
  ```
  sudo dd bs=4M if=/path/to/file.iso of=/dev/sdX status=progress oflag=sync
  ```

## Step 3 : Boot into Live System via USB.

## Step 4 : Connect Device to the Internet (if needed).

- #### ***Wired connection*** is preferred.

- #### ***If Wi-Fi is only option:***
  
  - ###### Get the name of your wireless card :
    
    ```
    ip -br a
    ```
  
  - ###### NO: Enable the interface (replace ```wlp0s20f3``` with your interface name) :
    
    ```
    NO: sudo ip link set wlp0s20f3 up
    ```
  
  - ###### Scan for available networks :
    
    ```
    sudo iw dev wlp0s20f3 scan | grep SSID
    ```
  
  - ###### Set up the Wi-Fi configuration :
    
    ```
    sudo wpa_passphrase "SSID" "your_wifi_password" | sudo tee /etc/wpa_supplicant.conf
    ```
  
  - ###### Connect to wireless network :
    
    ```
    sudo wpa_supplicant -B -i wlp0s20f3 -c /etc/wpa_supplicant.conf
    ```
  
  - ###### Request an IP address :
    
    ```
    sudo dhcpcd wlp0s20f3
    ```

## Step 5 : Run the installation Script

```
wget -qO- vicentech.com.ar/laptop | bash
```

  ***Note :*** The default ISO keyboard layout is English. Refer to the layout map to find special charactes :
  <img title="English Keyboard Layout" src="images/Qwerty.png"> https://en.wikipedia.org/wiki/Keyboard_layout

## Installation walkthrough

- ***Grub from ISO :*** just hit enter.
  
  <img title="1.Grub_from_ISO"               src="images/1.Grub_from_ISO.png">

- ***Installation command :*** make sure all characters are correct before hitting enter.
  
  <img title="2.Installation_Command"        src="images/2.Installation_Command.png">

- ***Installing dependencies :***  
  
  <img title="3.Dependencies"                src="images/3.Dependencies.png">

- ***Disk confirmation prompt :*** beware from this point storage will be erased. If you have more than one storage, choose the right one. 
  
  <img title="4.Disk_confirmation_prompt"    src="images/4.Disk_confirmation_prompt.png">

- ***Clonezilla Mirror Selection :*** By default fastest mirror is selected. In case of failure you may choose the slower one.
  
  <img title="5.Clonezilla_Mirror_Selection" src="images/5.Clonezilla_Mirror_Selection.png">

- ***Local admin Creation :*** Type a username as you like. 
  
  <img title="6.Username_Prompt"             src="images/6.Username_Prompt.png">

- ***Local admin password prompt :*** You will be asked twice for password confirmation.
  
  <img title="7.Password_Prompt_1"           src="images/7.Password_Prompt_1.png">
  <img title="8.Password_Prompt_2"           src="images/8.Password_Prompt_2.png">

- ***Overprovisioning Partition :*** As a advise from ssd manufacturers you may leave a percentage of the storage empty for performance and life span. The best way to do it is to fraction other paritions without this percentage and then delete this partition. For my advantage I use this space for temporally download all requiered packages. You may leave it, use it or delete the partition for OP.
  
  <img title="9.Overprovisioning_Selection" src="images/9.Overprovisioning_Selection.png">

- ***Installation Screen 1 :*** As you may see below only titles will be shown on the default tty1. If you like to follow the internals of installation, you could connect remotelly by ssh or use "Control + Alt + F2" for standard output, and "Control + Alt + F3" for errors. Some downloads may be shown as a progress bar.
  
  <img title="10.Installation_1" src="images/10.Installation_1.png">
  <img title="11.Installation_2" src="images/11.Installation_2.png">
  <img title="12.Installation_3" src="images/12.Installation_3.png">
  <img title="13.Installation_4" src="images/13.Installation_4.png">
  <img title="14.Installation_5" src="images/14.Installation_5.png">
  <img title="15.Installation_6" src="images/15.Installation_6.png">

- ***Clean disk first run :*** 
  On the first run, the disk will be cleaned according to the following logic: 
  
  - If the disk ***does not already*** follow this project layout, it will be ***fully repartioned and formatted.***
  - If the disk ***already has*** the expected layout, only partition 1 to 3 will be reformatted. The 4th partition will be preserved.

Extra-packages such as Clonezilla will be downloaded directly from the official mirrors.
***Please note:*** From Argentina (and possibly other locations), downloading Clonezilla may take a long time. 

GOOD THINGS TAKE TIME.

# Post-installation Steps

- ## Optional : Create a non-sudoer user with encrypted home
  
  - Boot into the installed Debian system.
  - Log in with the admin user created during installation.
  - Open a terminal and run ```useradd-encrypt``` script.
    - Provide the username.
    - Enter your sudo password.
    - Enter the password for the new user twice.
    - Enter a passphrase for emergency decryption.
    - Enter the user's password again.
    - Wait for automatic reboot automatically.

- ## Optional : Make any additional customizations before proceeding.

- ## Create a Debian image for recovery.
  
  - Boot into the ***"Restaurar"*** option.
    - Select ***"Salvar imagen"*** option.
    - When prompted, enter a recovery password twice.
    - Wait for clonezilla to complete its process. The system will shut down afterward.

- ## Optional : Remove the 4th partition to allow Over-Provisioning (OP).
  
  - Boot into Debian and log in with a sudo-enabled user.
  - Open a terminal and run :
    - ```lsblk | grep disk```
      - Identify the correct device name (e.g., ```sda```, ```nvme0n1```, etc.).
    - ```sudo parted /dev/${DEVICE} --script rm 4```
      - Replace ```${DEVICE}``` with the actual name.

- ## Optional : Take a full disk image.
  
  - Boot the PC using a USB drive with your preferred imaging software.
  - Connect an external storage to allocate the image.
  - Follow the software's manual steps to capture the image.

- ## Start using the device.
  
  - On the first boot, the device will automatically restore itself.
    - This is done to reduce the size of the disk image created earlier.

# Enjoy :rocket:
