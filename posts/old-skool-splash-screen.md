---
title: Old Skool Splash Screen
date: '2012-09-22'
description:
categories:
---

After I [got rid of most boot messages](/quieter-boot), I wanted to display a
splash screen.

[Syslinux](http://www.syslinux.org) can show a splash screen but it doesn't stay around until X starts.
I could have taken the easy route and put [Usplash](https://launchpad.net/usplash)
or [Splashy](http://alioth.debian.org/projects/splashy/) into [Tiny Core Linux](http://distro.ibiblio.org/tinycorelinux/)
on my USB stick.

But no! I took another route. I decided to use
[Zgv](http://www.svgalib.org/rus/zgv/). Zgv is an [SVGAlib](http://www.svgalib.org)-based image viewer,
so it runs on the Linux console. Feed it an image early on in the Tiny
Core __init.d__ scripts and voila, a splash screen!

SVGALib
-------

It wasn't all plain sailing though. The first thing was to get SVGAlib compiling
on a modern Linux distribution (let's assume Ubuntu here). Of course, I had
to make some [patches](https://gist.github.com/3764135#file_svgalib_1.4.3.patch). There wasn't much to
fix:

- Only build static libraries. I didn't need to use SVGAlib with anything else
  on Tiny Core Linux.

- Don't bother with assembly optimizations.

- Various type, macro and syntax changes - probably due to a tightening-up of
  compiler rules.

Zgv
---

I also [patched](https://gist.github.com/3767626#file_zgv_5.9.patch) Zgv - not to fix compile errors, but to:

-   Support [LSS16](http://www.syslinux.org/wiki/index.php/SYSLINUX#Display_graphic_from_filename:)
    image files. LSS16 is an arbitrary format which Syslinux supports for
    displaying splash screens. I wanted to use the same files in Syslinux later
    on if I wanted to.

    I implemented the main logic for loading LSS16
    images as separate [source](https://gist.github.com/3767626#file_readlss16.c)
    and [header](https://gist.github.com/3767626#file_readlss16.h) files.

- Remove support for JPEG, PNG and TIFF images in Zgv. I didn't need these
  libraries so it was pointless to add them to Tiny Core Linux and load them
  from the USB stick.

- Add support for 640 x 480 x 16 colours [planar](http://en.wikipedia.org/wiki/Planar_(computer_graphics\)) VGA mode. 

    SVGALib's __vga_getmodeinfo__ returns 0 bytes per pixel for planar VGA modes.
    For my graphics adapter it was only returning one 640 x 480 mode, and it was
    planar.

    Since I was only going to be using this mode for 640 x 480, I made a hack
    and changed only the graphics mode selection algorithm. From the patch:

    <pre><code>+  if(bpp==4) bytepp=0; else bytepp=(bpp+7)/8;</code></pre>

- Don't dither LSS16 images to 16 colours! In 16 colour mode, Zgv dithers
  images, even if they have 16 colours or less. It defines its own palette
  and maps the image onto it. Obviously, it's better to use the 16 colours in
  the image itself.

- Fix a SEGV, caused by not setting a global (__image_palette__).

Making LSS16 files
------------------
 
I created my splash screen in [Inkscape](http://inkscape.org) as a vector
graphic, __splash.svg__. Here's the script I used for creating a LSS16 file,
__splash.rle__, from it:

    inkscape -e splash-pic.png -w 300 -h 300 -b '#000000' splash.svg
    convert splash-pic.png \
            -bordercolor '#000000' \
            -border 170x40 \
            -gravity north \
            -background '#000000' \
            -extend 640x480 \
            -gravity south \
            -fill '#ffffff' \
            -pointsize 30 \
            -annotate +0+50 'Almost there, just a few moments...' \
            splash.png
    convert splash.png -colors 16 splash.ppm
    ppmtolss16 '#000000=0' '#ffffff=7' < splash.ppm > splash.rle

In other words:

1. Export the file from Inkscape, 300 x 300 on black background.

2. Use [ImageMagick](http://www.imagemagick.org) to:

    1. Add a border around the image - 40px of space at the top and extending
       the width to 640px by adding 170px either side.

    2. Extend the height of the image to 480px.

    3. Add a message 50px from the bottom of the image.

3. Use ImageMagick to convert the image to 16 color PPM format.

4.  Use __ppmtolss16__ to convert the PPM image to LSS16 format. __ppmtolss16__ comes with Syslinux. 
    The __.rle__ extension because LSS16 uses run-length encoding compression.

    Note how I set the background colour to index 0 and the foreground color to
    index 7. Zgv doesn't treat these indices as special, but Syslinux sets the
    console's text foreground and background to the colours at these indices.

Displaying the Splash Screen in Tiny Core
-----------------------------------------

Finally, we need to call Zgv to display the image while Tiny Core Linux is
loading. I do this by putting the following at the start of
__/etc/init.d/tc-config__:

    [ -f /proc/cmdline ] || /bin/mount /proc
    if grep -q quiet /proc/cmdline
    then
      echo -en "\033[2J\033[1;1H"
      exec > /dev/null
      if ! ps -o comm | grep zgv
      then
        sh -c "zgv -p -m \"640 480 4\" --viewer-16col-colour /usr/share/splash.rle &"
      fi
    fi

This clears the screen, homes the cursor, redirects output from the
script to __/dev/null__ and then runs Zgv. __-p__ hides the loading progress
bar. __-m__ selects the display mode to 640 x 480 x 4 bits per pixel.
__--viewer-16col-colour__ seems a bit superfluous given that it knows there
are 4 bits per pixel, but Zgv needs it anyway.

To stop Zgv before X loads, I put the following at the end of
__/etc/init.d/tc-config__:

    if grep -q quiet /proc/cmdline
    then
      sudo killall -INT zgv
      while ps -o comm | grep zgv; do sleep 1; done
    fi

Note I only run Zgv if __quiet__ was passed as a kernel boot parameter.

You might want to [remaster]( http://wiki.tinycorelinux.net/wiki:remastering)
your Tiny Core image to put these changes in.
