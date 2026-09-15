#!/bin/bash
# ---------------------------------------------------------------
#  Sortinghat - double-click this file to start (macOS).
#  The program itself lives in the app folder; nothing in there
#  needs to be run by hand.
# ---------------------------------------------------------------
cd "$(dirname "$0")" || exit 1

if ! command -v pwsh >/dev/null 2>&1; then
  cat <<'MSG'

  Sortinghat needs PowerShell 7, which macOS does not include.

  The easiest way to install it, if you have Homebrew:

      brew install --cask powershell

  Otherwise download the .pkg for your Mac from
  https://github.com/PowerShell/PowerShell/releases
  (choose "osx-arm64.pkg" on Apple Silicon, "osx-x64.pkg" on Intel).

  Then double-click this file again.

MSG
  read -r -p "  Press Return to close. " _
  exit 1
fi

pwsh -NoProfile -File "./app/Start-Sortinghat.ps1" "$@"
status=$?
if [ $status -ne 0 ]; then
  echo
  echo "  Sortinghat stopped. The message above explains why."
  echo "  If you are stuck, open README.md and read \"When something goes wrong\"."
  echo
  read -r -p "  Press Return to close. " _
fi
