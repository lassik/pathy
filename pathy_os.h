extern int assert_fd3_is_pipe(lua_State *L);
extern int write_to_fd3(lua_State *L);
extern int start_program(lua_State *L);
extern int wait_for_program(lua_State *L);
extern int get_directory_diagnostics(lua_State *L);
extern void map_files(lua_State *L, const char *dirpath, void (*mapfun)(lua_State *, const char *));
