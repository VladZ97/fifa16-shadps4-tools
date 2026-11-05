#!/bin/bash
# Fallback for FIFA 16.app: double-click in Finder to start the game in a Terminal window,
# exactly as `bash ~/fifa_metal/run.sh play` (no launcher settings are applied here).
# Stop it with: bash ~/fifa_metal/run.sh stop   (or the app's Stop button).
bash "$HOME/fifa_metal/run.sh" play
status=$?
echo
read -r -p 'Press Return to close this window.' _
exit $status
