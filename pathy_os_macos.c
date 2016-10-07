#include <mach-o/dyld.h>

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

extern int getmyname(lua_State *L)
{
    char *path;
    uint32_t n;

    n = 0;
    _NSGetExecutablePath(0, &n);
    if (!(path = malloc(n)))
        return luaL_error(L, "%s", strerror(errno));
    _NSGetExecutablePath(path, &n);
    lua_pushstring(L, path);
    free(path);
    return 1;
}
