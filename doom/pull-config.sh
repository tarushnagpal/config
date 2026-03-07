#!/usr/bin/env bash

# Pull Doom Emacs config from the active config directory into this repo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOOM_DIRECTORY_PERSONAL="$HOME/.doom.d"
DOOM_DIRECTORY_WORK="$HOME/.config/doom"
CONFIG_FILES=(config.el config.org init.el packages.el)

if [[ -d "$DOOM_DIRECTORY_PERSONAL" ]]; then
	SOURCE_DIR="$DOOM_DIRECTORY_PERSONAL"
elif [[ -d "$DOOM_DIRECTORY_WORK" ]]; then
	SOURCE_DIR="$DOOM_DIRECTORY_WORK"
else
	echo "No Doom config directory found!"
	exit 1
fi

for file in "${CONFIG_FILES[@]}"; do
	if [[ -f "$SOURCE_DIR/$file" ]]; then
		cp "$SOURCE_DIR/$file" "$SCRIPT_DIR/$file"
	else
		echo "Warning: $file not found in $SOURCE_DIR, skipping."
	fi
done

echo "Pulled Doom config from $SOURCE_DIR into repo."
