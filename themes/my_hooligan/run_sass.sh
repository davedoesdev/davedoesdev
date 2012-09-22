#!/bin/bash
# sudo gem install sass
# sudo gem install compass
cd "$(dirname "$0")"
sass --compass stylesheets/{_sass/style.scss,css/style.css}
