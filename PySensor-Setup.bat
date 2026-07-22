@echo off
title py-sensor - Setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if not "%errorlevel%"=="0" (
    echo.
    pause
)
