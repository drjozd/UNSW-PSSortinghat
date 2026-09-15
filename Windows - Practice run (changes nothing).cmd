@echo off
REM ---------------------------------------------------------------
REM  A practice run: a fake class in a fake team. Nothing real can
REM  change. Use this to learn the tool or to show someone else.
REM ---------------------------------------------------------------
setlocal
cd /d "%~dp0"
title Sortinghat (practice run)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\Start-Sortinghat.ps1" -Mock %*
pause
endlocal
