@echo off
REM ============================================================
REM  Firma Digital - Token Service
REM  Doble clic para desinstalar la version previa e instalar
REM  la nueva. Pide elevacion (UAC) y reinicia al finalizar.
REM ============================================================
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Deploy-TokenService.ps1" %*
set RC=%ERRORLEVEL%

echo.
echo Codigo de salida: %RC%
if "%RC%"=="0"    echo Resultado: OK
if "%RC%"=="3010" echo Resultado: OK, requiere reinicio
if %RC% GEQ 69000 echo Resultado: ERROR. Revisar C:\Windows\Logs\Software\

REM Sin pausa si se ejecuta de forma desatendida (GPO/SCCM/Intune)
if not "%1"=="" goto :fin
echo.
pause
:fin
exit /b %RC%
