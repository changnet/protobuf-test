## protobuf测试

这里主要做一些protobuf库的对比测试。所有代码都是以测试为目的，不处理异常。部分代码可能有修改，尽量让所有库的调用方式一致。

#### 构建测试
1. 把[lua-protobuf](https://github.com/starwing/lua-protobuf) checkout到当前当前目录
2. 把[pbc](https://github.com/changnet/pbc)checkout到当前当前目录
3. 把[lua 5.5](http://lua.org/)的源码下载，解压到当前目录
4. 安装VS，修改下`build.bat`的路径执行测试。或者在Linux下直接执行`build.sh`进行测试

#### 结果
`pbc`我有进行修改，主要是一些性能优化，以及protobuf3支持。同时我是使用自己的binding。

测试结果日志
```
========================================================================================
1. ENCODE / DECODE THROUGHPUT (game server packets)
========================================================================================
message     op      lib             size(B)        ns/op       kops/s       MB/s
----------------------------------------------------------------------------------------
Heartbeat   encode  pbc_binding           9        257.3       3886.9      33.36
Heartbeat   decode  pbc_binding           9        373.5       2677.5      22.98
Heartbeat   encode  lua-protobuf          9        427.1       2341.4      20.10
Heartbeat   decode  lua-protobuf          9        373.4       2678.3      22.99
LoginReq    encode  pbc_binding          65        858.2       1165.2      72.23
LoginReq    decode  pbc_binding          65        972.5       1028.3      63.74
LoginReq    encode  lua-protobuf         65       1086.7        920.2      57.04
LoginReq    decode  lua-protobuf         65       1541.1        648.9      40.22
MoveSync    encode  pbc_binding          39        769.7       1299.3      48.32
MoveSync    decode  pbc_binding          39        898.4       1113.1      41.40
MoveSync    encode  lua-protobuf         39        894.1       1118.4      41.60
MoveSync    decode  lua-protobuf         39       1304.1        766.8      28.52
BagUpdate   encode  pbc_binding         437       5451.0        183.5      76.45
BagUpdate   decode  pbc_binding         437       7496.8        133.4      55.59
BagUpdate   encode  lua-protobuf        437       6619.2        151.1      62.96
BagUpdate   decode  lua-protobuf        437       8280.2        120.8      50.33
```

#### 旧版本测试
查看`README-old.md`，里面还有一个纯lua库的对比
