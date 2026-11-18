@echo off
REM harmony DS 部署脚本：安装已签名 HAP 并启动应用（构建请先跑 scripts\build.cmd）
REM 用法: scripts\install.cmd
setlocal
set HDC="D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
if not exist %HDC% set HDC=hdc
cd /d "%~dp0.."

%HDC% list targets | findstr /C:"[Empty]" >nul && (
  echo 未检测到设备，先 hdc list targets 确认连接
  exit /b 1
)

%HDC% install -r entry\build\default\outputs\default\entry-default-signed.hap
if errorlevel 1 (
  echo 安装失败：确认 HAP 已构建（scripts\build.cmd assembleHap）
  exit /b 1
)
%HDC% shell aa start -a EntryAbility -b com.harmonyds.chat
endlocal
