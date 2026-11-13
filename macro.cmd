@echo off
rem Abre o Macro App. Use "macro.cmd --simular" para testar sem o SAP.
setlocal
set "MACRO_ARGS="
if /i "%~1"=="--simular" set "MACRO_ARGS=-Simular"
rem O script e lido como texto para funcionar mesmo com a execucao de .ps1 restrita.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath '%~dp0macro.ps1'))) -Raiz '%~dp0.' %MACRO_ARGS%"
if errorlevel 1 pause
