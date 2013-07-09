---
title: "Wrapping Webkit (Part 1 - GTK+/Vala)"
date: '2012-11-10'
description: Embedding a Web user interface in a Vala application
categories:
tags: [webkit, html, javascript, gtk, vala]
---

I wanted to write a user interface in HTML and Javascript but run the rest of
the application in some other language that has access to system facilities.
Therefore I needed
bi-directional communication between the user interface and the application
logic. I also wanted to run it as a normal standalone application.

[GTK+](http://www.gtk.org/) and [Qt](http://qt-project.org/) both let you embed
the [Webkit](http://www.webkit.org) browser engine to do this. Another option
is to run [Chromium](http://www.chromium.org/Home) in kiosk mode.

This post is about using GTK+'s Webkit component. Future posts will look at
Qt and Chromium.

Vala
----

I'm not a big fan of C++. It's much too complicated for me. Add in GTK+'s [wacky reference
counting](http://www.demko.ca/blog/posts/200705_gtkmm_refcoutning.txt) and using
GTK+ to run Webkit from C++ gets a big no from me.

Fortunately, there are [many other language bindings for GTK+](http://www.gtk.org/language-bindings.php). Although I could have used most of these, I wanted to
try something new - so I chose [Vala](https://live.gnome.org/Vala).

Vala's pretty interesting:

- It's statically typed.
- It's a a lot like Java/C#, with a similar set of language features.
- But it's compiled, via source translation to C.
- The only dependency it has is [GLib](http://developer.gnome.org/glib/),
  which is available pretty much everywhere nowadays.
- It does the GTK+ reference counting for you.
- It's officially supported by GNOME/GTK+.

What's not to like?!

<a id="example"></a>Example
===========================

We'll have two classes in our example:

1. A main class for parsing command line options and initializing things.
2. A window class which embeds Webkit and puts it in a GTK+ window.

Main class
----------

As with most languages, in Vala the startup function is called __main__ and
it's declared as a static method:

    using Gtk;

    class WebkitExample.Main : GLib.Object
    {
        public static int main(string[] args)
        {
            ...
        }
    }

Our example is going to support the following command line options:

<dl>
<dt>url</dt>
<dd>which URL to load into Webkit</dd>
</dl>

<dl>
<dt>fullscreen</dt>
<dd>run in full screen (kiosk) mode</dd>
</dl>

<dl>
<dt>hidecursor</dt>
<dd>hide the mouse cursor</dd>
</dl>

<dl>
<dt>debug</dt>
<dd>enable the Webkit developer tools in the context menu</dd>
</dl>

It also needs to create and show our window class (which embeds Webkit) and
initialize GTK+.

First we set the defaults for the command line options:

    try
    {
        url = "file://" + Path.get_dirname(FileUtils.read_link("/proc/self/exe")) + "/test.html";
    }
    catch (FileError e)
    {
        stderr.printf("%s\n", e.message);
        return 1;
    }
    
    fullscreen = false;
    hidecursor = false;
    debug = false;

You'll see by default we load a file named __test.html__ in the same directory
as the program.

Parsing command line options in Vala is pretty easy. You list the options in an
array, along with the type of argument expected (if any), some help text and in
which variable to put the argument. For our options:

    static string url;
    static bool fullscreen;
    static bool showcursor;
    static bool debug;

    const OptionEntry[] options =
    {
        { "url", 'u', 0, OptionArg.STRING, out url, "page to load", "URL" },
        { "fullscreen", 'f', 0, OptionArg.NONE, out fullscreen, "run in fullscreen mode", null },
        { "hidecursor", 'h', 0, OptionArg.NONE, out hidecursor, "hide mouse cursor", null },
        { "debug", 'd', 0, OptionArg.NONE, out debug, "enable web developer tools", null },
        { null }
    };

Then you create an __OptionContext__ with a description of the program,
and add the options to it:

    OptionContext context = new OptionContext("- Webkit example");
    
    context.add_main_entries(options, null);

To parse the options, call the __parse__ method:

    try
    {
        context.parse(ref args);
    }
    catch (OptionError e)
    {
        stderr.printf("%s: failed to parse arguments: %s\n", prog_name, e.message);
        return 1;
    }

To initialize GTK+, we add an optional .gtkrc file (I don't use it but it's
good practice) and call __Gtk.init__:

    Gtk.rc_add_default_file("webkit-example.gtkrc");
    Gtk.init(ref args);

Then we can create our GTK+ window which embeds Webkit (see the next section
for details of our window class):

    MainWindow w = new MainWindow(hidecursor, debug);

Make it full screen if the command line option was passed:

    if (fullscreen)
    {
            w.fullscreen();
    }

Show it and all its children (including Webkit):

    w.show_all();

And then load the URL into Webkit (this is a method on our window class which
ends up calling into Webkit):

    w.load(url);

Finally, we have to enter the GTK+ main loop which makes sure things are
displayed and user input events are dispatched properly:

    Gtk.main();

Window class
------------

This class is going to do the following:

- Inherit from the GTK+ Window class so it's a... erm... window.
- Create a new Webkit browser component and add it to the window.
- Configure things like the the window size and Webkit settings.
- Arrange for the mouse cursor to be hidden if the user requested to do so.
- Expose a function to Javascript running in Webkit which returns data read
  from standard input. This shows we can get data from Vala into the Web app.
- Expose a function to Javascript running in Webkit which writes its argument to
  standard output and then terminates the application. This shows we can call Vala
  functions and pass them data from the Web app.

Setting things up
-----------------

Here's how we declare our window class:

    public class WebkitExample.MainWindow : Window
    {
        private const string TITLE = "Webkit Example";
    
        private WebView webview;
        private Gdk.Cursor cursor;
        private static string data;

You can see we inherit from __Window__ and define a title which we'll set 
below. There are private instance variables for a Webkit component (__webview__),
an invisible mouse cursor (__cursor__), and data read from standard
input (__data__).

Next we define the constructor:

    public MainWindow (bool hidecursor, bool debug)
    {  
        title = TITLE;
        set_default_size(800, 600);
        destroy.connect(Gtk.main_quit);
        
        if (hidecursor)
        {
            cursor = new Gdk.Cursor(Gdk.CursorType.BLANK_CURSOR);
        }

Simple stuff here:

- Set the window title and size.
- Connect the __destroy__ event which is fired when the user closes the window
  to __Gtk.main_quit__ function which exits the application.
- If the user wants to hide the cursor, set __cursor__ to an invisible cursor.

Now we can create a Webkit component and initialize it:

        webview = new WebView();
        
        WebSettings settings = webview.get_settings();
        
        settings.enable_plugins = true;
        settings.enable_scripts = true;
        settings.enable_universal_access_from_file_uris = true;

Here I'm enabling plugins and scripts. I'm also enabling documents loaded from
the local system to make network calls. We won't use it in this example but
you'll need it if, for example, you have a user interface bundled with your
application that ends up talking to a Web service somewhere.

Next we need to set up the Webkit developer tools (also known as the Web
inspector).

    if (debug)
    {
        settings.enable_developer_extras = true;
        webview.web_inspector.inspect_web_view.connect(getInspectorView);
    }

We enable the _Inspect Element_ option in the right-click menu of
the main Webkit component, which opens the Web inspector (and the rest of the
developer tools like the console and network tracer)

The __inspect\_web\_view__ event is fired when the user selects the menu option.
We connect it to a method (__getInspectorView__) which returns the Webkit
component we want the Webkit inspector to display itself in.
The __getInspectorView__ method is described in the next section.

Now we need to connect up another event, __window\_object\_cleared__. This is
fired by Webkit when a new page is loaded. We'll connect it to a method which
exposes functions for Javascript in the page to call:

    webview.window_object_cleared.connect(addApp);

We'll get to __addApp__ a bit later on.

Finally, we finish configuring Webkit and add it to the main window:

    get_default_session().add_feature_by_type = typeof(CookieJar);
       
    ScrolledWindow sWindow = new ScrolledWindow(null, null);
    sWindow.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        
    sWindow.add(webview);
    add(sWindow);

You can see that we enable cookies and allow the Webkit component to scroll.

Returning a Webkit component for the Webkit inspector
-----------------------------------------------------

Here's __getInspectorView__, which we hooked up to the __inspect\_web\_view__
event in the constructor. 
This involves creating separate window and Webkit components for
the Web inspector:

    public unowned WebView getInspectorView(WebView v)
    {
        Window iWindow = new Window();
        WebView iWebview = new WebView();

        ScrolledWindow sWindow = new ScrolledWindow(null, null);
        sWindow.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);

        sWindow.add(iWebview);
        iWindow.add(sWindow);

Note I add the Webkit component (__iWebview__) to a scrolled window (__sWindow__)
so it doesn't matter if it doesn't all fit inside. I then add the scrolled
window to a top-level window (__iWindow__).

Next we set __iWindow__'s title based on the main window's title and its size
to the same as the main window's size. Then we show __iWindow__.
Finally we return __iWebview__ so the Web inspector uses it to display itself
in:

        iWindow.title = title + " (Web Inspector)";
        
        int width, height;
        get_size(out width, out height);
        iWindow.set_default_size(width, height);
        
        iWindow.show_all();

        iWindow.delete_event.connect(() =>
        {
            webview.web_inspector.close();
            return false;
        });

        unowned WebView r = iWebview;
        return r;
    }

Note intercepting the __delete_event__ from the window in order to close the
Web inspector before the window is destroyed. I found I got segmentation faults
if I didn't do this.

Note also the __unowned__ keyword. This means there will be no reference count
on the Webkit component so it will be deleted once the user closes __iWindow__.

Hiding the mouse cursor
-----------------------

In the constructor, we set __cursor__ to an invisible cursor if the user asked
for the mouse cursor to be hidden. Let's define a function to check if
__cursor__ was set and use it on the main window and Webkit component if it was:

    private void hide_cursor()
    {
        if (cursor != null)
        {
            window.set_cursor(cursor);
            webview.window.set_cursor(cursor);
        }
    }

I found I had to call __hide_cursor__ in a couple of places. Firstly, whenever
the mouse is moved:

    public override bool motion_notify_event(Gdk.EventMotion event)
    {
        hide_cursor(); 
               
        if (base.motion_notify_event == null)
        {
            return false;
        }
        else
        {
            return base.motion_notify_event(event);
        }
    }

and secondly when the [page is loaded](#load).

Getting data from standard input
--------------------------------

We want to read all of standard input and expose it to Javascript running in
Webkit. We'll see in the next section how to expose functions for Javascript to
call. What we do first is start a thread which reads from standard input:

    static construct
    {
        try
        {
            Thread.create<void*>(() =>
            {
                StringBuilder sb = new StringBuilder();
                char buffer[1024];
        
                while (!stdin.eof())
                {
                    string s = stdin.gets(buffer);
            
                    if (s != null)
                    {
                        sb.append(s);
                    }
                }
        
                lock (data)
                {
                    data = sb.str;
                }
     
                return null;
            }, false);
        }
        catch (ThreadError e)
        {
            stderr.printf("%s: failed to create data reader thread: %s\n", Main.prog_name, e.message);
            Gtk.main_quit();
        }
    }

This code is only run once, when the __MainWindow__ class is first used. We
build up a string buffer from standard input until end-of-file is reached.

Then we set the __data__ class variable that we declared at the top of the class
to the contents of the string buffer. Note we take out a __lock__ on __data__
first because we're going to be reading it from a different thread:

    public static JSCore.Value getData(JSCore.Context ctx,
                                       JSCore.Object function,
                                       JSCore.Object thisObject,
                                       JSCore.ConstValue[] arguments,
                                       out JSCore.Value exception)
    {
        exception = null;

        lock (data)
        {
            return new JSCore.Value.string(ctx, new JSCore.String.with_utf8_c_string(data));
        }
    }

We'll be calling this function from Javascript and exposing it to Webkit in the
next section. It simply returns __data__ to Javascript.

Passing data to Javascript
--------------------------

The cleanest way to pass data to Javascript is to expose functions for
Javascript to call when it's ready to do so. You can then return the data from
those functions.

In the constructor for __MainWindow__, we arranged for a method called
__addApp__ to be called whenever Webkit loaded a new page. Here's the start
of __addApp__:

    public void addApp(WebFrame frame, void *context, void *window_object)
    {
        unowned JSCore.Context ctx = (JSCore.Context) context;
        JSCore.Object global = ctx.get_global_object();

Here we get the global object from the Javascript context that's passed to us.
This represents the global variables in the page our Webkit component (__webview__) has loaded.

We can then use this to expose the __getData__ method we defined in the previous
section:

        JSCore.String name = new JSCore.String.with_utf8_c_string("app_getData");
        JSCore.Value ex;
                            
        global.set_property(ctx,
                            name,
                            new JSCore.Object.function_with_callback(ctx, name, getData),
                            JSCore.PropertyAttribute.ReadOnly,
                            out ex);

In Javascript, __getData__ will be available as __app_getData__.

Receiving data from Javascript
------------------------------

Let's continue the definition of __addApp__ from the previous section to expose
a method, __exit__, which Javascript can call to exit the application:

        name = new JSCore.String.with_utf8_c_string("app_exit");
        
        global.set_property(ctx,
                            name,
                            new JSCore.Object.function_with_callback(ctx, name, exit),
                            JSCore.PropertyAttribute.ReadOnly,
                            out ex);
    }

__exit__ will take an argument, which it will print to standard output before
exiting the application:

    public static JSCore.Value exit(JSCore.Context ctx,
                                    JSCore.Object function,
                                    JSCore.Object thisObject,
                                    JSCore.ConstValue[] arguments,
                                    out JSCore.Value exception)
    {
        exception = null;

        JSCore.String js_string = arguments[0].to_string_copy(ctx, null);

        size_t max_size = js_string.get_maximum_utf8_c_string_size();
        char *c_string = new char[max_size];
        js_string.get_utf8_c_string(c_string, max_size);

        stdout.printf("%s\n", (string) c_string);

        Gtk.main_quit();

        return new JSCore.Value.null(ctx);
    }

As you can see, we have to convert the Javascript string argument to UTF-8.
You'll need a UTF-8 locale set up to display the string if you use
any Unicode characters.

<a id="load"></a>Loading a page
-------------------------------

Finally, we need to define the __load__ method which allows users of
__MainWindow__ to specify the page which will be loaded into Webkit:

    public void load(string url)
    {
        webview.open(url);
        hide_cursor();
    }

It just calls the __open__ method of our Webkit component and then hides the
cursor (if necessary).

Compiling
---------

That's it for the Vala code but there are a couple of other things to do before
we can compile it and get a binary we can run.

Firstly, the class and type definitions for interoperating with Javascript
aren't built into Vala. They have to be defined separately. This is done by
[defining them in a VAPI file](https://live.gnome.org/Vala/Tutorial#Binding_Libraries_with_VAPI_Files).

I won't go into the details here, but the hard
work has already been done by Sam Thursfield and is available [here](http://gitorious.org/seed-vapi/seed-vapi/blobs/master/javascriptcore.vapi).
I had to make a few patches, which are available [here](https://gist.github.com/4058053#file-javascriptcore-vapi-patch).

Secondly, when you compile a Vala program, especially one which uses some
complex types, it's fairly common to get warnings about const and type
incompatibility from the C compiler (remember Vala is translated into C).
Most people ignore these but I like to compile without warnings. I've adopted a
rather skanky workaround to do this. Basically, I insert a script to fix up the
types in the generated C source code.

You can find all the source from this article [here](https://gist.github.com/4058053). You'll also find a working
Makefile, a patched version of the Javascript VAPI file, my skanky workaround script
and the test Web page described in the next section.

<a id="test_page"></a>Test Web page
-----------------------------------

Finally, let's take a look at a Web page we can load into our example
application. It needs to:

- Call __app_getData__ periodically until it returns something other than the
  empty string. This will be the data read from standard input and we'll display
  it in the page once it's read.

- Call __app_exit__ at some point, passing in a message which the application
  will write to standard output before exiting. We'll do this when the user
  presses a button.

The HTML turns out to be pretty simple:

    <html>
    <head>
    <script type="text/javascript">
    function check_data()
    {
        var data = app_getData();

        if (data === "")
        {
            setTimeout(check_data, 1000);
        }
        else
        {
            document.getElementById('data').innerText = data;
        }
    }
    </script>
    </head>
    <body onload='check_data()'>
    <p>
    data: <span id="data"></span>
    </p>
    <input type="button" value="Exit" onclick="app_exit('goodbye from Javascript')">
    </body>
    </html>

We poll __app_getData__ every second once the page has loaded. When we have the
data from standard input, we display it in the __#data__ element.

When the user clicks on the __Exit__ button, we call __app_exit__ with a
message.

You can test it by piping some data through to the __webkit-example__ binary
you get by building the [source](https://gist.github.com/4058053). For example:

    echo 'Hello World!' | ./webkit-example
