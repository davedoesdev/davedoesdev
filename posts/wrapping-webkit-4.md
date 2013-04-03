---
title: "Wrapping Webkit (Part 4 - Chromium/Bash)"
date: '2013-03-29'
description:
categories:
tags: [webkit, html, javascript, chromium, bash, inotify]
---

This is the last in my short series about getting data into and out of a
Web application running in Webkit. Previously I wrote about hosting Webkit
[in a Vala application using GTK+](/wrapping-webkit-part-1-gtk%2B-vala),
[in a C++ application using Qt](/wrapping-webkit-part-2-qt-c%2B%2B) and
[in a Python application using Qt Quick](/wrapping-webkit-part-3-qt-quick-python).

This time I'm going to do something a bit different: How can I pass data to
and from a Javascript application running in Chromium? I'll be using Bash
and command line utilities. Be on the lookout for egregious hacks!

# Getting data in

Getting data into Chromium is easy &mdash; write it to a file and read it using
[XMLHttpRequest](http://www.w3.org/TR/XMLHttpRequest/).
jQuery's [ajax](http://api.jquery.com/jQuery.ajax/) function is a convenient way of doing this. Chromium needs the __--allow-file-access-from-files__
command line option to read files from a Web app loaded from local disk.

An alternative is to pass the data as part the URL. However, the data would
have to be available before Chromium was launched. I wanted to start Chromium
and read the data in the background. Also, having the data visible in
Chromium's omnibox isn't always desirable.

# Getting data out

Getting data out of Chromium is much more difficult, and this is where a hack
is required. Javascript running in a Web page can save data to the local
filesystem using the following mechanisms:

- [Web Storage](http://www.w3.org/TR/webstorage/) is basically a key-value
  store, which Chromium implements using [SQLite](http://www.sqlite.org/).
  On Linux it's stored in __~/.config/chromium/Default/Local Storage__.</dd>

- [IndexedDB](http://www.w3.org/TR/IndexedDB/) is a key-value store like Web
  Storage but with searching and key traversal functionality. Chromium implements IndexedDB
  using [LevelDB](https://code.google.com/p/leveldb/).</dd>

- The [FileSystem API](http://dev.w3.org/2009/dap/file-system/pub/FileSystem/)
  is a Chromium-only way for Web applications to access a single, sandboxed
  section of the local filesystem.

We could store data in Javascript using Web Storage, IndexedDB or the
FileSystem API and access it from outside Chromium. In all three cases, we'd be
tied to Chromium's implementation: SQLite for WebStorage, LevelDB for
IndexedDB, the Chromium-only FileSystem API and where Chromium chooses to store
the data for all three.

I wanted to see if I could get data out of a Web app in a way which isn't
dependent on Chromium's internals. It would be nice if the technique worked
on Firefox too.

## Using inotify (aka the hack)

So here's what I ended up doing:

- Create 256 files, named from 0 to 255. Put some dummy data in each file.

- Set up an [inotify](http://en.wikipedia.org/wiki/Inotify) watch on the files
  so we get notified when each is opened.

- When one of the files is opened, it means the Web app is passing us a
  byte of data, with a value equal to the name of the file.

- In the Web app (Javascript), for each byte of data we want to pass out,
  use __jQuery.ajax__ to open and read from the file which has the same name
  as the byte's value.

OK so it's a bit of a hack but it does actually work! It's not the fastest
data transfer mechanism but it doesn't rely on Chromium internals &mdash;
it works for Firefox too.

Also, it relies on inotify reporting file events in the order they occurred.
We'll be serializing reads in Javascript (we won't start a read until a previous
one has completed) so it should be okay.

# Bash script

The easiest way to set this up is to write a shell script. Here's what it does:

1. Parse command line arguments, including options to:
    - Specify the browser to use (default to Chromium).
    - Specify the URL to load into the browser (default to __test.html__ in the
      same directory as the script).
    - Use fullscreen mode when launching the browser.

    <pre><code>url="file://$PWD/test.html"
    browser=chromium-browser

    for arg in "$@"
    do
      case "$arg" in
        -u=*|--url=*) url="$(echo "$arg" | sed 's/^.*=//')";;
        -f|--fullscreen) args="$args --kiosk";;
        -b=*|--browser=*) browser="$(echo "$arg" | sed 's/^.*=//')";;
      esac
    done</code></pre>

2. Allow the browser to read files from local disk. For Chromium:

        if test "$browser" = chromium-browser -o "$browser" = google-chrome
        then
          args="$args --allow-file-access-from-files"
        fi

   You can't turn this on from the command line for Firefox. You'll need to use
   __about:config__ to set __security.fileuri.strict\_origin\_policy__
   to __false__ instead. Note this will apply globally for all sites so be
   careful. It would be a good idea to use [Firefox profiles](http://support.mozilla.org/en-US/kb/profiles-where-firefox-stores-user-data)
   to stop the setting being used in your normal browsing.

3. Define some variables we'll use later for specifying the paths of:
   a temporary file, a file for storing data read from standard input and
   a directory to hold the 0..255 files.

        tmp_file="$(dirname "$0")/data.tmp"
        data_file="$(dirname "$0")/data.txt"
        bytes_dir="$(dirname "$0")/bytes"

4. Create files named 0 to 255 in a new directory.

        mkdir -p "$bytes_dir"
        for byte in {0..255}
        do
          echo "$byte" > "$bytes_dir/byte$byte"
        done

5. Handle Ctrl-C by killing everything and removing all files and directories
   we may have created.

        trap "\"$(dirname "$0")/rkill.sh\" --skip=$BASHPID $$; rm -rf "$bytes_dir" "$tmp_file" "$data_file"; exit" SIGINT

   (more about __rkill.sh__ [here](/script-cleanup))

5. Launch the browser in the background, passing it the URL to load.
   When the browser exits, remove the directory and the 0..255 files.

        (
        "$browser" $args "$url"
        rm -rf "$bytes_dir"
        ) &

6. Read from standard input, again in the background. Write the data to a
   temporary file and then rename the temporary file to the file that the
   Web app is expecting the data to be in. Doing it this way ensures the Web
   app never reads partial data.

        cat | (
        cat > "$tmp_file"
        mv "$tmp_file" "$data_file"
        ) &

7. Use [inotifywait](https://github.com/rvoicilas/inotify-tools/wiki#wiki-info) to monitor for:
    - Any of the 0..255 files being opened.
    - The directory we created for them being deleted.

   <pre><code>inotifywait -m -e OPEN -e DELETE\_SELF "$bytes_dir"/* |</pre></code>

8. When one of the files is opened, print a byte to standard ouput, value equal
   to the file name.
   When the directory is deleted (i.e. the browser has exited), clean up and
   exit.

        (gawk 'BEGIN{i=0; j=0; code=0}{
          if (index($2, "DELETE_SELF") > 0)
          {
            printf("\n");
            exit;
          }
          printf("%c", gensub(/^(.*\/byte)([0-9]+)$/, "\\2", 1, $1) + 0);
        }'
        "$(dirname "$0")/rkill.sh" --skip=$BASHPID $$
        rm -f "$tmp_file" "$data_file"
        )

   As you can see, I'm using Awk to process the output from inotifywait.

# Test Web page

Finally, let's look at __test.html__. It's a bit longer than the same page in
my previous posts.

First, we need to include jQuery since we'll be using it for reading files:

    <html>
    <head>
    <script type="text/javascript" src="jquery-1.9.1.min.js"></script>
    <script type="text/javascript">

Now we'll define a function, __exit__, which should pass a message to the
Bash script. For each byte in the message, it'll need to read from a file
with the corresponding name. It should do this for each byte _in turn_ &mdash;
i.e. only read from a file when the previous read has completed.

    function exit(msg, i)
    {
        if (i === msg.length)
        {
            window.close();
            return;
        }

The first argument, __msg__, is the message and the second argument, __i__,
is the index of the byte to process next. When we reach the end of the message,
you can see we close the browser. Note for Firefox you'll need to use
__about:config__ to set __dom.allow\_scripts\_to\_close\_windows__ to __true__.
Again, make sure you don't have this set for your normal browsing.

We use __jQuery.ajax__ to read from the file named after the byte at index __i__:

        $.ajax(
        {
            url: "bytes/byte" + msg.charCodeAt(i),
            cache: false,
            mimeType: 'text/plain',
            success: function (data)
            {
                exit(msg, i + 1);
            },
            error: function ()
            {
                window.close();
            }
        });
    }

Notice we make sure the browser doesn't cache the result because if the message
contains the same byte more than once, we want the inotify handler to fire every
time. Once the file has been read, we call __exit__ again to process the next
byte in the message. If an error occurs, we just close the browser.

Next we'll define a global, __bridge__, with two methods. First, a method
to get the data that the Bash script has read from standard input (or an empty
string if it's not yet available):

    var bridge = {
        getData: function (cb)
        {
            $.ajax(
            {
                url: 'data.txt',
                cache: false,
                mimeType: 'text/plain',
                success: function (data)
                {
                    cb(data);
                },
                error: function ()
                {
                    cb('');
                }
            });
        },

Second, a method to sit in front of the __exit__ function we defined above,
converting its argument to UTF-8 and starting things off at index 0:

        exit: function (msg)
        {
            if (!this.exiting)
            {
                // convert to UTF-8 (http://ecmanaut.blogspot.co.uk/2006/07/encoding-decoding-utf8-in-javascript.html)
                exit(unescape(encodeURIComponent(msg)), 0);
                this.exiting = true;
            }
        }
    };

It also guards against being called more than once.

We'll also need a function which polls for data read from standard input:

    function check_data()
    {
        bridge.getData(function (data)
        {
            if (data === "")
            {
                setTimeout(check_data, 1000);
            }
            else
            {
                $('#data').text(data);
            }
        });
    }
    </script>
    </head>

You can see it writes the data into an element with id __data__.

Finally, here's the body of the page:

    <body onload='check_data()'>
    <p>
    data: <span id="data"></span>
    </p>
    <input type="button" value="Exit" onclick="bridge.exit('goodbye from Javascript')">
    </body>
    </html>

When the page loads, we start polling for the data from standard input.
You can see the __data__ element we write the data into.
There's also a button which will pass a message out to the Bash script and exit
the browser when clicked.

Test it all out by piping data to the Bash script like this:

    echo 'Hello World!' | ./browser_example.sh

You can find all the source from this article [here](https://gist.github.com/5240269).
