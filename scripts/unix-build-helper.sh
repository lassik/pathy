set -eu
cd "$(dirname "$0")"/..

[ -e build-config.sh ] && { echo "Using build-config.sh"; . ./build-config.sh; }

builddir="$(basename $0)"
builddir="${builddir%.*}"
[ -d "$builddir" ] || mkdir -m 0700 "$builddir"
find "$builddir" -depth -mindepth 1 | xargs rm -rf --
cd "$builddir"
echo "Entering directory '$PWD'"

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
$CC $CFLAGS -I . $LUA_CFLAGS -o pathy ../pathy.c $extra_c_files \
    $LDFLAGS $LUA_LDFLAGS -DPROGVERSION="\"$PROGVERSION\""
