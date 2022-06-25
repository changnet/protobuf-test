#include <string.h>

#include "pb_ext.h"

PB_NS_BEGIN

int Lext_encode(void* LS, lua_State* L, int index, pb_Buffer *b)
{
    // Lpb_encode(L);
    lpb_Env e;
    const pb_Type* t = lpb_type(LS, lpb_checkslice(L, index));

    luaL_checktype(L, index + 1, LUA_TTABLE);

    // lpb_encodeҪ��ջ���ض�����Ҫ���������
    if (lua_gettop(L) != index + 1) return -1;

    // argcheck(L, t != NULL, 1, "type '%s' does not exists", lua_tostring(L, 1));

    e.L = L, e.LS = LS, e.b = b;
    // ��������ݣ���д����pb_Buffer *b = e->b;

    lpb_encode(&e, t);

    return 0;
}

int lext_decode(void* LS, lua_State* L, pb_Slice* s)
{
    // pb_lslice(data, size) ��const char *����slice
    const pb_Type* t = lpb_type(LS, lpb_checkslice(L, 1));
    lpb_Env e;
    //argcheck(L, t != NULL, 1, "type '%s' does not exists", lua_tostring(L, 1));
    
    lpb_pushtypetable(L, LS, t);
    e.L = L, e.LS = LS, e.s = s;
    return lpbD_message(&e, t);
}

////////////////////////////////////////////////////////////////////////////////

// ��ʱ��һЩ�������ڲ���
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
    // Ϊ��ģ�����ݴ�socket���գ�����ֱ�Ӵ���һ��encode��bufferȡ���ݣ�����lua
    // �Ǳ�ȡ����
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

1. û�б�¶lpb_State�Ƚӿڣ���������ο���
2. lpb_typeΪʲô����ָ�룬����ΪʲôҪcopyһ�Σ�����ֱ���� pb_type ����
3. ʹ����argcheck luaL_checktype�Ƚӿڣ������C\C++���õĻ�����ӡ�����Ķ�ջ��̫��
    encodeһ���Ǵ�lua���ģ��������
    decode��Ū��last error�ķ�ʽ
4. lpb_useenchooks����һ��������Ӱ�����ܣ����Ƕ������ȥ��
4. pb_prepbuffsize���ṩһ���㹻��Ļ��������Ͳ��ᴥ�����䣬�о�Ҳ���ܽ���

*/

PB_NS_END

