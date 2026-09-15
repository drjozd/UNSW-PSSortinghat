#!/bin/bash
# ---------------------------------------------------------------
#  Practice mode - a fake class, a fake team, nothing real.
#  macOS or Linux. Windows users: use the .cmd of the same name.
# ---------------------------------------------------------------
cd "$(dirname "$0")" || exit 1

if ! command -v pwsh >/dev/null 2>&1; then
  echo
  echo "  Sortinghat needs PowerShell 7: brew install --cask powershell"
  echo
  read -r -p "  Press Return to close. " _
  exit 1
fi

pwsh -NoProfile -File "./Start-Sortinghat.ps1" -Mock
echo
read -r -p "  Press Return to close. " _
