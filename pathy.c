#include <stdio.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "pathy_os.h"
#include "pathy_lua.h"

#define PROGNAME "pathy"

#define LUA_REGISTER(L, name) lua_register(L, #name, name)

static void list_dir_entry(lua_State *L, const char *name)
{
    lua_pushstring(L, name);
    lua_rawseti(L, 2, lua_rawlen(L, 2)+1);
}

static int list_files_into_table(lua_State *L)
{
    map_files(L, luaL_checkstring(L, 1), list_dir_entry);
    return 0;
}

static void hash_dir_entry(lua_State *L, const char *name)
{
    lua_pushboolean(L, 1);
    lua_setfield(L, 2, name);
}

static int hash_files_into_table(lua_State *L)
{
    map_files(L, luaL_checkstring(L, 1), hash_dir_entry);
    return 0;
}

extern int main(int argc, char **argv)
{
    lua_State *L;
    int i;

    L = luaL_newstate();
    luaL_openlibs(L);
    lua_pushstring(L, PROGNAME);
    lua_setglobal(L, "PROGNAME");
    lua_pushstring(L, PROGVERSION);
    lua_setglobal(L, "PROGVERSION");
    LUA_REGISTER(L, assert_fd3_is_pipe);
    LUA_REGISTER(L, write_to_fd3);
    LUA_REGISTER(L, start_program);
    LUA_REGISTER(L, wait_for_program);
    LUA_REGISTER(L, get_directory_diagnostics);
    LUA_REGISTER(L, list_files_into_table);
    LUA_REGISTER(L, hash_files_into_table);

    lua_createtable(L, argc-1, 0);
    for (i = 1; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i);
    }
    lua_setglobal(L, "arg");

    if (luaL_loadbuffer(L, pathy_lua, sizeof(pathy_lua), PROGNAME)
        || lua_pcall(L, 0, 0, 0)) {
        fprintf(stderr, "%s: error: %s\n", PROGNAME, lua_tostring(L, -1));
        return 1;
    }
    lua_close(L);
    return 0;
}
