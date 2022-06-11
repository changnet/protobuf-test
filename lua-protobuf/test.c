#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "pb_ext.h"
#include <stdio.h>

int main()
{
    lua_State* L = luaL_newstate();

    luaL_openlibs(L);

    // luaopen_pbext(L);
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
