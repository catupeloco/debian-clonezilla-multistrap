#!/bin/bash
DELAY=130
if ! dpkg -l imagemagick > /dev/null 2>&1 ; then
	echo Installing package
	sudo apt install imagemagick
fi
if command -v convert >/dev/null 2>&1 ; then
	# Without trim
	#convert -delay $DELAY -trim -loop 0 *.png animation.gif 
	# With trim but without notes
	#convert -delay $DELAY *.png -fuzz 10% -trim +repage -loop 0 animation.gif
	# With notes
	convert -delay $DELAY *.png -fuzz 10% -trim +repage \
		-gravity South -pointsize 24 -fill White \
		-annotate +0+20 "%f" \
		-loop 0 animation.gif
fi
if command -v magick >/dev/null 2>&1 ; then
	magick -delay $DELAY -trim -loop 0 *.png animation.gif 
fi

open animation.gif &

