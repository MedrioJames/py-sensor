@echo off
title py-sensor - Setup
echo.
echo   py-sensor - Setup
echo   Downloading the latest setup from GitHub...
echo.

set "PYSENSOR_TEMP_INSTALL=%TEMP%\py-sensor-install.ps1"
if exist "%PYSENSOR_TEMP_INSTALL%" del "%PYSENSOR_TEMP_INSTALL%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/MedrioJames/py-sensor/main/install.ps1' -OutFile '%PYSENSOR_TEMP_INSTALL%'"

if not exist "%PYSENSOR_TEMP_INSTALL%" (
    echo.
    echo   Could not download the setup script. Check your internet connection and try again.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PYSENSOR_TEMP_INSTALL%"
set "PYSENSOR_EXIT_CODE=%errorlevel%"

del "%PYSENSOR_TEMP_INSTALL%" >nul 2>&1

if not "%PYSENSOR_EXIT_CODE%"=="0" (
    echo.
    pause
)
