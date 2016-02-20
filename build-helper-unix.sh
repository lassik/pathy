# Do not run this script directly. It is just a helper for others.

set -eu
cd "$(dirname "$0")"

[ -e build-config.sh ] && { echo "Using build-config.sh"; . ./build-config.sh; }

builddir="$(basename $0)"
builddir="${builddir%.*}"
echo "Build directory is $builddir"
[ -d "$builddir" ] || mkdir -m 0700 "$builddir"
find "$builddir" -mindepth 1 -delete
cd "$builddir"

PROGVERSION="${PROGVERSION:-built on $(date "+%Y-%m-%d") by $(whoami)}"

PREFIX="${PREFIX:-$default_prefix}"
CC="${CC:-$default_cc}"
CFLAGS="${CFLAGS:-$default_cflags}"
LDFLAGS="${LDFLAGS:-$default_ldflags}"
LUA="${LUA:-$default_lua}"
LUAC="${LUAC:-$default_luac}"
LUA_CFLAGS="${LUA_CFLAGS:-$($default_lua_cflags_cmd)}"
LUA_LDFLAGS="${LUA_LDFLAGS:-$($default_lua_ldflags_cmd)}"

$LUAC -o pathy.luac ../getopt.lua ../pathy.lua
$LUA ../file2h.lua pathy.luac pathy_lua > pathy_lua.h
$CC $CFLAGS -I . $LUA_CFLAGS -o pathy-helper ../pathy.c \
    ../pathy_os_unix.c $LDFLAGS $LUA_LDFLAGS -DPROGVERSION="\"$PROGVERSION\""
sed "s@PATHY_HELPER=.*@PATHY_HELPER=$PREFIX/libexec/pathy-helper@" \
    < ../pathy.sh > pathy.sh
