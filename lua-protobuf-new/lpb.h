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

lpb_State* default_lstate(lua_State* L);

void lpb_encode(lpb_Env* e, const pb_Type* t);

const pb_Type* lpb_type(lpb_State* LS, pb_Slice s);

pb_Slice lpb_checkslice(lua_State* L, int idx);

int lpbD_message(lpb_Env* e, const pb_Type* t);

void lpb_pushtypetable(lua_State* L, lpb_State* LS, const pb_Type* t);

PB_NS_END

#endif /* lpb_h */
