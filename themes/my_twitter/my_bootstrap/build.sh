#!/bin/bash
cd "$(dirname "$0")"
./node_modules/less/bin/lessc -x bootstrap.less > ../stylesheets/bootstrap.min.css
