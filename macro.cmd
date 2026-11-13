@echo off
rem Abre o Macro App.
rem   macro.cmd --simular   testa sem o SAP
rem   macro.cmd --64        usa o PowerShell de 64 bits (so para SAP GUI de 64 bits)
setlocal
set "RAIZ=%~dp0."
set "ROTEIRO=%~dp0macro.ps1"

rem O SAP GUI normalmente e de 32 bits, e so um PowerShell de 32 bits consegue falar com ele.
set "PS=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"

set "MACRO_ARGS="
:argumentos
if "%~1"=="" goto abrir
if /i "%~1"=="--simular" set "MACRO_ARGS=-Simular"
if /i "%~1"=="--64" set "PS=powershell"
shift /1
goto argumentos

:abrir
rem O script e lido como texto para funcionar mesmo com a execucao de .ps1 restrita.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath '%ROTEIRO%'))) -Raiz '%RAIZ%' %MACRO_ARGS%"
if errorlevel 1 pause
