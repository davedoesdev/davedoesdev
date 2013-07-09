---
title: "Wrapping Webkit (Part 2 - Qt/C++)"
date: '2013-01-27'
description: Embedding a Web user interface in a C++ application
categories:
tags: [webkit, html, javascript, qt, c++]
---

In my [previous post](/wrapping-webkit-part-1-gtk%2B-vala), I showed how to
get bi-directional communication going between Javascript and Vala, using
GTK+'s Webkit component.

This time I'm going to do the same between Javascript and C++, using
[Qt](http://qt-project.org/)'s Webkit component. Last time out I decided against
using C++ with GTK+ but Qt seems better suited to the language. Let's see
how Qt/C++ compares to GTK+/Vala.

We'll be sticking to the same example [we used before with Vala](/wrapping-webkit-part-1-gtk%2B-vala#example):

1. A main function for parsing command line options and initializing things.
2. A window class which embeds Webkit and puts it in a Qt window.

# Main function

The first thing to do in a Qt application is declare a __QApplication__ object:

    int main(int argc, char *argv[])
    {
        QApplication a(argc, argv);

This initializes Qt so it's a good idea to do it early on.

We'll support the same command line options: __url__, __fullscreen__,
__hidecursor__ and __debug__.  Qt doesn't have a helper class to parse command
line options so we'll use
[TCLAP](http://tclap.sourceforge.net/), a nice small library for doing just
that:

    TCLAP::CmdLine cmd("Webkit Example");
    TCLAP::ValueArg<std::string> urlArg("u", "url", "page to load", false, "file://" + QDir(a.applicationDirPath()).filePath("test.html").toStdString(), "URL", cmd);
    TCLAP::SwitchArg fullscreenSwitch("f", "fullscreen", "run in fullscreen mode", cmd, false);
    TCLAP::SwitchArg hidecursorSwitch("c", "hidecursor", "hide mouse cursor", cmd, false);
    TCLAP::SwitchArg debugSwitch("d", "debug", "enable web inspector", cmd, false);

    cmd.parse(argc, argv);

As you can see, we specify the default value for each option at the same time.
__url__ defaults to a file called __test.html__ in the same directory as the
application.

Now we create our Qt window which embeds Webkit (see the next section for
details of our window class):

    MainWindow w(debugSwitch.getValue());

Make it full screen if the command line option was passed:

    if (fullscreenSwitch.getValue())
    {
        w.setWindowState(Qt::WindowFullScreen);
    }

A slight difference with the Vala version is that we hide the mouse cursor
using the application object rather than the window:

    if (hidecursorSwitch.getValue())
    {
        a.setOverrideCursor(QCursor(Qt::BlankCursor));
    }

Next we can load the URL into Webkit (this is a method on our window class
which ends up calling into Webkit):

    w.load(urlArg.getValue().c_str());

and show the window and all its children (including Webkit):

    w.show():

Finally, we have to start the Qt application (i.e. the main event loop):

    return a.exec();

# Window class

## Declaration

This class is going to do the following:

- Inherit from the Qt __QMainWindow__ class so it's a top-level window.
- Apply settings and add widgets defined visually in [Qt Creator](http://qt-project.org/wiki/Category:Tools::QtCreator), Qt's IDE.
  In our GTK+/Vala example, we did this ourselves in code. With Qt Creator,
  you can configure things like the window's size and add a Webkit component
  to it visually using a form designer.
- Specify what Webkit features are enabled.
- Start a thread which reads data from standard input.
- Expose an object to Javascript which has two methods:
    1. A method which returns data read by the thread from standard input.
       This shows we can get data from C++ into the Web app.
    2. A method which writes its argument to standard output and then terminates
       the application. This shows we can call C++ functions and pass them data
       from the Web app.

Here's how we declare our window class:

    class MainWindow : public QMainWindow
    {
        Q_OBJECT
    
You can see we inherit from __QMainWindow__. We also have to use the
__Q_OBJECT__ macro in our class because we'll be using Qt _signals_ and _slots_.
Signals and slots are declared like any other C++ method but Qt can connect a
signal to a slot at runtime. When the signal method is called, Qt makes sure
that any slot methods connected to it are also called. We'll be using signals
slots in this example.

Next we declare our constructor and destructor:

    public:
        explicit MainWindow(bool debug, QWidget *parent = 0);
        ~MainWindow() {}

and a public method to load a URL into Webkit:

    void load(const char *url);

The __MainWindow__ class has the following private data:

    private:
        Ui::MainWindow ui;
        DataReader reader;
        QThread readerThread;
        Bridge bridge;

__Ui::MainWindow__ is a class which Qt Creator's form designer generates from
your visual design for the window. Qt Creator saves your design as an XML
file which is then converted into this class. You can find the XML file for this
example [here](https://gist.github.com/davedoesdev/4659070#file-mainwindow-ui).
I put a grid layout onto the window and then dragged a __QWebView__ widget
onto the layout.

__DataReader__ is a class we'll define later which reads data from standard
input and raises a signal with the data when it's done. This will be done in a
thread (__readerThread__).

__Bridge__ is also a class we'll define later. It contains the methods we want
to expose to Javascript: one to retrieve the data read by __reader__ from
standard input and one to exit the application. It should also have a slot
which can receive the data from __reader__ and store it.

Finally, we can define a couple of slots &mdash; we'll connect them to signals
later:

    private slots:
        void addBridgeToPage();
        void exit(QString msg);

__addBridgeToPage__ will be called whenever a new page is loaded into Webkit.
It will add __bridge__ to the page. __exit__ will print its argument to
standard output and then close the window. Note we declare these slots
__private__. This just means the methods which implement them are private to
the class &mdash; Qt can connect the slots themselves to signals in any class.

## Implementation

__MainWindow__'s implementation is pretty simple. Let's look at the constructor
first:

    MainWindow::MainWindow(bool debug, QWidget *parent) :
        QMainWindow(parent)
    {
        QWebSettings::globalSettings()->setAttribute(QWebSettings::PluginsEnabled, true);
        QWebSettings::globalSettings()->setAttribute(QWebSettings::JavascriptEnabled, true);
        QWebSettings::globalSettings()->setAttribute(QWebSettings::LinksIncludedInFocusChain, false);
        QWebSettings::globalSettings()->setAttribute(QWebSettings::LocalContentCanAccessRemoteUrls, true);
        QWebSettings::globalSettings()->setAttribute(QWebSettings::LocalStorageEnabled, true);
    
        if (debug)
        {
            QWebSettings::globalSettings()->setAttribute(QWebSettings::DeveloperExtrasEnabled, true);
        }

You can see we set a bunch of Webkit options:

- Enable plugins (you usually don't need this).
- Enable Javascript.
- Enable tabbing between links.
- Allow pages loaded from local disk to make calls to remote URLs. The
  Javascript in our example doesn't do this but it's useful if you want to
  distribute a HTML/JS user interface and have it communicate with a server
  somewhere.
- Enable Local (DOM) storage. Again, our example doesn't actually need to do
  this.
- Enable Webkit's Web inspector if the __debug__ parameter is true.

Next we have to initialize the user interface we designed visually using
Qt Creator's form designer:

    ui.setupUi(this);

Now we need to hook up a bunch of signals and slots. First, add __bridge__
to the global Javascript environment when a page is loaded. We do this by
connecting the __javaScriptWindowObjectCleared__ signal from Webkit to our
__addBridgeToPage__ method (which we'll define later):

    connect(ui.webView->page()->mainFrame(), SIGNAL(javaScriptWindowObjectCleared()), this, SLOT(addBridgeToPage()));

Next, when Javascript raises the __exit__ signal in __bridge__, arrange for the
__exit__ method in __MainWindow__ to be called:

    connect(&bridge, SIGNAL(exit(QString)), this, SLOT(exit(QString)));

When __reader__ has finished reading data from standard input, notify __bridge__
so it can store the data for Javascript to receive when it polls for it:

    connect(&reader, SIGNAL(dataRead(QString)), &bridge, SLOT(gotData(QString)));

Finally, we need to arrange for __reader__ to be run in a separate thread so it
doesn't block the main user interface:

    connect(&readerThread, SIGNAL(started()), &reader, SLOT(read()));
    connect(&reader, SIGNAL(dataRead(QString)), &readerThread, SLOT(quit()));

    reader.moveToThread(&readerThread);
    readerThread.start();

The recommended approach to starting a thread in Qt uses signals and slots,
as you can see above. You connect the __started__ signal to the slot that will
do the work. Then once the work is done (__dataRead__), tell the thread to stop
(__quit__). Before starting the thread, you must set the affinity of the object
which will be doing the work (__moveToThread__).

Now we can define __MainWindow__'s methods: __load__, __addBridgeToPage__ and
__exit__.

    void MainWindow::load(const char *url)
    {
        //ui->webView->load(QUrl(url));
        ui.webView->setHtml("<script>location.replace('" + QString(url) + "');</script>");
    }

__load__ tells the Webkit component (__webView__) to visit a URL. If you use
Webkit's __load__ method to do this, you get an extra entry in the history.
You can see above I use an alternative which runs some Javascript to replace
the current page instead.

    void MainWindow::addBridgeToPage()
    {
        ui.webView->page()->mainFrame()->addToJavaScriptWindowObject("bridge", &bridge);
    }

__addBridgeToPage__ is called whenever a new page is loaded. It adds __bridge__
to the page so Javascript can call it.

    void MainWindow::exit(QString msg)
    {
        QTextStream(stdout) << msg << endl;
        close();
    }

Remember we connected __MainWindow::exit__ to the __exit__ signal raised by
__bridge__ (this signal is raised when Javascript calls the __exit__ method
on __bridge__ after we exposed it to the page).

# __DataReader__ class

## Declaration

This class just has to read data from standard input and raise a signal with
the data when it's done:

    class DataReader : public QObject
    {
        Q_OBJECT

    private slots:
        void read();

    signals:
        void dataRead(QString data);
    };

## Implementation

We only need to implement __read__ &mdash; Qt takes care of generating a method
for raising the __dataRead__ signal (the method has the same prototype as the
signal but you have to use the __emit__ keyword when calling it from C++):

    void DataReader::read()
    {
        emit dataRead(QTextStream(stdin).readAll());
    }

# __Bridge__ class

## Declaration

An object of this class (__bridge__ in __MainWindow__) will be exposed to
Javascript. It has:

- A signal, __exit__. Javascript apps can just call the __exit__ method on the
  __Bridge__ object to raise the signal. Remember we connected this
  signal to the __exit__ method in __MainWindow__.
- A slot, __getData__, which can be called from Javascript to retrieve data
  read from standard input. If no data has yet been read, it should return
  an empty string.
- A slot, __gotData__, which will receive data read from standard input and
  store it so it can be returned to Javascript when it calls __getData__.

Here's what this looks like in code:

    class Bridge : public QObject
    {
        Q_OBJECT
    
    signals:
        void exit(QString msg);

    public slots:
        QString getData();

        // Override slot inherited from QObject which shouldn't be exposed!
        // See https://bugs.webkit.org/show_bug.cgi?id=34809
        void deleteLater() {}

    private slots:
        void gotData(QString data);

Finally, we need a member variable to store the data and a mutex because
Javascript may be calling __getData__ at the same time that __gotData__ is
being called (I'm unclear as to where Javascript calls are handled so it's
best to be safe):

    private:
        QMutex mutex;
        QString data;
    };

## Implementation

__getData__ and __gotData__ are really simple: they just get and set __data__
inside a lock on __mutex__:

    QString Bridge::getData()
    {
        QMutexLocker locker(&mutex);
        return data;
    }

    void Bridge::gotData(QString data)
    {
        QMutexLocker locker(&mutex);
        this->data = data;
    }

# <a id="test_page"></a>Test Web page

To test our example, we can re-use the [Web page we used to test our Vala version](/wrapping-webkit-part-1-gtk%2B-vala#test_page), with a simple modification
to call call __exit__ and __getData__ via __bridge__ rather than as separate
functions:

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

Test it, as before, by piping data to __webkit-example__:

    echo 'Hello World!' | ./webkit-example

You can find all the source from this article [here](https://gist.github.com/4659070).

