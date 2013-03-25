---
title: "Wrapping Webkit (Part 3 - Qt Quick/Python)"
date: '2013-03-23'
description:
categories:
tags: [webkit, html, javascript, qt, qt quick, qml, python]
---

[Last time out](/wrapping-webkit-part-2-qt-c%2B%2B), I showed how to get
bi-directional communication going between Javascript and C++, using Qt's
Webkit component.

This time I'm going to stick with Qt but use its new shiny: [Qt Quick](http://qt-project.org/doc/qt-4.8/qtquick.html). Qt Quick adds a markup language, [QML](http://qt-project.org/doc/qt-4.8/gettingstartedqml.html), to the mix.

You use QML to declare which components to build your user interface from.
The idea is that a declarative specification will make your user interface work across different types of device (mobile is the main focus).

For application logic, you can use Javascript in QML. Alternatively you can
use a language which has Qt (and Qt Quick) bindings. Last time I used C++. This time I'll use
[PySide](http://qt-project.org/wiki/PySide) &mdash; the Python bindings to Qt.

# The QML

Let's start with the QML for our example. It needs to do a couple of things:

1. Declare a __WebView__ (Webkit) component which will load our HTML page.
2. Expose a _bridge_ object to Javascript in the page. The bridge object should
   have a couple of methods to do the following:
    - Return data read from standard input by our Python code.
    - Ask our Python code to exit the application.

First we import __QtQuick__ and __QtWebKit__:

    import QtQuick 1.0
    import QtWebKit 1.0

Next we declare the __WebView__ component. This will be the only Qt component
in our application:

    WebView
    {
        settings.javascriptEnabled: true;
        width: 800;
        height: 600;

You can see we turn Javascript on in Webkit and set the initial size. Next we
declare a __bridge__ object for our HTML page to call:

    javaScriptWindowObjects: QtObject
    {
        WebView.windowObjectName: "bridge";

        function getData()
        {
            return the_bridge.getData();
        }

        function exit(msg)
        {
            the_bridge.exit(msg);
        }
    }
}

Notice a couple of things here:

1. We define __bridge__'s methods in Javascript directly in the QML.
2. __bridge__ is just a proxy to another object called __the_bridge__.
   __the_bridge__ is undefined in our QML; our Python code will
   have to define it and add to our __WebView__'s runtime environment.
   Ideally I'd have exposed __the_bridge__ directly to the page but I couldn't
   get that to work.

# The Python

Our Python code has to do what the C++ code did in [my previous example](/wrapping-webkit-part-2-qt-c%2B%2B):

1. Handle command line arguments specifying:
    - The URL of a page to load into Webkit.
    - Run as a fullscreen application.
    - Hide the mouse cursor.
    - Enable Webkit's developer tools.

2. Read data from standard input and make it available to the page when done.

3. Expose a function to the page so it can exit the application.

## Imports

First up we need to import a bunch of modules:

    #!/usr/bin/env python
    import sys
    import argparse
    import signal
    from os import path
    from threading import Lock
    from PySide import QtGui, QtDeclarative, QtCore
    from PySide.QtWebKit import QWebSettings

You can see the Qt modules we're going to use. __QtDeclarative__ handles the
QML stuff. Notice also that I'm using the standard Python __Lock__ class rather
than __QMutex__. Either would have worked fine.

## Parsing command line arguments

Python's already got decent support for parsing command line arguments via the
__argparse__ module. So it's pretty straightforward for us:

    parser = argparse.ArgumentParser(description='Webkit Example')
    parser.add_argument('-u', '--url', help='page to load', default='file://' + sys.path[0] + '/test.html')
    parser.add_argument('-f', '--fullscreen', help='run in fullscreen mode', action='store_true')
    parser.add_argument('-c', '--hidecursor', help='hide mouse cursor', action='store_true')
    parser.add_argument('-d', '--debug', help='enable web inspector', action='store_true')
    args = parser.parse_args()

The default page to load is __test.html__ in the same directory as the
application. The other arguments default to __False__ (__argparse__ assumes this
because the action to take when they're specified is __store_true__).

We also have to pass the command line through to __QApplication__ when we
initialise Qt:

    app = QtGui.QApplication(sys.argv)

## __DataReader__

Next we'll define a class which will read from standard input and raise a Qt
signal with the data when it's done:

    class DataReader(QtCore.QObject):
        def __init__(self):
            super(DataReader, self).__init__()

        @QtCore.Slot(str)
        def read(self):
            self.readsig.emit(sys.stdin.read())

        readsig = QtCore.Signal(str)

As you can see, it's pretty simple to declare slots and signals in Python:
use the __Slot__ decorator and the __Signal__ constructor. One thing to note
is signals have to declared as class attributes. However, Qt makes sure each
instance of your class has a separate runtime signal object.

## __Bridge__

Now it's time to define a class which will be exposed to QML (it'll implement
the __the_bridge__ object we left undefined above):

    class Bridge(QtCore.QObject):
        def __init__(self):
            super(Bridge, self).__init__()
            self.data = ''
            self.lock = Lock()

__data__ will contain data read from standard input by __DataReader__ when it's
done. We also create a mutex (__Lock__) so we can safely read and write to
__data__ from multiple threads...

        @QtCore.Slot(result=str)
        def getData(self):
            with self.lock:
                return self.data

        @QtCore.Slot(str)
        def gotData(self, data):
            with self.lock:
                self.data = data

We have to declare __getData__ as a slot so it can be called from QML.
__gotData__ is a slot so we can hook it up to a __DataReader__ later on.

Finally, we define a signal to raise when application exit is required, plus a
function (slot) to raise it:

        exitsig = QtCore.Signal(str)

        @QtCore.Slot(str)
        def exit(self, msg):
            self.exitsig.emit(msg)

## Creating a view

Now we need to create a __QDeclarativeView__, which is like a Qt window but
uses a QML file to build the user interface:

    view = QtDeclarative.QDeclarativeView()
    view.setWindowTitle('WebKit Example')
    view.setResizeMode(QtDeclarative.QDeclarativeView.ResizeMode.SizeRootObjectToView)

We set the window title here and tell it to resize its contents when it is
resized. Note we don't load the QML into it yet &mdash; we have some more
setting up to do first.

## Hooking it all up

First let's make a __DataReader__ and a __Bridge__:

    reader = DataReader()
    bridge = Bridge()

Now we need to let __bridge__ know when __reader__ finishes reading from
standard input:

    reader.readsig.connect(bridge.gotData)
 
When __bridge__ raises an exit signal, we want to exit the application by
closing __view__:

    def exit(msg):
        print msg
        view.close()

    bridge.exitsig.connect(exit)

Then we can start __reader__ on a separate thread:

    readerThread = QtCore.QThread()
    readerThread.started.connect(reader.read)
    reader.readsig.connect(readerThread.quit)
    reader.moveToThread(readerThread)
    readerThread.start()

## Miscellaneous settings

There's three odds and ends we need to take care of:

1. Enable Webkit's developer tools if specified on the command line:

        QWebSettings.globalSettings().setAttribute(QWebSettings.WebAttribute.DeveloperExtrasEnabled, args.debug)

2. Hide the mouse cursor if specified on the command line:

        if args.hidecursor:
            app.setOverrideCursor(QtGui.QCursor(QtCore.Qt.BlankCursor))

   Note this current generates X errors on Ubuntu 12.10 64-bit due to a [bug in PySide](https://bugreports.qt-project.org/browse/PYSIDE-25).

3. Enable Ctrl-C to terminate the program (PySide seems to disable it):

        signal.signal(signal.SIGINT, signal.SIG_DFL)

## Showing the view

Now we can close things out by loading our QML and showing it.

First we need to add __bridge__ to __view__'s runtime environment, making it
available to QML as __the_bridge__:

    view.rootContext().setContextProperty('the_bridge', bridge)

Next we load the QML &mdash; I place it in a file alongside the Python source:

    view.setSource(path.basename(__file__).replace('.py', '.qml'))

Now the QML is loaded, the Webkit component is available as the top-level (root)
object in __view__. So we can load a page into it:

    view.rootObject().setProperty('url', args.url)

Finally, we show __view__ on the screen (in fullscreen mode if specified on the
command line):

    if args.fullscreen:
        view.showFullScreen()
    else:
        view.show()

And start Qt's message loop etc:

    app.exec_()

# Test Web page

To test our example, we can use exactly the same [Web page we used to test our
C++ version](/wrapping-webkit-part-2-qt-c%2B%2B#test_page):

    <html>
    <head>
    <script type="text/javascript">
    function check_data()
    {
        var data = bridge.getData();
    
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
    <input type="button" value="Exit" onclick="bridge.exit('goodbye from Javascript')">
    </body>
    </html>

Test it by piping data to __webkit-example.py__:

    echo 'Hello World!' | ./webkit-example.py

You can find all the source from this article [here](https://gist.github.com/5229176).
    
