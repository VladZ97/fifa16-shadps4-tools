#!/bin/zsh
# Points ~/fifa_run.sh back at the launcher's official Pre-release build.
sed -i '' 's#^EMU=.*#EMU="/Users/me/Library/Application Support/shadPS4QtLauncher/versions/Pre-release/shadps4"#' "$HOME/fifa_run.sh"; grep '^EMU=' "$HOME/fifa_run.sh"
