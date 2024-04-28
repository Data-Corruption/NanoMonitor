@echo off

REM Set the path to the Visual Studio vcvars64.bat or vcvars32.bat file
CALL "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

REM Create the bin directory if it doesn't exist
if not exist "./bin" mkdir ./bin
if not exist "./bin/obj" mkdir ./bin/obj

REM Compile the source code
cl /std:c++17 /EHsc ./src/main.cpp ./src/gpu.cpp ./src/cpu.cpp ./src/log.cpp /I "./deps/nvapi/include" /Fo"./bin/obj/" /Fe"./bin/NanoMonitor.exe" /link /machine:x64 /LIBPATH:"./deps/nvapi/lib" pdh.lib User32.lib Gdi32.lib nvapi64.lib

