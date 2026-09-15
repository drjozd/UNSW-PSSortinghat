#!/bin/bash
# ---------------------------------------------------------------
#  A practice run: a fake class in a fake team. Nothing real can
#  change. Use this to learn the tool or to show someone else.
# ---------------------------------------------------------------
cd "$(dirname "$0")" || exit 1

if ! command -v pwsh >/dev/null 2>&1; then
  echo
  echo "  Sortinghat needs PowerShell 7:  brew install --cask powershell"
  echo
  read -r -p "  Press Return to close. " _
  exit 1
fi

pwsh -NoProfile -File "./app/Start-Sortinghat.ps1" -Mock "$@"
echo
read -r -p "  Press Return to close. " _
