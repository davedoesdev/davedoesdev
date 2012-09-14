#!/bin/bash
cd "$(dirname "$0")"
ruhoh compile && rm -rf ../davedoesdev.github.com/* && cp -r compiled/* ../davedoesdev.github.com
