#!/bin/sh -
default_prefix="/usr"
default_cc="gcc"
default_cflags="-Wall -Wextra -g -O"
default_ldflags=""
default_lua="lua"
default_luac="luac"
default_lua_cflags_cmd="pkg-config --cflags lua"
default_lua_ldflags_cmd="pkg-config --libs lua"
. "$(dirname "$0")/unix-build-helper.sh"