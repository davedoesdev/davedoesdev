#!/bin/bash
cd "$(dirname "$0")"
rackup -p 9292 rackup.ru
