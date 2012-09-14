#!/bin/bash
cd "$(dirname "$0")"
./compile.sh && cd compiled && python -m SimpleHTTPServer
