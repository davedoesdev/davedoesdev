#!/bin/bash
cd "$(dirname "$0")"
./compile.sh && rm -rf ../davedoesdev.github.io/* && cp -r compiled/* ../davedoesdev.github.io && echo www.davedoesdev.com > ../davedoesdev.github.io/CNAME
