#include <lua.hpp>

#include <cstdint>
#include <cstring>
#include <cassert>

#include "protolua.h"

///////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////
// 临时存一些数据用于测试
static size_t len = 0;
static char buff[10240];

void proto_init(lua_State* L);

static int init(lua_State* L)
{
    proto_init(L);
    return 0;
}

static int load(lua_State* L)
{
    assert(lua_gettop(L) == 1);
    luaL_checktype(L, 1, LUA_TSTRING);
    const char* file = lua_tostring(L, 1);
    if (!proto_parse(file, L))
    {
        proto_error("proto.parse fail, file=%s", file);
        lua_pushboolean(L, false);
        return 1;
    }

    lua_pushboolean(L, true);
    return 1;
}

int encode_test(lua_State* L)
{
    const char* proto = luaL_checkstring(L, 1);

    len = sizeof(buff);
    if (!proto_encode(proto, L, 2, buff, &len))
    {
        proto_error("proto.encode fail, proto=%s", proto);
        return 0;
    }
    return 0;
}

int decode_test(lua_State* L)
{
    // 为了模拟数据从socket接收，这里直接从上一次encode的buffer取数据，不从lua
    // 那边取数据

    const char* proto = luaL_checkstring(L, 1);
    if (!proto_decode(proto, L, buff, len))
    {
        proto_error("proto.decode fail, proto=%s", proto);
        return 0;
    }


    // 默认情况下，所有内容解析到一个table
    return 1;
}

int encode_and_save(lua_State* L)
{
    const char* proto = luaL_checkstring(L, 1);
    len = sizeof(buff);
    if (!proto_encode(proto, L, 2, buff, &len))
    {
        proto_error("proto.encode fail, proto=%s", proto);
        return 0;
    }
    return 0;
}

int luaopen_pbext(lua_State* L)
{
    luaL_Reg libs[] = {
        {"init", init},
        {"load", load},
        {"encode_and_save", encode_and_save},
        { "encode", encode_test },
        { "decode", decode_test },
        { NULL, NULL }
    };
    luaL_newlib(L, libs);
    return 1;
}

int main()
{

    lua_State* L = luaL_newstate();

    luaL_openlibs(L);

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
