@echo off
REM harmony DS device unit test: build ohosTest hap, install, run hypium, restore release hap.
REM NOTE: keep this file ASCII-only. cmd.exe parses batch files in the system ANSI codepage;
REM UTF-8 Chinese comments corrupt the parser and break every following line.
REM Usage: scripts\test.cmd [suite name], e.g. scripts\test.cmd characterCard
setlocal
set DEVECO_SDK_HOME=D:\Program Files\Huawei\DevEco Studio\sdk
set JAVA_HOME=D:\Program Files\Huawei\DevEco Studio\jbr
set PATH=%JAVA_HOME%\bin;%PATH%
set NODE=D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe
set HVIGOR=D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js
set HDC=D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe
if not exist "%HDC%" set HDC=hdc
set BUNDLE=com.harmonyds.chat
set TEST_HAP=entry\build\default\outputs\ohosTest\entry-ohosTest-signed.hap
if not exist "%TEST_HAP%" set TEST_HAP=entry\build\default\outputs\ohosTest\entry-ohosTest-default-signed.hap
cd /d "%~dp0.."

echo [1/4] building ohosTest hap...
"%NODE%" "%HVIGOR%" --mode module -p module=entry@ohosTest assembleHap --no-daemon
if errorlevel 1 goto :fail

echo [2/4] installing test hap (app data kept)...
"%HDC%" install -r %TEST_HAP%
if errorlevel 1 goto :fail

echo [3/4] running hypium suite...
if "%~1"=="" (
  "%HDC%" shell aa test -b %BUNDLE% -m entry -s unittest OpenHarmonyTestRunner -s timeout 15000
) else (
  "%HDC%" shell aa test -b %BUNDLE% -m entry -s unittest OpenHarmonyTestRunner -s class %~1 -s timeout 15000
)

echo [4/4] restoring normal hap...
"%HDC%" install -r entry\build\default\outputs\default\entry-default-signed.hap
"%HDC%" shell aa start -a EntryAbility -b %BUNDLE%
endlocal
exit /b 0

:fail
echo FAILED: check device connection (hdc list targets) and that the normal hap is built (scripts\build.cmd)
endlocal
exit /b 1
