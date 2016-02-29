#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <dirent.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "pathy_os.h"

static struct stat st;

extern int assert_fd3_is_pipe(lua_State *L)
{
    if ((fstat(3,  &st) == -1) || !S_ISFIFO(st.st_mode))
        return luaL_error(L, "fd 3 is not a pipe");
    return 0;
}

extern int write_to_fd3(lua_State *L)
{
    const char *s;
    ssize_t n;

    s = luaL_checkstring(L, 1);
    if ((n = write(3, s, strlen(s))) == (ssize_t)-1)
        return luaL_error(L, "cannot write to fd 3: %s", strerror(errno));
    if ((n < 0) || ((size_t)n != strlen(s)))
        return luaL_error(L, "cannot write more than %zd bytes to fd 3", n);
    return 0;
}

extern int start_program(lua_State *L)
{
    const char **argv = 0;
    pid_t pid = -1;
    int fds[2] = {-1, -1};
    int argc, i, status, firsterror = 0;

    errno = 0;
    if ((argc = lua_gettop(L)) < 1)
        goto cleanup;
    if (!(argv = calloc(argc+1, sizeof(*argv))))
        goto cleanup;
    for (i = 0; i < argc; i++)
        argv[i] = luaL_checkstring(L, i+1);
    if (pipe(fds) == -1)
        goto cleanup;
    if ((pid = fork()) == (pid_t)-1)
        goto cleanup;
    if (!pid) {
        dup2(fds[0], 0);
        close(fds[0]);
        close(fds[1]);
        execvp(argv[0], (char **)argv);
        _exit(127);
    }
    if (dup2(fds[1], 1) == -1)
        goto cleanup;
cleanup:
    firsterror = errno;
    close(fds[0]);
    close(fds[1]);
    free(argv);
    if (firsterror) {
        if (pid != (pid_t)-1)
            waitpid(pid, &status, 0);
        return luaL_error(L, "cannot run program: %s", strerror(firsterror));
    }
    lua_pushinteger(L, pid);
    return 1;
}

extern int wait_for_program(lua_State *L)
{
    pid_t pid;
    int status;

    pid = luaL_checkunsigned(L, 1);
    if ((close(1) == -1) || (waitpid(pid, &status, 0) == -1))
        return luaL_error(L, "cannot run program: %s", strerror(errno));
    lua_pushinteger(L, status);
    return 1;
}

extern int get_directory_diagnostics(lua_State *L)
{
    const char *dirpath;
    const char *etype;

    dirpath = luaL_checkstring(L, 1);
    lua_newtable(L);
    if (stat(dirpath, &st) == -1) {
        switch (errno) {
        case EACCES:
        case ELOOP:
        case ENAMETOOLONG:
        case ENOENT:
        case ENOTDIR:
            lua_pushstring(L, strerror(errno));
            lua_setfield(L, -2, "error");
            return 1;
        }
        /* TODO: Is it really wise to single out errno's like this? */
        return luaL_error(L, "stat failed: %s", strerror(errno));
    }
    etype = "unknown";
    switch (st.st_mode & S_IFMT) {
    case S_IFIFO: etype = "pipe"; break;
    case S_IFCHR: etype = "device"; break;
    case S_IFDIR: etype = "directory"; break;
    case S_IFBLK: etype = "device"; break;
    case S_IFREG: etype = "file"; break;
    case S_IFLNK: etype = "symbolic link"; break; /* TODO: We'd need to use lstat() */
    case S_IFSOCK: etype = "socket"; break;
    }
    lua_pushstring(L, etype);
    lua_setfield(L, -2, "type");
    lua_pushboolean(L, st.st_mode & 0002);
    lua_setfield(L, -2, "is_world_writable");
    return 1;
}

extern void map_files(lua_State *L, const char *dirpath, void (*mapfun)(lua_State *, const char *))
{
    DIR *handle;
    struct dirent *d;
    int firsterror;

    if (!(handle = opendir(dirpath)))
        goto done;
    for (;;) {
        errno = 0;
        if (!(d = readdir(handle)))
            break;
        if (!strcmp(d->d_name, ".") || !strcmp(d->d_name, ".."))
            continue;
        mapfun(L, d->d_name);
    }
done:
    firsterror = errno;
    if (handle && (closedir(handle) == -1) && !firsterror)
        firsterror = errno;
    if (firsterror)
        luaL_error(L, "cannot list directory %s: %s",
                   dirpath, strerror(firsterror));
}
