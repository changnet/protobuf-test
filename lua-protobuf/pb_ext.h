#ifndef pb_ext_h
#define pb_ext_h

#include "pb.h"

#include <lua.h>
#include <lauxlib.h>

PB_NS_BEGIN



/**
 * @brief 获取lpb_State，因为lpb_State结构不在pb.h声明，只能用void指针替代
 * @param L lua虚拟机
 * @return 
*/
void* lext_state(lua_State* L);

/**
 * @brief 把lua table打包到缓冲区中
 * @param LS lpb_State指针
 * @param L lua虚拟机
 * @param index 需要打包的lua table在栈中的索引
 * @param b 缓冲区指针
 * @return 成功返回0
*/
int lext_encode(void *LS, lua_State* L, int index, pb_Buffer* b);

/**
 * @brief 解析protobuf数据到lua table
 * @param LS lpb_State指针
 * @param L lua虚拟机
 * @param s 待解析protobuf数据到
 * @return 成功返回0
*/
int lext_decode(void* LS, lua_State* L, pb_Slice *s);

int lext_pack(lua_State* L, int index);
int lext_unpack(lua_State* L, int index);

int luaopen_pbext(lua_State* L);

PB_NS_END

#endif /* pb_ext_h */
