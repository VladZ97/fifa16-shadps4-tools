#!/bin/bash
# Test runner for a self-contained FIFA 16.app in an ISOLATED data folder (never the user's):
#   APP_UNDER_TEST=<.app> APP_DATA=<data dir> APP_SAVES=<saves dir> [APP_UPDATE=<dir>|none] bash app_runner.sh start|stop
export FIFA_APP="${APP_UNDER_TEST:?}" FIFA_DATA_DIR="${APP_DATA:?}" FIFA_SAVES_DIR="${APP_SAVES:?}"
export FIFA_GAME_DIR="/Volumes/SanDiskSSD/F16_02138_extracted/F16_02138/FIFA 16 - CUSA02138 + Update 1.07/FIFA_16/CUSA02138"
if [ "${APP_UPDATE:-}" = none ]; then unset FIFA_UPDATE_DIR; else export FIFA_UPDATE_DIR="${APP_UPDATE:-/Volumes/SanDiskSSD/F16_02138_extracted/F16_02138/FIFA 16 - CUSA02138 + Update 1.07/FIFA_16/CUSA02138-UPDATE}"; fi
export FIFA_MODS_DIR="${APP_MODS-$HOME/FIFA16Mods/merged}"
exec bash "$FIFA_APP/Contents/Resources/run.sh" "$@"
