---
title: Vu Meter
date: '2012-10-07'
description:
categories:
tags: []
---

I wanted a large on-screen volume indicator showing:

- The microphone amplification level, changing as you adjust it (by pressing
  keys, for example).

- Whether the microphone is muted.

- The current microphone level, changing as you speak into the microphone.

Here's what I did.

xosdd
-----

[XOSD](http://sourceforge.net/projects/libxosd/) does the real work here.
It displays text anywhere on your X desktop and it looks like an old skool TV/VCR's
display.

XOSD is a library to build into your own projects. [xosdd](http://phintsan.kapsi.fi/xosdd.html) puts XOSD into a daemon which listens on a named pipe for
commands using a custom protocol.

I made a [2-line patch](https://gist.github.com/3847336#file-xosdd-0-0-patch) to xosdd in order to support display of text in the centre of the screen.

First, I created some named pipes:

    for p in /tmp/{audio,display,vumeter,level}_control
    do
      if ! test -p "$p"
      then
        mkfifo "$p"
      fi
    done

__display_control__ and __vumeter_control__ are for communicating with xosdd:

<dl>
<dt>/tmp/display_control</dt>
<dd>For commands to display the microphone amplification level and muted state.</dd>
</dl>

<dl>
<dt>/tmp/vumeter_control</dt>
<dd>For commands to display the current microphone level.</dd>
</dl>

__audio_control__ and __level_control__ are for receving user input and
capturing raw microphone level data. They won't be used with xosdd directly
but by processes which sit in front of xosdd.

<dl>
<dt>/tmp/audio_control</dt>
<dd>For user actions: microphone volume up/down, mute/unmute and turn current level monitoring on/off. These will be sent when the user presses
corresponding keys on the keyboard.</dd>
</dl>

<dl>
<dt>/tmp/level_control</dt>
<dd>For raw microphone level data.</dd>
</dl>

I ran xosdd twice - once for displaying the amplification level and muted state
and once for displaying the current level:

    xosdd -l 4 -t 2 -f '-*-terminus-bold-r-*-*-*-240-100-100-*-*-*-*' /tmp/display_control &

    cat > /tmp/display_control <<EOF
    align center
    pos middle
    EOF

    xosdd -l 4 -f '-*-terminus-bold-r-*-*-*-240-100-100-*-*-*-*' /tmp/vumeter_control &

    cat > /tmp/vumeter_control <<EOF
    color orange
    align center
    pos middle
    EOF

Both default to displaying information in the centre of the screen. I used the
[Terminus](http://terminus-font.sourceforge.net) font here but you may wish to
use something else. XOSD only supports bitmap fonts.

Displaying amplification level and muted state
----------------------------------------------

Let's define a bash function which we can call at any time to get xosdd to
display the microphone volume level and whether it's muted.

You'll need to set __ctlIn__ to the name of your microphone under ALSA.
Run __amixer__ without arguments to list all your devices. On one of my systems
it's called __Mic__, on another it's called __Capture__.

    function display_input
    {
      amixer get "$ctlIn" | egrep -o '([0-9]+%)|(\[off\])' |
      {
      local state=On color=yellow percent
      while read v
      do
        if test "$v" = "[off]"
        then
          state=Off
          color=red
        else
          percent="$v"
        fi
      done
      cat > /tmp/display_control <<EOF
    color $color
    string 0 "Microphone: $state"
    bar 1 $percent
    EOF
      }
    }

What we're doing is calling __amixer__ to get information about the device
and filtering for amplification level and muted state. Note the egrep option
__-o__ outputs each match _part_ on a separate line.

If the microphone is muted, the colour is set to red; unmuted is yellow.
We display text for the muted state on the first line and a bar indicating
the amplification level on the second.

Monitoring current microphone level
-----------------------------------

This is a bit more complicated but not too bad. Basically, we want to read
raw microphone level data from __/tmp/level_control__ and turn it into commands
for xosdd on __tmp/vumeter_control__. 

At the same time, we want to keep the amplification and muted state display
updated so the user can press microphone up/down keys and see both the
amplification and current levels change.

    (
    while true
    do
      gawk '/^.+%$/ {print ""; fflush(); printf("string 2 \"Current Level\"\nbar 3 %s\n", $NF) >"/tmp/vumeter_control"; close("/tmp/vumeter_control")}' /tmp/level_control |
      (
      first=yes
      while read
      do
        if test $first = yes
        then
          echo 'timeout -1' > /tmp/display_control
          first=no
        fi
        display_input
      done
      echo hide > /tmp/vumeter_control
      echo -e 'hide\ntimeout 2' > /tmp/display_control
      )
    done
    ) &

Node that we need to disable the __timeout__ on the amplification and muted
display while monitoring is active.  
When we stop receiving raw microphone level data, both displays are
hidden straight away. 

Main control loop
-----------------

Now we need to control the microphone displays. We want to:

- Allow the user to increase and decrease the microphone amplification level
  and then display the level on the screen.

- Mute and unmute the microphone and display the status on the screen.

- Start and stop monitoring of the current microphone level, and its display.

Here's how we do this:

    while true
    do
      exec 3< /tmp/audio_control
      while read cmd <&3
      do
        case $cmd in
          d)
            amixer -q set "$ctlIn" ${ctlDelta}-
            display_input
            ;;
    
          u)
            amixer -q set "$ctlIn" ${ctlDelta}+
            display_input
            ;;
    
          t)
            amixer -q set "$ctlIn" toggle
            display_input
            ;;
    
          m)
            if test "$recpid"
            then
              kill $recpid
              unset recpid
            else
              arecord -vvv /dev/null -V mono > /tmp/level_control &
              recpid=$!
            fi
            ;;
        esac
      done
      exec 3<&-
    done
    ) &

