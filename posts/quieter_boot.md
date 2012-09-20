---
title: Quieter Boot
date: '2012-09-16'
description:
categories:
tags: [boot, syslinux, freedos, usb, kexec-loader, tinycorelinux]
---

One of my PCs has a rather unique boot sequence:

1. [Syslinux](http://www.syslinux.org), from an SD card and configured to chain
   load the next stage.

2. A pre-boot environment, [FreeDOS](http://www.freedos.org), from the SD card.
   The pre-boot environment does the following:

    1. Check if a USB stick is inserted. If there is one inserted, then continue
       to the next stage in the boot sequence. Otherwise...

    2. Display a message asking the user to insert the USB stick.

    3. Wait 20 seconds for the USB stick to be inserted.

    4. If the USB stick is inserted within those 20 seconds, then continue to
       the next stage in the boot sequence, but pass a flag indicating to boot
       into a maintenance mode. Otherwise...

    5. Go to a DOS prompt.

    FreeDOS makes a great pre-boot environment - it's super fast to boot, very
    small and you don't have to faff about producing custom initrds. I used
    [Bret Johnson](http://bretjohnson.us)'s USBDOS drivers to do the USB stick
    detection.

3. [kexec-loader](http://www.solemnwarning.net/kexec-loader/), from the SD card
   (via [Linld](http://busybox.net/~vda/linld/)) and configured to boot the next
   stage from the USB stick. I used kexec-loader here because it contains
   USB 2.0 drivers, so loading the next stage is much faster than using the
   BIOS's legacy emulation mode.

4. The fantastic [Tiny Core Linux](http://distro.ibiblio.org/tinycorelinux/welcome.html),
   from the USB stick, booting into X with some custom extensions.

Now, this all works well but I wanted to reduce the copious level of noise
(messages) displayed while booting to a minimum.

Syslinux
--------

Syslinux itself makes some noise. I had to [patch](https://gist.github.com/3748363#file_syslinux_4.03.patch) it to make it quiet. You can see the patch is mostly about supressing
__puts__ and __printf__. You can also see that the copyright notice is still
displayed.

I also added some new control codes to Syslinux display files:

- __STX__ (\002): Home the cursor without clearing the screen.
  I found this useful if I displayed a message in the centre of the screen.
  Any text that was displayed afterwards was less likely to cause the screen
  to scroll.

- __SOH__ (\001): Hide the cursor.
  Useful for a completely black screen.

- __ETX__ (\003): Change palette register 1 (normally blue) to bright white,
  using [INT 10H 1000H](http://webpages.charter.net/danrollins/techhelp/0137.HTM).

In the end I used just __ETX__ in my Syslinux display file.

FreeDOS
-------

Confession: I didn't bother supressing messages in FreeDOS. Therefore, the
FreeDOS copyright notice was displayed momentarily until the next stage.
If you want to remove this notice, you'll have to patch FreeDOS and recompile
from source.

I did use [nansi.sys](http://help.fdos.org/en/hhstndrd/base/nansi.htm)
to display a greeting message in blue before starting kexec-loader with Linld:

    echo ESC[34mWelcome!ESC[0m
    linld image=vmlinux initrd=initrd.img ...

(Note: you'll need to get the literal ESC character into your bat file,
e.g. using ^V in Vim and then pressing the Escape key).

Of course, since we used __ETX__ in the Syslinux display file, this message
was actually shown in bright white.

kexec-loader
------------

To hide all further messages until X starts, I passed the following kernel
parameters to kexec-loader using Linld:

    quiet
    console=tty2
    vt.default_blu=0,0,0,0,255,0,0,0,0,0,0,0,0,0,0,0
    vt.default_grn=0,0,0,0,255,0,0,0,0,0,0,0,0,0,0,0
    vt.default_red=0,0,0,0,255,0,0,0,0,0,0,0,0,0,0,0

__quiet__ hides most kernel log messages, but unfortunately not all of them -
as the [description](http://www.kernel.org/doc/Documentation/kernel-parameters.txt) of this parameter says:

> __quiet__&nbsp;&nbsp;&nbsp;&nbsp;[KNL] Disable most log messages

__console=tty2__ makes all kexec-loader's kernel messages go to tty2 - i.e. they
are hidden because tty1 is shown by default.

The __vt.default_*__ parameters change the Linux kernel's console palette.
As you can see, I set every colour in the palette to black, _except_ palette
colour 4. This hid all messages except for those displayed using palette number
4.

The Linux kernel's console palette is in a [different order](http://git.kernel.org/?p=linux/kernel/git/stable/linux-stable.git;a=blob;f=drivers/tty/vt/vt.c#l1045)
to __INT 10H__'s:

    unsigned char color_table[] = { 0, 4, 2, 6, 1, 5, 3, 7,
                                           8,12,10,14, 9,13,11,15 };

Palette colour 4 here corresponds to __INT 10H__'s palette register 1 (i.e.
normally blue). So the effect of this is to hide everything except the
__Welcome!__ message we displayed in the FreeDOS pre-boot environment.

Tiny Core Linux
---------------

To keep Tiny Core Linux quiet, I got kexec-loader to boot it with these
parameters:

    quiet
    vt.default_blu=0,0,0,0,255,0,0,0,0,0,0,0,0,0,0,0
    vt.default_grn=0,0,0,0,255,0,0,0,0,0,0,0,0,0,0,0
    vt.default_red=0,0,0,0,255,0,0,0,0,0,0,0,0,0,0,0

I repeated __vt.default_*__ because otherwise the Linux kernel resets the
palette to the default colours.

I didn't boot with __console=tty2__ because I wanted the flexibility to display
messages later in the boot process.

Summary
-------

My goal was to reduce the amount of noise during boot for a PC booting from
Syslinux into FreeDOS then (via Linld) from kexec-loader into Tiny Core Linux.

- I patched Syslinux to remove all messages apart from the copyright one.
- I patched Syslinux with an extra display file control code to turn the blue
  palette register into bright white.
- I displayed a welcome message in FreeDOS using this colour.
- I started kexec-loader with options to turn all except this colour into black.
- I did the same when starting Tiny Core Linux.

The effect of this is that the following are shown before kexec-loader starts:

1. The BIOS blurb.
2. The Syslinux copyright message.
3. The FreeDOS copyright message.
4. The welcome message.

After kexec-loader starts, and until X comes up, only the welcome message is
displayed.

If you wanted to do more, you could clear the screen in the Syslinux display
file and remove the copyright messages from Syslinux and FreeDOS.

