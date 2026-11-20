#!/bin/sh
set -e
SDK="$1"
if [ -z "$SDK" ]; then SDK="$(xcrun --sdk iphoneos --show-sdk-path)"; fi
clang -arch arm64 -miphoneos-version-min=14.0 -isysroot "$SDK" -dynamiclib -fobjc-arc -framework UIKit -framework Foundation -undefined dynamic_lookup -o YufengTest.dylib YufengTest.m
file YufengTest.dylib 2>/dev/null || true
ls -lh YufengTest.dylib
