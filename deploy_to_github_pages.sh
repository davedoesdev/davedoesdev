#!/bin/bash
cd "$(dirname "$0")"
./compile.sh && rm -rf ../davedoesdev.github.com/* && cp -r compiled/* ../davedoesdev.github.com
