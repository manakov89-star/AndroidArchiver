@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not exist "C:\projects\AndroidArchiver\obj" mkdir "C:\projects\AndroidArchiver\obj"
cl /nologo /std:c++17 /utf-8 /W3 /D WIN32_LEAN_AND_MEAN /D _DLL /D _USRDLL /c /Fo"C:\projects\AndroidArchiver\obj\AndroidArchiveCommand.obj" "C:\projects\AndroidArchiver\src\AndroidArchiveCommand.cpp"
link /nologo /DLL /OUT:"C:\projects\AndroidArchiver\AndroidArchiveCmd.dll" "C:\projects\AndroidArchiver\obj\AndroidArchiveCommand.obj" /DEF:"C:\projects\AndroidArchiver\src\AndroidArchiveCmd.def" ole32.lib user32.lib shell32.lib
echo BUILD_EXIT=%errorlevel%