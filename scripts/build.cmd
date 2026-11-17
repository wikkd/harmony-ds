@echo off
REM harmony DS 构建脚本：DevEco CLI 构建（无需打开 IDE）
REM 用法: scripts\build.cmd [assembleHap]  默认 assembleHap
setlocal
set DEVECO_SDK_HOME=D:\Program Files\Huawei\DevEco Studio\sdk
set JAVA_HOME=D:\Program Files\Huawei\DevEco Studio\jbr
set PATH=%JAVA_HOME%\bin;%PATH%
set NODE=D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe
set HVIGOR=D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js
cd /d "%~dp0.."
"%NODE%" "%HVIGOR%" --mode module -p module=entry@default %1 --no-daemon %2 %3
endlocal
