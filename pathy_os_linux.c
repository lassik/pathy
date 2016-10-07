#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

extern int getmyname(lua_State *L)
{
    char *path;

    if (!(path = calloc(1, PATH_MAX+1)))
        goto fail;
    if (readlink("/proc/self/exe", path, PATH_MAX+1) == (ssize_t)-1)
        goto fail;
fail:
    if (!errno)
        lua_pushstring(L, path);
    free(path);
    if (errno)
        return luaL_error(L, "%s", strerror(errno));
    return 1;
}
