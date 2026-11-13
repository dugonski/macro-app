@echo off
rem Abre o Macro App.
rem   macro.cmd --simular   testa sem o SAP
rem   macro.cmd --32        usa o PowerShell de 32 bits
setlocal
set "RAIZ=%~dp0."
set "ROTEIRO=%~dp0macro.ps1"

set "PS=powershell"
set "PS32=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"

set "MACRO_ARGS="
:argumentos
if "%~1"=="" goto abrir
if /i "%~1"=="--simular" set "MACRO_ARGS=-Simular"
if /i "%~1"=="--32" if exist "%PS32%" set "PS=%PS32%"
shift /1
goto argumentos

:abrir
rem O script e lido como texto para funcionar mesmo com a execucao de .ps1 restrita.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath '%ROTEIRO%'))) -Raiz '%RAIZ%' %MACRO_ARGS%"
if errorlevel 1 pause
