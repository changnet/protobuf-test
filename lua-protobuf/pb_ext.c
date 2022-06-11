#include "pb_ext.h"

PB_NS_BEGIN

void* Lext_state(lua_State* L)
{
    return default_lstate(L);
}

int Lext_encode(void* LS, lua_State* L, int index, pb_Buffer *b)
{
    // Lpb_encode(L);
    lpb_Env e;
    const pb_Type* t = lpb_type(LS, lpb_checkslice(L, index));

    luaL_checktype(L, index + 1, LUA_TTABLE);

    // lpb_encodeҪ��ջ���ض�����Ҫ���������
    if (lua_gettop(L) != index + 1) return -1;

    argcheck(L, t != NULL, 1, "type '%s' does not exists", lua_tostring(L, 1));

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
    argcheck(L, t != NULL, 1, "type '%s' does not exists", lua_tostring(L, 1));
    
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
    __LS = Lext_state(L);
    return 0;
}

int load(lua_State* L)
{
    lpb_State* LS = __LS;// default_lstate(L);
    const char* filename = luaL_checkstring(L, 1);
    size_t size;
    pb_Buffer b;
    pb_Slice s;
    int ret;
    FILE* fp = fopen(filename, "rb");
    if (fp == NULL)
        return luaL_fileresult(L, 0, filename);
    pb_initbuffer(&b);
    do {
        char* d = pb_prepbuffsize(&b, BUFSIZ);
        if (d == NULL) return fclose(fp), luaL_error(L, "out of memory");
        size = fread(d, 1, BUFSIZ, fp);
        pb_addsize(&b, size);
    } while (size == BUFSIZ);
    fclose(fp);
    s = pb_result(&b);
    ret = pb_load(&LS->local, &s);
    if (ret == PB_OK) global_state = &LS->local;
    pb_resetbuffer(&b);
    lua_pushboolean(L, ret == PB_OK);
    lua_pushinteger(L, pb_pos(s) + 1);
    return 2;
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
        {"load", load},
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

