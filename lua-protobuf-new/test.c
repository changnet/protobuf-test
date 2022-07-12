#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <stdio.h>

#include "pb_ext.h"

int luaopen_pb(lua_State* L);
int luaopen_pb_buffer(lua_State* L);
int luaopen_pb_slice(lua_State* L);

int main()
{
    lua_State* L = luaL_newstate();

    luaL_openlibs(L);

    luaL_requiref(L, "pb", luaopen_pb, 1);
    lua_pop(L, 1);  /* remove lib */

    luaL_requiref(L, "pb_buffer", luaopen_pb_buffer, 1);
    lua_pop(L, 1);  /* remove lib */

    luaL_requiref(L, "pb_slice", luaopen_pb_slice, 1);
    lua_pop(L, 1);  /* remove lib */

    luaL_requiref(L, "pb_ext", luaopen_pbext, 1);
    lua_pop(L, 1);  /* remove lib */

    int e = luaL_dofile(L, "test_ext.lua");
    if (e)
    {
        printf("ERROR: %s", lua_tostring(L, lua_gettop(L)));
    }

    lua_close(L);

    return 0;
}
