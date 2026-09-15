@echo off
REM ---------------------------------------------------------------
REM  Practice mode - a fake class, a fake team, nothing real.
REM  Use this to learn the tool, or to show someone else how it works.
REM ---------------------------------------------------------------
setlocal
cd /d "%~dp0"
title Sortinghat (practice mode)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Sortinghat.ps1" -Mock
pause
endlocal