The __arecord__ command supplies raw microphone level data.

You'll have to set __ctlDelta__ to the amount you want the microphone level
changed when __d__ and __u__ commands are received. This will either be a
percentage (e.g. 5%) or a number (e.g. 1) depending on your audio device.
You'll have to try both to see what works for you.

Keyboard control
----------------

As you'll have noticed, everything is controlled through sending single-letter
commands through __/tmp/audio_control__.
We could make the user echo data through this named pipe but that wouldn't be very
convenient.

Better to send a command when the user presses a key on the keyboard.
How you do this will depend on your environment.

The window manager I use is [IceWM](http://www.icewm.org). It has a
__$HOME/.icewm/keys__ file where you can specify commands to run when a key
is pressed.

Here's my __$HOME/.icewm/keys__ file:

    key "XF86AudioRaiseVolume" sh -c "test -p /tmp/audio_control && echo u > /tmp/audio_control"
    key "XF86AudioLowerVolume" sh -c "test -p /tmp/audio_control && echo d > /tmp/audio_control"
    key "XF86AudioMute" sh -c "test -p /tmp/audio_control && echo t > /tmp/audio_control"
    key "F12" sh -c "test -p /tmp/audio_control && echo m > /tmp/audio_control"

The volume up (__XF86AudioRaiseVolume__) and down (__XF86AudioLowerVolume__)
keys on the keyboard send the __u__ and __d__ commands through __/tmp/audio_control__ - resulting in the microphone volume being increased or decreased and
the level displayed on the screen.

The mute key (__XF86AudioMute__) key sends the __t__ command through __/tmp/audio_control__, resulting in the
microphone being muted or unmuted and the status displayed on the screen.

The __F12__ key sends the __m__ command through __/tmp/audio_control__.
This starts displaying the current microphone level on the screen, changing
in real time as you speak into it. Press __F12__ again to stop monitoring the
microphone level.

Putting it all together
-----------------------

The complete script is [here](https://gist.github.com/3847759#file-vu-meter-sh). Remember you need to set __ctlIn__ and __ctlDelta__ for
your device at the top.
The script calls __rkill.sh__ from my [previous post](/script-cleanup)
to clean things up at the end - press ^C or Enter to exit.

Finally, here are some screenshots of my Vu Meter in action:

[![Microphone On]({{urls.media}}/vu-meter/mic-on.png "Microphone On")]({{urls.media}}/vu-meter/mic-on.png)

[![Microphone Monitor]({{urls.media}}/vu-meter/mic-mon.png "Microphone Off")]({{urls.media}}/vu-meter/mic-mon.png)

[![Microphone Off]({{urls.media}}/vu-meter/mic-off.png "Microphone Monitor")]({{urls.media}}/vu-meter/mic-off.png)

