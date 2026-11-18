@echo off
REM 测试消息注入：向应用注入固定夹具或触发真实发送（Debug 构建有效）
REM 用法: scripts\inject.cmd math|md|long 注入夹具会话
REM       scripts\inject.cmd send <文本>  当前会话真实发送（真 SSE）
REM       scripts\inject.cmd key <sk-...> 校验并保存 API Key
setlocal
set HDC="D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
if not exist %HDC% set HDC=hdc
if "%~1"=="" (
  echo 用法: scripts\inject.cmd math^|md^|long ^| send ^<文本^> ^| key ^<sk-...^>
  exit /b 1
)
if /I "%~1"=="send" (
  %HDC% shell aa start -a EntryAbility -b com.harmonyds.chat --ps testSend "%~2"
) else if /I "%~1"=="key" (
  %HDC% shell aa start -a EntryAbility -b com.harmonyds.chat --ps testKey "%~2"
) else (
  %HDC% shell aa start -a EntryAbility -b com.harmonyds.chat --ps testInject %~1
)
endlocal
