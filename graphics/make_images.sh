#!/bin/bash
cd "$(dirname "$0")"
for d in 16 24 32 48 64 128
do
  inkscape -e ddd-${d}x${d}.png -w $d -h $d vec/ddd.svg
done
./png2ico ddd.ico ddd-*.png
