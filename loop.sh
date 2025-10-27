#!/bin/bash
#This script is for making changes more quickly
while true; do
	vi setup.sh 
	sed -i '/^SCRIPT_DATE=/c\SCRIPT_DATE='$(date +'%Y%m%d-%H%M') setup.sh 
       	git add . 
	git commit -m "$(date +'%Y%m%d-%H%M')" 
	git push
	echo Sleeping 10 seconds ...
	grep ^SCRIPT_DATE setup.sh
	sleep 10
done
