#!/usr/bin/dash

########################################################################
#                                                                      #
#                          Description                                 #
#                                                                      #
#        Customization of new install of Linux Mint 21.3 XFCE          #
#                                                                      #
#  Optional parameters:                                                #
#     -thunderbird    Uninstall thunderbird                            #
#     -libreoffice    Uninstall libreoffice and associated packages    #
#     -bluetooth      Uninstall all bluetooth-related packages         #
#     +dvdcss         Install DVD CSS decryption support               #
#                                                                      #
#  Eg: /usr/bin/dash mint-21.3-xfce-customize.sh -bluetooth +dvdcss    #
#                                                                      #
#  NOTE: This script must be run as a normal user (not root) to        #
#        enable xfconf to function correctly. User input of sudo       #
#        password will be required at least once.                      #
#                                                                      #
#  XFCE panel configuration                                            #
#   The XFCE panel will be configured according to a supplied profile. #
#     Requires a panel profile file exported by xfce4-panel-profiles   #
#     in the same directory as this script.                            #
#     The profile file is specified by the variable 'profilename'      #
#     eg. profilename='xfce_panel_profile.tar.bz2'                     #
#                                                                      #
########################################################################

# -e Exit immediately on non-zero return value
# -u Report error on expansion of unset variable
# -x Print each command before running it
set -eu

# Check for parameters and set pkgs variable accordingly
if [ "$#" -ne 0 ]
then
    pkgs=$*
else
    pkgs=''
fi

# Current timestamp
now="$(date +"%F_%H-%M-%S")"

# Absolute path to this script
spath="$(realpath "$0")"

# Log file to be created
logfile="$spath.$now.log"

# XFCE panel profile file should be in the same directory as this script
profilename='xfce_panel_profile_linux_mint_21.3_2024-05-27.tar.bz2'
panelprofile="$(dirname -- "$spath")/$profilename"

# Linux Mint 21.3 themes
windowtheme='Daloa'
desktoptheme='Mint-Y-Dark-Purple'
icontheme='Mint-Y-Purple'
cursortheme='Breeze_Snow'

indent_print_file()
{
    # Print the file specified in the first parameter with indentation
    [ -f "$1" ] && sed 's/^/  /' "$1"
}

grub_menu()
{
    ##### Change the grub boot menu options ################

    grub='/etc/default/grub'

    printf "Checking '%s' for required changes\n" "$grub"

    # Check if grub edits are required
    grep --quiet '^GRUB_TIMEOUT_STYLE=menu' "$grub" && style_edit=0 || style_edit=1
    grep --quiet '^GRUB_TIMEOUT=10' "$grub" && timeout_edit=0 || timeout_edit=1
    grep --quiet '^GRUB_CMDLINE_LINUX_DEFAULT=""' "$grub" && cmdline_edit=0 || cmdline_edit=1
    if [ "$style_edit" -ne 0 ] || [ "$timeout_edit" -ne 0 ] || [ "$cmdline_edit" -ne 0 ]
    then
        printf "Changes are required for '%s'\n" "$grub"
        backup="$grub.$now"
        sudo cp "$grub" "$backup"
        printf "Original file '%s' backed up to '%s'\n" "$grub" "$backup"

        [ "$style_edit" -ne 0 ] && sudo sed -i 's/^GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' "$grub"
        [ "$timeout_edit" -ne 0 ] && sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=10/' "$grub"
        [ "$cmdline_edit" -ne 0 ] && sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' "$grub"
        printf "Modified '%s':\n" "$grub"
        indent_print_file "$grub"
        printf '\n'
        sudo update-grub
    else
        printf "No changes are required for '%s'\n" "$grub"
    fi
    printf '\n'
}

