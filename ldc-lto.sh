ldc2 -i source/app.d -Isource -L-lgmp -L-lmpfr -of dext -O3 -ffast-math -enable-inlining -release --boundscheck=off -flto-binary=/usr/lib/llvm-10/lib/LLVMgold.so -flto=full