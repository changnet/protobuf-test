#include <string.h>

#include "pb_ext.h"

PB_NS_BEGIN

int Lext_encode(void* LS, lua_State* L, int index, pb_Buffer *b)
{
    // Lpb_encode(L);
    lpb_Env e;
    const pb_Type* t = lpb_type(LS, lpb_checkslice(L, index));

    luaL_checktype(L, index + 1, LUA_TTABLE);

    // lpb_encode要求栈顶必定得是要打包的数据
    if (lua_gettop(L) != index + 1) return -1;

    // argcheck(L, t != NULL, 1, "type '%s' does not exists", lua_tostring(L, 1));

    e.L = L, e.LS = LS, e.b = b;
    // 打包的数据，是写到了pb_Buffer *b = e->b;

    lpb_encode(&e, t);

    return 0;
}

int lext_decode(void* LS, lua_State* L, pb_Slice* s)
{
    // pb_lslice(data, size) 从const char *构建slice
    const pb_Type* t = lpb_type(LS, lpb_checkslice(L, 1));
    lpb_Env e;
    //argcheck(L, t != NULL, 1, "type '%s' does not exists", lua_tostring(L, 1));
    
    lpb_pushtypetable(L, LS, t);
    e.L = L, e.LS = LS, e.s = s;
    return lpbD_message(&e, t);
}

////////////////////////////////////////////////////////////////////////////////

// 临时存一些数据用于测试
static void* __LS = NULL;
static size_t len = 0;
static char buff[10240];

int init(lua_State* L)
{
    __LS = default_lstate(L);
    return 0;
}

int encode_test(lua_State* L)
{
    lpb_State* LS = __LS;
    pb_resetbuffer(&LS->buffer);

    Lext_encode(LS, L, 1, &LS->buffer);

    return 0;
}

int decode_test(lua_State* L)
{
    // 为了模拟数据从socket接收，这里直接从上一次encode的buffer取数据，不从lua
    // 那边取数据
    lpb_State* LS = __LS;

    pb_Slice s = pb_lslice(buff, len);

    lext_decode(LS, L, &s);
    return 1;
}

int encode_and_save(lua_State* L)
{
    lpb_State* LS = __LS;
    pb_resetbuffer(&LS->buffer);

    Lext_encode(LS, L, 1, &LS->buffer);

    const char* b = pb_buffer(&LS->buffer);
    len = pb_bufflen(&LS->buffer);

    memcpy(buff, b, len);

    lua_pushinteger(L, len);
    return 1;
}

int luaopen_pbext(lua_State* L)
{
    luaL_Reg libs[] = {
        {"init", init},
        {"encode_and_save", encode_and_save},
        { "encode", encode_test },
        { "decode", decode_test },
        { NULL, NULL }
    };
    luaL_newlib(L, libs);
    return 1;
}

/*

1. 没有暴露lpb_State等接口，不方便二次开发
2. lpb_type为什么不用指针，里面为什么要copy一次，考虑直接用 pb_type ？？
3. 使用了argcheck luaL_checktype等接口，如果从C\C++调用的话，打印出来的堆栈不太对
    encode一定是从lua调的，这个还好
    decode得弄个last error的方式
4. lpb_useenchooks会在一定程序上影响性能，考虑定义个宏去掉
4. pb_prepbuffsize，提供一个足够大的缓冲区，就不会触发分配，感觉也还能接受

*/

PB_NS_END

