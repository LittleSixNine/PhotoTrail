#!/bin/sh
set -eu
/usr/bin/xcrun clang -Os -Wall -Wextra -Werror -arch arm64 -arch x86_64 \
  -mmacosx-version-min=14.0 "$1" -lcompression -o "$2"
/usr/bin/codesign --force --sign - "$2"
