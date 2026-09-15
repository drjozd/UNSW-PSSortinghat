@echo off
REM ---------------------------------------------------------------
REM  Sortinghat - double-click this file to start.
REM  The program itself lives in the app folder; nothing in there
REM  needs to be run by hand.
REM ---------------------------------------------------------------
setlocal
cd /d "%~dp0"
title Sortinghat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\Start-Sortinghat.ps1" %*
set EXITCODE=%ERRORLEVEL%
if not "%EXITCODE%"=="0" (
  echo.
  echo   Sortinghat stopped. The message above explains why.
  echo   If you are stuck, open README.md and read "When something goes wrong".
  echo.
  pause
)
endlocal
