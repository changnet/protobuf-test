#ifndef pb_ext_h
#define pb_ext_h

#include "pb.h"

#include <lua.h>
#include <lauxlib.h>

PB_NS_BEGIN



/**
 * @brief ��ȡlpb_State����Ϊlpb_State�ṹ����pb.h������ֻ����voidָ�����
 * @param L lua�����
 * @return 
*/
void* lext_state(lua_State* L);

/**
 * @brief ��lua table�������������
 * @param LS lpb_Stateָ��
 * @param L lua�����
 * @param index ��Ҫ�����lua table��ջ�е�����
 * @param b ������ָ��
 * @return �ɹ�����0
*/
int lext_encode(void *LS, lua_State* L, int index, pb_Buffer* b);

/**
 * @brief ����protobuf���ݵ�lua table
 * @param LS lpb_Stateָ��
 * @param L lua�����
 * @param s ������protobuf���ݵ�
 * @return �ɹ�����0
*/
int lext_decode(void* LS, lua_State* L, pb_Slice *s);

int lext_pack(lua_State* L, int index);
int lext_unpack(lua_State* L, int index);

int luaopen_pbext(lua_State* L);

PB_NS_END

#endif /* pb_ext_h */
