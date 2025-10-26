#!/bin/bash
while true; do
	vi setup.sh 
	sed -i '/^SCRIPT_DATE=/c\SCRIPT_DATE='$(date +'%Y%m%d-%H%M') setup.sh 
       	git add . 
	git commit -m "$(date +'%Y%m%d-%H%M')" 
	git push
	echo dormir....
	wget -qO- vicentech.com.ar/notebook | head -n 2 
	shellcheck script.sh
	sleep 10
done
