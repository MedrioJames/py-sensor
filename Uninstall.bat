@echo off
title py-sensor - Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
if not "%errorlevel%"=="0" (
    echo.
    pause
)
