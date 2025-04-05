# debian-clonezilla-multistrap

## Download debian live iso standard

<div>
 <a href "https://cdimage.debian.org/cdimage/weekly-live-builds/amd64/iso-hybrid/debian-live-testing-amd64-standard.iso">
For brand new devices (Weekly build)
 </a>
<br>
 <a href "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/" >
For everything else (Current build)
 </a>
</div>

## Copy Iso to pendrive using ventoy or dd

## Run live via USB

## Connect device to internet if necesary

#### - Connect cable if its possible.

#### - If wifi is only option

###### - - get wireless card name

```
ip -br a
```

###### - - if wifi card is wlan0

```
sudo ip link set wlan0 up
```

###### - - if you don't know SSID (Wifi Network name)

```
iwlist wlan0 scan | grep SSID
```

###### - - set wifi configuration

```
sudo wpa_passphrase "SSID" "your_wifi_password" | sudo tee /etc/wpa_supplicant.conf
```

###### - - connect to wireless network

```
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
```

###### - - request ip address

```
sudo dhclient wlan0
```

## Run script

```
$ sudo su -
# curl -fsSL vicentech.com.ar/notebook | bash
```
