@echo off
REM harmony DS deploy: install signed hap and launch the app. Keep this file ASCII-only
REM (cmd.exe parses batch files in the ANSI codepage; UTF-8 comments corrupt parsing).
setlocal
set HDC=D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe
if not exist "%HDC%" set HDC=hdc
cd /d "%~dp0.."

"%HDC%" list targets | findstr /C:"[Empty]" >nul && (
  echo No device found. Run: hdc list targets
  exit /b 1
)

"%HDC%" install -r entry\build\default\outputs\default\entry-default-signed.hap
if errorlevel 1 (
  echo Install failed. Build first: scripts\build.cmd assembleHap
  exit /b 1
)
"%HDC%" shell aa start -a EntryAbility -b com.harmonyds.chat
endlocal