ntfs_fstab()
{
    ##### Change options for ntfs mounts in /etc/fstab #################

    changed=0
    repl='defaults,umask=000,uid=1000,gid=1000,windows_names' # string to replace ntfs fstab entry field 4

    src='/etc/fstab'
    tempfile="/tmp/fstab.$now"

    printf "Checking '%s' for NTFS mounts\n" "$src"

    while IFS='' read -r LINE || [ -n "${LINE}" ]
    do
        if printf '%s\n' "${LINE}" | grep '^UUID.*[[:space:]]ntfs[[:space:]]' | grep -qv "$repl"
        then
            ADD="$(printf '%s' "${LINE}" | awk '{$4="defaults,umask=000,uid=1000,gid=1000,windows_names"}1')"
            printf 'Line to be replaced:\n%s\nNew line:\n%s\n\n' "${LINE}" "${ADD}"
            printf '# %s\n' "${LINE}" >> "$tempfile"
            printf '%s\n' "${ADD}" >> "$tempfile"
            changed=1
        else
            printf '%s\n' "${LINE}" >> "$tempfile"
        fi
    done < "$src"

    if [ "$changed" -eq 1 ]
    then
        oldsrc="$src.$now"
        sudo mv "$src" "$oldsrc"
        printf "Original file '%s' backed up to '%s'\n" "$src" "$oldsrc"
        sudo mv "$tempfile" "$src"
        printf "'%s' has been modified:\n" "$src"
        indent_print_file "$src"
    else
        printf "No changes are required for '%s'\n" "$src"
    fi
    printf '\n'
}

journal_persistent()
{
    ##### Change the systemd journal configuration to 'persistent' #####

    jconf='/etc/systemd/journald.conf'
    s1="Storage=persistent"

    printf "Checking the systemd journal '%s' for persistence\n" "$jconf"

    # Check if required string s1 is found
    if grep --quiet "[[:blank:]]*$s1" "$jconf"
    then
        printf 'The systemd journal is already persistent\n'
    else
        printf "The systemd journal is NOT persistent\n"
        backup="$jconf.$now"
        sudo cp "$jconf" "$backup"
        printf "Original file '%s' backed up to '%s'\n" "$jconf" "$backup"

        # Comment out any line containing 'Storage=' if not already commented
        sudo sed -e '/Storage=/ s/^#*/#/' -i "$jconf"
        # Insert new string after [Journal] line
        sudo sed "/\[Journal\]/a $s1" -i "$jconf"
        printf "The systemd journal is now persistent:\n"
        indent_print_file "$jconf"
    fi
    printf '\n'
}

resolv_link()
{
    ##### Change the systemd /etc/resolv.conf symbolic link ####

    # This is required for name resolution if there is a DNS server on the local network
    # - systemd links '/etc/resolv.conf' to '/run/systemd/resolve/stub-resolv.conf', which sets the
    #   nameserver as 127.0.0.53

    p1='/etc/resolv.conf'
    p2='/run/systemd/resolve/resolv.conf'

    printf "Checking if '%s' points to '%s'\n" "$p1" "$p2"

    target="$(readlink -f "$p1")"
    if [ "$target" = "$p2" ]
    then
        printf "Symbolic link '%s' already points to '%s':\n" "$p1" "$target"  && indent_print_file "$target"
    else
        printf "Symbolic link '%s' does NOT point to '%s':\n" "$p1" "$target"
        backup="$p1.$now"
        sudo cp "$p1" "$backup"
        printf "Original link '%s' backed up to '%s'\n" "$p1" "$backup"
        sudo ln -sf "$p2" "$p1" && printf "'%s' now points to '%s':\n" "$p1" "$p2" && indent_print_file "$p1"
    fi
    printf '\n'
}


