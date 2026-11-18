@echo off
REM harmony DS 真机单测脚本：构建 ohosTest HAP -^> 安装 -^> 跑 hypium 用例 -^> 恢复正式包
REM 注意：运行期间测试包会临时替换正式包，脚本结束前自动恢复（-r 安装不丢应用数据）
REM 用法: scripts\test.cmd [class 名]  如 scripts\test.cmd mathConverter
setlocal
set DEVECO_SDK_HOME=D:\Program Files\Huawei\DevEco Studio\sdk
set JAVA_HOME=D:\Program Files\Huawei\DevEco Studio\jbr
set PATH=%JAVA_HOME%\bin;%PATH%
set NODE=D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe
set HVIGOR=D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js
set HDC="D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
if not exist %HDC% set HDC=hdc
set BUNDLE=com.harmonyds.chat
set TEST_HAP=entry\build\default\outputs\ohosTest\entry-ohosTest-signed.hap
if not exist %TEST_HAP% set TEST_HAP=entry\build\default\outputs\ohosTest\entry-ohosTest-default-signed.hap
cd /d "%~dp0.."

echo [1/4] 构建 ohosTest HAP...
"%NODE%" "%HVIGOR%" --mode module -p module=entry@ohosTest assembleHap --no-daemon
if errorlevel 1 goto :fail

echo [2/4] 安装测试包（应用数据保留）...
%HDC% install -r %TEST_HAP%
if errorlevel 1 goto :fail

echo [3/4] 运行 hypium 用例...
if "%~1"=="" (
  %HDC% shell aa test -b %BUNDLE% -m entry -s unittest OpenHarmonyTestRunner -s timeout 15000
) else (
  %HDC% shell aa test -b %BUNDLE% -m entry -s unittest OpenHarmonyTestRunner -s class %~1 -s timeout 15000
)

echo [4/4] 恢复正式包...
%HDC% install -r entry\build\default\outputs\default\entry-default-signed.hap
%HDC% shell aa start -a EntryAbility -b %BUNDLE%
endlocal
exit /b 0

:fail
echo 失败：确认设备已连接（hdc list targets）、正式 HAP 已构建（scripts\build.cmd）
endlocal
exit /b 1
