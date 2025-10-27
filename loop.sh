#!/bin/bash
#This script is for making changes more quickly
while true; do
	vi setup.sh 
	sed -i '/^SCRIPT_DATE=/c\SCRIPT_DATE='$(date +'%Y%m%d-%H%M') setup.sh 
       	git add . 
	git commit -m "$(date +'%Y%m%d-%H%M')" 
	git push
	echo sleeping 10 second...
	head -n 2 setup.sh
	sleep 10
done
