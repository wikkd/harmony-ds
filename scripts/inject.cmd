@echo off
REM harmony DS test message injection (Debug builds only). Keep this file ASCII-only.
REM Usage: scripts\inject.cmd math|md|long     inject fixture session
REM        scripts\inject.cmd send <text>     real send in current session (real SSE)
REM        scripts\inject.cmd key <sk-...>    verify and save API key
setlocal
set HDC=D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe
if not exist "%HDC%" set HDC=hdc
if "%~1"=="" (
  echo Usage: scripts\inject.cmd math^|md^|long ^| send ^<text^> ^| key ^<sk-...^>
  exit /b 1
)
if /I "%~1"=="send" (
  "%HDC%" shell aa start -a EntryAbility -b com.harmonyds.chat --ps testSend "%~2"
) else if /I "%~1"=="key" (
  "%HDC%" shell aa start -a EntryAbility -b com.harmonyds.chat --ps testKey "%~2"
) else (
  "%HDC%" shell aa start -a EntryAbility -b com.harmonyds.chat --ps testInject %~1
)
endlocal
