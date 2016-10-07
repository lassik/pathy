#!/bin/sh -
default_prefix="/usr/local"
default_cc="clang"
default_cflags="-Wall -Wextra -g -O"
default_ldflags=""
default_lua="lua52"
default_luac="luac52"
default_lua_cflags_cmd="pkg-config --cflags lua-5.2"
default_lua_ldflags_cmd="pkg-config --libs lua-5.2"
. "$(dirname "$0")/unix-build-helper.sh"
