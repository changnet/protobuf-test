// 把项目自研的 PbcCodec 注册成独立 Lua 模块 pbc_binding
// 语义与 server/src/message/pbc.lua 使用的 engine.PbcCodec 保持一致：
//   PbcCodec() / codec:reset() / codec:load(binary) / codec:update()
//   codec:encode(schema, tbl) / codec:decode(schema, binary)
//   codec:encode_to_buffer(schema, tbl) / codec:decode_from_buffer(schema, ptr, size)
//   codec:is_map(schema, field) 反射：字段是不是 proto3 map

#include <new>

#include <lua.hpp>

#include "pbc_codec.hpp"

#define PBC_CODEC_MT "PbcCodec"

// userdata 里直接放对象本体（不会移动），不再多一层指针
static PbcCodec *check_self(lua_State *L)
{
    return static_cast<PbcCodec *>(luaL_checkudata(L, 1, PBC_CODEC_MT));
}

// 无参数、无返回值的两个方法单独包装
static int l_reset(lua_State *L)
{
    check_self(L)->reset();
    return 0;
}

static int l_update(lua_State *L)
{
    check_self(L)->update();
    return 0;
}

// 反射糖：codec:is_map(schema, field) -> boolean
static int l_is_map(lua_State *L)
{
    const char *schema = luaL_checkstring(L, 2);
    const char *key    = luaL_checkstring(L, 3);
    lua_pushboolean(L, check_self(L)->is_map_field(schema, key));
    return 1;
}

// 其余成员函数签名就是 int32_t(lua_State*)，与 lua_CFunction 返回值语义一致
#define DEF_METHOD(name)                                  \
    static int l_##name(lua_State *L)                     \
    {                                                     \
        return check_self(L)->name(L);                    \
    }

DEF_METHOD(load)
DEF_METHOD(encode)
DEF_METHOD(decode)
DEF_METHOD(decode_from_buffer)
DEF_METHOD(encode_to_buffer)

#undef DEF_METHOD

static int l_new(lua_State *L)
{
    void *ud = lua_newuserdatauv(L, sizeof(PbcCodec), 0);

    luaL_getmetatable(L, PBC_CODEC_MT);
    lua_setmetatable(L, -2);

    // 元表先挂好：构造函数里若抛异常，__gc 才有机会跑
    new (ud) PbcCodec();
    return 1;
}

static int l_gc(lua_State *L)
{
    static_cast<PbcCodec *>(luaL_checkudata(L, 1, PBC_CODEC_MT))->~PbcCodec();
    return 0;
}

extern "C" int luaopen_pbc_binding(lua_State *L)
{
    // 模块表本身同时充当实例的方法表（__index）
    luaL_Reg funcs[] = {
        {"new", l_new},
        {"reset", l_reset},
        {"load", l_load},
        {"update", l_update},
        {"is_map", l_is_map},
        {"encode", l_encode},
        {"decode", l_decode},
        {"decode_from_buffer", l_decode_from_buffer},
        {"encode_to_buffer", l_encode_to_buffer},
        {nullptr, nullptr},
    };
    luaL_newlib(L, funcs);

    // 支持 PbcCodec() 这种与项目一致的写法
    lua_newtable(L);
    lua_pushcfunction(L, l_new);
    lua_setfield(L, -2, "__call");
    lua_setmetatable(L, -2);

    // 实例元表：__gc 释放，__index 指向模块表
    luaL_newmetatable(L, PBC_CODEC_MT);
    luaL_Reg mt[] = {{"__gc", l_gc}, {nullptr, nullptr}};
    luaL_setfuncs(L, mt, 0);
    lua_pushvalue(L, -2);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    return 1;
}