apt_pkgs()
{
    ##### Remove and install apt packages ##############################

    # ----- Replace default sources.list with local sources version -----

    printf "Changing apt sources to local servers\n"

    # Backup the apt sources list file
    slist='/etc/apt/sources.list.d/official-package-repositories.list'

    # Create a temporary file
    templist="$(mktemp)"

    # Save the preferred source list in the temporary file
    cat << 'EOF' > "$templist"
deb https://mirror.aarnet.edu.au/pub/linuxmint-packages victoria main upstream import backport

deb http://mirror.aarnet.edu.au/pub/ubuntu/archive jammy main restricted universe multiverse
deb http://mirror.aarnet.edu.au/pub/ubuntu/archive jammy-updates main restricted universe multiverse
deb http://mirror.aarnet.edu.au/pub/ubuntu/archive jammy-backports main restricted universe multiverse

deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOF

    # Check if current apt source list is identical to new list
    if diff --report-identical-files --ignore-all-space "$templist" "$slist"
    then
        printf "Apt source list file '%s' already contains preferred local sources.\n" "$slist"
        rm "$templist"
    else
        printf "Apt source list file '%s' differs from preferred local source list\n" "$slist"
        backupdir='/etc/apt/backup'
        sudo mkdir -p "$backupdir"
        oldlist="$backupdir/$(basename "$slist").$now"
        sudo mv "$slist" "$oldlist"
        printf "Original file '%s' has been backed up as '%s'\n" "$slist" "$oldlist"
        sudo mv "$templist" "$slist"
        printf "New apt sources list file has been created:\n"
        indent_print_file "$slist"
        printf '\n'
    fi

    # Refresh the package lists
    printf '\nUpdating the list of packages\n'
    sudo apt-get update

    # ----- Check apt package removal and installation options -----

    # Variable to store names of packages to be removed
    rem_pkgs=''

    # Variable to store names of packages to be installed
    add_pkgs=''

    # Check parameters for optional removals and installations
    while [ $# -gt 0 ]
    do
        case $1 in
            # Check if Thunderbird is to be removed
            '-thunderbird') printf 'Thunderbird to be removed\n'
                            rem_pkgs="$rem_pkgs thunderbird*"
                            ;;
            # Check if LibreOffice is to be removed
            '-libreoffice') printf 'LibreOffice to be removed\n'
                            rem_pkgs="$rem_pkgs libreoffice* python3-uno uno-libs-private ure* libuno* mythes*"
                            ;;
            # Check if Bluetooth support is to be removed
            '-bluetooth')   printf 'Bluetooth support to be removed\n'
                            rem_pkgs="$rem_pkgs pulseaudio-module-bluetooth bluetooth blueman bluez*"
                            ;;

            # Check if DVD player CSS decryption is to be supported
            '+dvdcss')      printf 'DVD CSS decryption support to be installed\n'
                            add_pkgs="$add_pkgs libdvd-pkg"
                            ;;
        esac
        shift
    done

    [ -n "$rem_pkgs" ] || [ -n "$add_pkgs" ] && printf '\n'

    #----- uninstall unwanted apt packages -----

    printf 'Removing unwanted packages\n'

    # Remove light-locker screen locker
    rem_pkgs="$rem_pkgs light-locker*"

    # Remove support for running live system from media
    rem_pkgs="$rem_pkgs casper"

    # Remove support utilities for Samba
    rem_pkgs="$rem_pkgs cifs-utils"

    # Remove java
    rem_pkgs="$rem_pkgs default-jre*"

    # Remove RAID support
    rem_pkgs="$rem_pkgs dmraid"

    # Remove point-to-point protocol support
    rem_pkgs="$rem_pkgs ppp*"

    # Remove telnet
    rem_pkgs="$rem_pkgs telnet"

    # Remove unwanted fonts
    rem_pkgs="$rem_pkgs fonts-beng* fonts-deva* fonts-gargi fonts-gubbi fonts-gujr* fonts-guru* fonts-indic fonts-kacst* fonts-kalapi fonts-khmeros-core fonts-knda fonts-lao fonts-lklug-sinhala fonts-lohit* fonts-mlym fonts-nakula fonts-navilu fonts-orya* fonts-pagul fonts-sahadeva fonts-samyak* fonts-sarai fonts-sil* fonts-smc* fonts-taml fonts-telu* fonts-thai-tlwg fonts-tibetan-machine fonts-tlwg* fonts-yrsa-rasa"

    # Remove unwanted hunspell dictionaries
    rem_pkgs="$rem_pkgs hunspell-de-* hunspell-en-ca hunspell-en-za hunspell-es hunspell-it hunspell-pt* hunspell-ru"

    # Remove unwanted hyphenation languages
    rem_pkgs="$rem_pkgs hyphen-de hyphen-fr hyphen-it hyphen-pt* hyphen-ru"

    # Remove modemmanager
    rem_pkgs="$rem_pkgs modemmanager"

    # Remove orca screen reader
    rem_pkgs="$rem_pkgs orca*"

    # Remove Onboard on-screen keyboard
    rem_pkgs="$rem_pkgs onboard*"

    # Remove braille keyboard support
    rem_pkgs="$rem_pkgs brltty libbrlapi0.8 python3-brlapi xbrlapi python3-louis liblouis*"

    # Remove text to speech support
    rem_pkgs="$rem_pkgs python3-speechd speech-dispatcher* libspeechd2 libespeak-ng1 espeak-ng-data"

    # Remove gnome-calculator
    rem_pkgs="$rem_pkgs gnome-calculator"

    # Remove warpinator
    rem_pkgs="$rem_pkgs warpinator"

    # Remove Drawing
    rem_pkgs="$rem_pkgs drawing"

    # Remove redshift
    rem_pkgs="$rem_pkgs redshift*"

    # Remove Notes
    rem_pkgs="$rem_pkgs sticky"

    # Remove Hexchat
    rem_pkgs="$rem_pkgs hexchat*"

    # Remove Transmission
    rem_pkgs="$rem_pkgs transmission*"

    # Remove Web Apps
    rem_pkgs="$rem_pkgs webapp-manager"

    # Remove celluloid
    rem_pkgs="$rem_pkgs celluloid"

    # Remove Hypnotix
    rem_pkgs="$rem_pkgs hypnotix"

    # Remove rhythmbox
    rem_pkgs="$rem_pkgs rhythmbox* librhythmbox-core10 gir1.2-rb-3.0"

    # Remove Library
    rem_pkgs="$rem_pkgs thingy"

    # Remove Backup Tool
    rem_pkgs="$rem_pkgs mintbackup"

    # Remove Compiz
    rem_pkgs="$rem_pkgs compiz* python3-compizconfig libcompizconfig0 libdecoration0"

    # Remove Welcome Screen
    rem_pkgs="$rem_pkgs mintwelcome"

    # Remove Disk Usage Analyzer
    rem_pkgs="$rem_pkgs baobab"

    # Remove Timeshift
    rem_pkgs="$rem_pkgs timeshift"

    # Remove unwanted XFCE plugins
    rem_pkgs="$rem_pkgs xfce4-cpufreq-plugin xfce4-dict xfce4-eyes-plugin xfce4-mailwatch-plugin xfce4-systemload-plugin xfce4-time-out-plugin xfce4-timer-plugin xfce4-verve-plugin xfce4-weather-plugin xfce4-xkb-plugin"

    # Remove thumbnailers (system hog)
    rem_pkgs="$rem_pkgs tumbler* ffmpegthumbnailer"

    # Remove buggy Alsa Use Case Manager that prevents PulseAudio HDMI 5.1 audio output
    # refer: https://forums.linuxmint.com/viewtopic.php?t=410508
    rem_pkgs="$rem_pkgs alsa-ucm-conf"

    # Remove all of the packages listed in 'rem_pkgs' variable and limit output for logging
    # shellcheck disable=SC2086  # override shellcheck - word-splitting required
    sudo apt-get purge -yqq $rem_pkgs

    # Remove remnant font directories - either empty or containing nothing except '.uuid' fontconfig files
    # Refer bug report: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=897040
    for f in /usr/share/fonts/truetype/*
    do
        if [ -d "$f" ] # Is a directory
        then
            num="$(find "$f" -type f | wc -l)" # Number of files in directory
            printf "directory '%s' contains '%s' entries\n" "$f" "$num"
            if [ "$num" -eq 1 ] && [ -f "$f/.uuid" ]
            then
                printf "Removing remnant '.uuid' file and font folder '%s'\n" "$f"
                sudo rm "$f/.uuid" && sudo rm --dir "$f"
            elif [ "$num" -eq 0 ]
            then
                printf "Removing empty font folder '%s'\n" "$f"
                sudo rm --dir "$f"
            fi
        fi
    done

    #----- Install required apt packages -----

    printf '\nInstalling wanted packages\n'

    # Install ssh
    add_pkgs="$add_pkgs ssh"

    # Install gparted
    add_pkgs="$add_pkgs gparted"

    # Install mate-calculator
    add_pkgs="$add_pkgs mate-calc*"

    # Install VLC
    add_pkgs="$add_pkgs vlc"

    # Install smplayer
    add_pkgs="$add_pkgs smplayer"

    # Install wanted XFCE plugins
    add_pkgs="$add_pkgs xfce4-clipman*"

    # Install XFCE panel profiles manager
    add_pkgs="$add_pkgs xfce4-panel-profiles"

    # Install all of the packages listed in 'add_pkgs' variable
    # Use non-interactive frontend to apply defaults to any dialog inputs
    # and limit output for logging
    # shellcheck disable=SC2086  # override shellcheck - word-splitting required
    sudo DEBIAN_FRONTEND=noninteractive apt-get -yqq install $add_pkgs

    case $add_pkgs in
        *'libdvd-pkg'*)    printf "libdvd-pkg installation was requested\n"
                           # Non-interactive dpkg-reconfigure required for script (uses defaults)
                           sudo dpkg-reconfigure -fnoninteractive libdvd-pkg
                           ;;
    esac

    printf '\n'
}

xfce_customize()
{
    ##### XFCE desktop customization ############################################

    xfce_load_panel_profile()
    {
        printf 'Customizing the XFCE panel\n'

        # Remove unwanted pre-installed panel layouts
        for f in /usr/share/xfce4-panel-profiles/layouts/*
        do
            [ -f "$f" ] && sudo rm "$f"
        done

        if [ -f "$panelprofile" ] && [ -r "$panelprofile" ]
        then
            # Backup existing panel profile
            profdir="$HOME/.config/xfce4/panel/profiles"
            mkdir -p "$profdir"
            xfce4-panel-profiles save "$profdir/$now.tar.bz2"

            # Remove existing panel launchers
            # They mess up configuration of new panel profile launchers (xfce bug?)
            for d in "$HOME"/.config/xfce4/panel/launcher-*
            do
                [ -d "$d" ] && rm -r "$d"
            done

            if xfce4-panel-profiles load "$panelprofile"
            then
                printf "The XFCE panel profile '%s'has been imported and applied.\n" "$panelprofile"
            else
                printf "Failed to import a panel profile from the specified file '%s'.\n" "$panelprofile"
            fi
        else
            printf "The XFCE panel has not been modified. No readable panel profile file was supplied.\n"
        fi
    }

    xfce_panel_plugins()
    {
        # ----- Settings for individual panel plugins -----

        # Get a list of panel ids
        panids="$(xfconf-query -c xfce4-panel -p /panels | grep -o '^[[:digit:]]*$' | sort -g)"

        for panel in $panids
        do
            # Get a list of plugin ids for current panel
            if plugids="$(xfconf-query -c xfce4-panel -p /panels/panel-"$panel"/plugin-ids)" # Check if property exists
            then
                plugids="$(printf '%s' "$plugids" | grep -o '^[[:digit:]]*$' | sort -g)"

                for pid in $plugids
                do
                    # Get the name of the plugin
                    pname="$(xfconf-query -c xfce4-panel -p /plugins/plugin-"$pid")"

                    # Configure the panel clock settings
                    if [ "$pname" = 'clock' ]
                    then
                        xfconf-query -c xfce4-panel -p /plugins/plugin-13/digital-date-font --create --type string --set "Sans 8"
                        xfconf-query -c xfce4-panel -p /plugins/plugin-13/digital-date-format --create --type string --set "<span size='large'>%F</span>"
                        xfconf-query -c xfce4-panel -p /plugins/plugin-13/digital-layout --create --type uint --set 1
                        xfconf-query -c xfce4-panel -p /plugins/plugin-13/digital-time-font --create --type string --set "Sans Bold 8"
                        xfconf-query -c xfce4-panel -p /plugins/plugin-13/digital-time-format --create --type string --set "<span size='large' weight='bold' letter-spacing='1500'>%T</span>"
                    fi
                done
            fi
        done
    }

    xfce_logout_dialog()
    {
        # ----- Remove unwanted options from logout dialog -----
        printf "\nRemoving logout dialog option 'Switch User'\n"
        xfconf-query -c xfce4-session -p '/shutdown/ShowSwitchUser' --create --type bool --set false
        printf "Removing logout dialog option 'Hibernate'\n"
        xfconf-query -c xfce4-session -p '/shutdown/ShowHibernate' --create --type bool --set false
        printf "Removing logout dialog option 'Hybrid Sleep'\n"
        xfconf-query -c xfce4-session -p '/shutdown/ShowHybridSleep' --create --type bool --set false
    }

    xfce_desktop_theme()
    {
        # ----- Change desktop theme to $desktoptheme value -----
        printf "Changing desktop theme to '%s'\n" "$desktoptheme"
        xfconf-query -c xsettings -p /Net/ThemeName --create --type string --set "$desktoptheme"
    }

    xfce_icon_theme()
    {
        # ----- Create icon cache -----
        for f in /usr/share/icons/*/ # Loop through icon directories only (ignore files)
        do
            if [ -f "$f/index.theme" ] # Check for index.theme file to avoid errors
            then
                printf "Updating icon cache for '%s'\n" "$f"
                sudo gtk-update-icon-cache "$f"
            fi
        done

        # ----- Change icon theme to $icontheme value -----
        printf "Changing icon theme to '%s'\n" "$icontheme"
        xfconf-query -c xsettings -p /Net/IconThemeName --create --type string --set "$icontheme"
    }

    xfce_cursor_theme()
    {
        # ----- Change cursor theme to $cursortheme value -----
        printf "Changing cursor theme to '%s'\n" "$cursortheme"
        xfconf-query -c xsettings -p /Gtk/CursorThemeName --create --type string --set "$cursortheme"
    }

    xfce_window_manager()
    {
        # ----- Window Manager settings -----
        printf "Configuring Window Manager\n"

        printf "Changing window theme to '%s'\n" "$windowtheme"
        xfconf-query -c xfwm4 -p /general/theme --create --type string --set "$windowtheme"
        xfconf-query -c xfwm4 -p /general/activate_action --create --type string --set 'none'
        xfconf-query -c xfwm4 -p /general/borderless_maximize --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/box_move --create --type bool --set false
        xfconf-query -c xfwm4 -p /general/box_resize --create --type bool --set false
        xfconf-query -c xfwm4 -p /general/click_to_focus --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/full_width_title --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/mousewheel_rollup --create --type bool --set false
        xfconf-query -c xfwm4 -p /general/move_opacity --create --type int --set 80
        xfconf-query -c xfwm4 -p /general/placement_mode  --create --type string --set 'mouse'
        xfconf-query -c xfwm4 -p /general/resize_opacity --create --type int --set 80
        xfconf-query -c xfwm4 -p /general/snap_resist --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/snap_to_border --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/snap_to_windows --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/snap_width --create --type int --set 10
        xfconf-query -c xfwm4 -p /general/tile_on_move --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/urgent_blink --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/repeat_urgent_blink --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/zoom_desktop --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/zoom_pointer --create --type bool --set true
        xfconf-query -c xfwm4 -p /general/workspace_count --create --type int --set 2 # Want 2 workspaces
    }

    xfce_terminal()
    {
        # ----- Set defaults for xfce4-terminal (version 1.04) -----

        # (NOTE: xfce4-terminal version 1.1.0 uses xfconf to store settings)

        printf 'Setting XFCE Terminal preferences\n'
        term_cfg_dir="$HOME/.config/xfce4/terminal"
        # Create the required directory if it doesn't yet exist
        mkdir -p "$term_cfg_dir"

        # Write the default settings to the xfce4-terminal config file
        cat << EOF > "$term_cfg_dir/terminalrc"
[Configuration]
BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT
BackgroundDarkness=0.700000
ColorPalette=#000000;#cc0000;#4e9a06;#c4a000;#3465a4;#75507b;#06989a;#d3d7cf;#555753;#ef2929;#8ae234;#fce94f;#739fcf;#ad7fa8;#34e2e2;#eeeeec
FontName=Monospace 9
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBellUrgent=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_IBEAM
MiscDefaultGeometry=120x32
MiscInheritGeometry=FALSE
MiscMenubarDefault=TRUE
MiscMouseAutohide=FALSE
MiscMouseWheelZoom=TRUE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
MiscMiddleClickOpensUri=FALSE
MiscCopyOnSelect=FALSE
MiscShowRelaunchDialog=TRUE
MiscRewrapOnResize=TRUE
MiscUseShiftArrowsToScroll=FALSE
MiscSlimTabs=FALSE
MiscNewTabAdjacent=FALSE
MiscSearchDialogOpacity=100
MiscShowUnsafePasteDialog=TRUE
MiscRightClickAction=TERMINAL_RIGHT_CLICK_ACTION_CONTEXT_MENU
ScrollingLines=1000
EOF
    }

    xfce_thunar()
    {
        # ----- Thunar settings -----

        printf 'Setting Thunar preferences\n'

        # Details view column order
        col_order='THUNAR_COLUMN_NAME,THUNAR_COLUMN_SIZE,THUNAR_COLUMN_SIZE_IN_BYTES,THUNAR_COLUMN_TYPE,THUNAR_COLUMN_DATE_MODIFIED,THUNAR_COLUMN_LOCATION,THUNAR_COLUMN_MIME_TYPE,THUNAR_COLUMN_PERMISSIONS,THUNAR_COLUMN_OWNER,THUNAR_COLUMN_GROUP,THUNAR_COLUMN_DATE_CREATED,THUNAR_COLUMN_DATE_ACCESSED,THUNAR_COLUMN_RECENCY,THUNAR_COLUMN_DATE_DELETED'

        # Details view visible columns (not in order)
        col_visible='THUNAR_COLUMN_DATE_MODIFIED,THUNAR_COLUMN_GROUP,THUNAR_COLUMN_MIME_TYPE,THUNAR_COLUMN_NAME,THUNAR_COLUMN_OWNER,THUNAR_COLUMN_PERMISSIONS,THUNAR_COLUMN_SIZE'

        xfconf-query -c thunar -p /default-view --create --type string --set ThunarDetailsView
        xfconf-query -c thunar -p /last-details-view-column-order --create --type string --set "$col_order"
        xfconf-query -c thunar -p /last-details-view-visible-columns --create --type string --set "$col_visible"
        xfconf-query -c thunar -p /last-location-bar --create --type string --set ThunarLocationEntry
        xfconf-query -c thunar -p /last-show-hidden --create --type bool --set true
        xfconf-query -c thunar -p /misc-confirm-move-to-trash --create --type bool --set true
        xfconf-query -c thunar -p /misc-date-style --create --type string --set THUNAR_DATE_STYLE_YYYYMMDD
        xfconf-query -c thunar -p /misc-exec-shell-scripts-by-default --create --type bool --set false
        xfconf-query -c thunar -p /misc-file-size-binary --create --type bool --set true
        xfconf-query -c thunar -p /misc-folder-item-count  --create --type string --set THUNAR_FOLDER_ITEM_COUNT_ONLY_LOCAL
        xfconf-query -c thunar -p /misc-folders-first --create --type bool --set true
        xfconf-query -c thunar -p /misc-full-path-in-tab-title --create --type bool --set true
        xfconf-query -c thunar -p /misc-full-path-in-window-title --create --type bool --set true
        xfconf-query -c thunar -p /misc-recursive-search --create --type string --set THUNAR_RECURSIVE_SEARCH_ALWAYS
        xfconf-query -c thunar -p /misc-show-delete-action --create --type bool --set true
        xfconf-query -c thunar -p /misc-single-click --create --type bool --set false
        xfconf-query -c thunar -p /misc-thumbnail-mode --create --type string --set THUNAR_THUMBNAIL_MODE_ONLY_LOCAL
        xfconf-query -c thunar -p /misc-transfer-use-partial --create --type string --set THUNAR_USE_PARTIAL_MODE_ALWAYS
        xfconf-query -c thunar -p /misc-transfer-verify-file --create --type string --set THUNAR_VERIFY_FILE_MODE_ALWAYS
        xfconf-query -c thunar -p /misc-volume-management --create --type bool --set false
    }

    xfce_power_manager()
    {
        # ----- XFCE Power Manager 4.18.1 settings for all systems -----

        printf 'Setting XFCE Power Manager preferences\n'

        # Set power button action to 'Ask'
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/power-button-action --create --type uint --set 3
        # Set sleep button action to 'Do nothing'
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/sleep-button-action --create --type uint --set 0
        # Set hibernate button action to 'Do nothing'
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/hibernate-button-action --create --type uint --set 0
        # Lock screen when system is going to sleep
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate --create --type bool --set true
        # Enable DPMS screen blanking and sleep
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled --create --type bool --set true
        # Blank screen on AC after 10 minutes
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac --create --type uint --set 10
        # Sleep screen on AC after 15 minutes
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-sleep --create --type uint --set 15
        # Screen off on AC after 20 minutes
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac-off --create --type uint --set 20

        # ----- XFCE Power Manager settings for laptops only -----

        if laptop-detect # Check if the current system is a laptop
        then
            printf 'Laptop detected: setting Power Manager preferences for laptop\n'
            # Set battery button action to 'Do nothing'
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/battery-button-action --create --type uint --set 0
            # Blank screen on battery after 10 minutes
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-battery --create --type uint --set 10
            # Sleep screen on battery after 10 minutes
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-battery-sleep --create --type uint --set 10
            # Screen off on battery after 15 minutes
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-battery-off --create --type uint --set 15
            # Inactivity on battery after 15 minutes
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-battery --create --type uint --set 15
            # Lid action on AC = sleep
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lid-action-on-ac --create --type uint --set 1
            # Lid action on battery = sleep
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lid-action-on-battery --create --type uint --set 1
            # Allow systemd logind to handle lid switch
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/logind-handle-lid-switch --create --type bool --set true
            # Critical power action = shutdown
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/critical-power-action --create --type uint --set 4
        else
            printf 'Not a laptop\n'
        fi

        # ----- XFCE Power Manager settings for ACPI backlight interfaces only -----

        # Check if any ACPI backlight interface exists
        bl_interface=0
        for f in /sys/class/backlight/*
        do
            if [ -d "$f" ]
            then
                bl_interface=1
                break
            fi
        done

        if [ "$bl_interface" -eq 1 ]
        then
            printf 'Backlight screen interface detected:\n  setting Power Manager preferences for backlight screen\n'
            # Brightness reduction timeout on AC = never
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-on-ac --create --type uint --set 9
            # Brightness level on AC after timeout = 80%
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-level-on-ac --create --type uint --set 80
            # Brightness reduction timeout on battery = 120 seconds
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-on-battery --create --type uint --set 120
            # Brightness level on battery after timeout = 25%
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-level-on-battery --create --type uint --set 25
            # Brightness exponential
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-exponential --create --type bool --set false
            # Brightness step count
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-step-count --create --type uint --set 10
            # Handle brightness keys
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/handle-brightness-keys --create --type bool --set true
            # Brightness switch ??
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-switch --create --type uint --set 0
            # Restore brightness on exit
            xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-switch-restore-on-exit --create --type uint --set 1

            # Hidden setting: Minimum brightness level: '/xfce4-power-manager/brightness-slider-min-level'
            #  From 'https://docs.xfce.org/xfce/xfce4-power-manager/preferences':
            #   Note: the minimum value should be a value relevant to your backlight interface as shown (on Linux)
            #   in the /sys/class/backlight/INTERFACE/* files. For example, a “max_brightness” value of 10,000 means
            #   that to set the minimum value at 10%, you would use 1,000 as the brightness-slider-min-level value.
            if maxb="$(xfpm-power-backlight-helper --get-max-brightness)" # Get maximum brightness
            then
                # Set minimum brightness to 10% of max brightness
                minb="$(echo "$maxb / 10" | bc)"
                xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-slider-min-level --create --type uint --set "$minb"
            else
                printf 'Failed to get backlight maximum brightness\n'
            fi
        else
            printf 'No backlight screen interface detected\n'
        fi
    }

    xfce_load_panel_profile
    xfce_panel_plugins
    xfce_logout_dialog
    xfce_desktop_theme
    xfce_icon_theme
    xfce_cursor_theme
    xfce_window_manager
    xfce_terminal
    xfce_thunar
    xfce_power_manager
}


{
    printf "Running script '%s' at %s\n\n" "$spath" "$now"
    printf "Logging to '%s'\n\n" "$logfile"

    ##### root user check ##################################################

    # This script needs to be run as a non-root user because it makes changes
    # to the user's desktop configuration.
    # Check that the user is NOT running this script as root.
    if [ "$(id -u)" -eq "0" ]
    then
        printf 'This script must be run as a normal user, not as root.\n'
        exit 1
    fi

    ##### exit trap #######################################################

    # Exit script message
    bye()
    {
        printf "\nExiting script\n '%s'\n with return value '%s'\n" "$spath" "$1"
        exit "$1"
    }

    # Trap exit and run function 'bye()'
    trap 'bye $?' EXIT

    ##### Call the configuration functions ###################

    # Change the grub menu boot options if required
    grub_menu

    # Change options for ntfs mounts in /etc/fstab
    ntfs_fstab

    # Change the systemd journal configuration if not persistent
    journal_persistent

    # Change the target of the systemd resolv.conf symbolic link if required
    resolv_link

    # Set local apt sources, remove unwanted apt packages, and install new required packages
    if [ -n "$pkgs" ]
    then
        # shellcheck disable=SC2086  # override shellcheck - word-splitting required
        apt_pkgs $pkgs
    else
        apt_pkgs
    fi

    # Customize the XFCE desktop environment
    xfce_customize

} 2>&1 | tee -a "$logfile" # Redirect all output to stdout and logfile
