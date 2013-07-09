---
title: Script Cleanup
date: '2012-09-29'
description: A script which kills a process and all its descendants
categories:
tags: [script, linux, bash]
---

Sometimes I like to write complicated [Bash](http://www.gnu.org/software/bash/bash.html) scripts. You know the ones - multiple background subprocesses,
communicating through pipes or fifos. In fact, my next post will be about
one I've written recently.

At the end of the script, you have to make sure all those background processes
are killed.

rkill.sh
--------
I've pulled code to do this out into a separate file, [rkill.sh](https://gist.github.com/3808428#file-rkill-sh).
It's listed below, but I've split it into sections here to make it easier to
explain.

    #!/bin/bash
    
    function contains
    {
      local arr=("${!1}")
    
      for v in "${arr[@]}"
      do
        if test "$v" = "$2"
        then
          return 0
        fi
      done
    
      return 1
    }

The __contains__ function returns 0 if its second argument is in the array whose
name is passed as the first argument. Otherwise it returns 1.
    
    function rkill
    {
      local pid=$1 p d s
    
      done_pids=("${done_pids[@]}" $pid)

The __rkill__ function is where the action happens. It takes one parameter -
the ID of the process at the root of the tree to kill (__pid__). This is added
to the list of processes already dealt with so we don't end up in a loop.
    
      if test $pid -eq $BASHPID
      then
        return
      fi

Don't kill the process running this script!
    
      if ! contains skip[@] $pid
      then
        kill -s STOP $pid
        while true
        do
          s=$(ps -o pid,stat | grep $pid | awk '{print substr($NF, 0, 1)}')
          if test -z "$s" -o "$s" = T
          then
            break
          fi
          sleep 1
        done
      fi

The __skip__ array can contain a list of processes not to kill. If __pid__
isn't in this list, then suspend it so it doesn't continue to create new
children. We also wait until __ps__ shows the process is suspended.

Then, even if we skip a process, we recurse to its children:
    
      while true
      do
        d=0
    
        for p in $(pgrep -P $pid)
        do
          if ! contains done_pids[@] $p
          then
            d=1
            rkill $p
            break
          fi
        done
    
        if test $d -eq 0
        then
          break
        fi
      done

What we do is find all the children of __pid__ and call __rkill__ on
each of them, checking we haven't seen a process before recursing.

We keep going until there are no child processes left that we haven't seen
before.
    
      if ! contains skip[@] $pid
      then
        if ! contains nokill[@] $pid
        then
          kill $pid
        fi
        kill -s CONT $pid
      fi
    }

Finally, if we're not skipping __pid__ and it's not in the __nokill__ array
then we kill it. We need to resume the process even after killing it so it can
die.

Note that __nokill__ is slightly different to __skip__. A __nokill__ process
is suspended while its children are killed; a __skip__ process is not.
    
    for arg in "$@"
    do
      case $arg in
        --skip=*) skip=("${skip[@]}" $(echo "$arg" | sed 's/^.*=//'));;
        --nokill=*) nokill=("${nokill[@]} $(echo "$arg" | sed 's/^.*=//')");;
        *) pid="$arg";;
      esac
    done  

This is a simple command line parser which accumulates __skip__ and __nokill__
process IDs. Any other argument is assumed to be the process ID at the root
of the tree to kill.
    
    if test $pid
    then
      rkill $pid
    fi

Finally, we kick things off by calling __rkill__ with the process ID passed on
the command line.

Example
-------

To check it works, put __rkill.sh__ somewhere on your path and run something
like this:

    #!/bin/bash

    ( echo 12; sleep 20; echo 54;
      ( ls; ls ) > /dev/null &
      ( sleep 30; (echo foo) ) &
      echo 90
    ) | (
      read x
      rkill.sh --skip=$BASHPID $$
      echo finished
    )

This script should suspend and then terminate without leaving any new processes
behind. It'll display __finished__ after killing all subprocesses - any extra
cleanup can be done after __rkill.sh__ returns.

