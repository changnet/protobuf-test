#!/bin/sh

echo "run debug pbc test"
cd pbc
protoc -o addressbook.pb addressbook.proto
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make VERBOSE=1
cd ..
./pbctest

echo "run release pbc test"
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make VERBOSE=1
cd ..
./pbctest

echo "run debug lua-protobuf test"
cd ../lua-protobuf
protoc -o addressbook.pb addressbook.proto
gcc -g -o test test.c pb.c -llua -ldl -lm
./test

echo "run release lua-protobuf test"
gcc -O3 -DNDEBUG -o test test.c pb.c -llua -ldl -lm
./test

echo "run debug protolua test"
cd ../protolua
cd thirdparty
git clone https://github.com/google/protobuf.git
cd ..
cmake . -DCMAKE_BUILD_TYPE=Debug
make
cd protolua
./protolua

echo "run release protolua test"
cd ..
cmake . -DCMAKE_BUILD_TYPE=Release
make
cd protolua
./protolua
