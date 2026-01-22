#!/usr/bin/env sh
# Intended for use in Alpine containers, see the "nightly" Github action for a list of dependencies

CXX="clang++-21"
LLVM_CONFIG="llvm-config-21"

DISABLED_WARNINGS="-Wno-switch -Wno-macro-redefined -Wno-unused-value"

CPPFLAGS="-DODIN_GAMEENGINE_VERSION_RAW=\"dev-v0.0.1\""
CXXFLAGS="-std=c++14 $($LLVM_CONFIG --cxxflags --ldflags)"

LDFLAGS="-static -lm -lzstd -lz -lffi -pthread -ldl -fuse-ld=mold"
LDFLAGS="$LDFLAGS $($LLVM_CONFIG --link-static --ldflags --libs --system-libs --libfiles)"
LDFLAGS="$LDFLAGS -Wl,-rpath=\$ORIGIN"

EXTRAFLAGS="-DNIGHTLY -O3"

set -x
$CXX src/main.cpp src/libtommath.cpp $DISABLED_WARNINGS $CPPFLAGS $CXXFLAGS $EXTRAFLAGS $LDFLAGS -o odin
