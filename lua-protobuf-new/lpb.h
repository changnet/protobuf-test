#ifndef lpb_h
#define lpb_h

#define PB_STATIC_API
#include "pb.h"

#define LUA_LIB
#include <lua.h>
#include <lauxlib.h>

PB_NS_BEGIN

typedef struct lpb_State {
    const pb_State* state;
    pb_State  local;
    pb_Cache  cache;
    pb_Buffer buffer;
    int defs_index;
    int enc_hooks_index;
    int dec_hooks_index;
    unsigned use_hooks : 1; /* lpb_Int64Mode */
    unsigned enum_as_value : 1;
    unsigned default_mode : 2; /* lpb_DefMode */
    unsigned int64_mode : 2; /* lpb_Int64Mode */
    unsigned encode_default_values : 1;
    unsigned decode_default_array : 1;
    unsigned decode_default_message : 1;
    unsigned encode_order : 1;
} lpb_State;

typedef struct lpb_Env {
    lua_State* L;
    lpb_State* LS;
    pb_Buffer* b;
    pb_Slice* s;
} lpb_Env;

#define pb_error_field "__pb_last_strerror"

lpb_State* default_lstate(lua_State* L);

void lpb_encode(lpb_Env* e, const pb_Type* t);

const pb_Type* lpb_type(lpb_State* LS, pb_Slice s);

pb_Slice lpb_checkslice(lua_State* L, int idx);

int lpbD_message(lpb_Env* e, const pb_Type* t);

void lpb_pushtypetable(lua_State* L, lpb_State* LS, const pb_Type* t);

inline void lpb_set_error(lua_State* L, const char* fmt, ...)
{
    va_list l;
    va_start(l, fmt);
    lua_pushvfstring(L, fmt, l);
    va_end(l);

    lua_setglobal(L, pb_error_field);
}

inline int lpb_error(lua_State* L) {
    lua_getglobal(L, pb_error_field);

    lua_pushnil(L);
    lua_setglobal(L, pb_error_field);

    return lua_error(L);
}

inline int comp_field(const void* a, const void* b) {
    return (*(const pb_Field**)a)->number - (*(const pb_Field**)b)->number;
}

PB_API const pb_Field* pb_sortfield(pb_Type* t) {
    if (!t->field_sort && t->field_count) {
        pb_Field** list = malloc(sizeof(pb_Field*) * t->field_count);

        int index = 0;
        const pb_Field* f = NULL;
        while (pb_nextfield(t, &f)) {
            list[index++] = (pb_Field*)f;
        }

        qsort(list, index, sizeof(pb_Field*), comp_field);
        t->field_sort = list;
    }

    return t->field_sort ? *t->field_sort : NULL;
}

/*
#define lpb_checkstack(L, n, msg)   \
    do {if (!lua_checkstack(L, n)) lpb_error(L, msg);} while(0)

#define lpb_checktable(L, f) \
    do{\
        if(!lua_istable(L, -1))\
            lpb_error("table expected at field '%s', got %s",\
            (const char*)f->name, luaL_typename(L, -1));\
    } while (0)

#define lpb_argcheck(L, cond, idx, fmt, ...) \
    do {\
        if (!cond) lpb_error(L, "bad argument #%d " fmt, idx, __VA_ARGS__);\
    } while (0)
*/
PB_NS_END

#endif /* lpb_h */
