#!/bin/bash
DELAY=130
if ! dpkg -l imagemagick > /dev/null 2>&1 ; then
	echo Installing package
	sudo apt install imagemagick
fi
if command -v convert >/dev/null 2>&1 ; then
	convert -delay $DELAY -loop 0 *.png animation.gif 
fi
if command -v magick >/dev/null 2>&1 ; then
	magick -delay $DELAY -loop 0 *.png animation.gif 
fi

open animation.gif &

