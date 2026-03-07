#!/usr/bin/env bash

# Push Doom Emacs config from this repo into the active config directory

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOOM_DIRECTORY_PERSONAL="$HOME/.doom.d"
DOOM_DIRECTORY_WORK="$HOME/.config/doom"
CONFIG_FILES=(config.el config.org init.el packages.el)

if [[ -d "$DOOM_DIRECTORY_PERSONAL" ]]; then
	DEST_DIR="$DOOM_DIRECTORY_PERSONAL"
elif [[ -d "$DOOM_DIRECTORY_WORK" ]]; then
	DEST_DIR="$DOOM_DIRECTORY_WORK"
else
	echo "No Doom config directory found!"
	exit 1
fi

for file in "${CONFIG_FILES[@]}"; do
	if [[ -f "$SCRIPT_DIR/$file" ]]; then
		cp "$SCRIPT_DIR/$file" "$DEST_DIR/$file"
	else
		echo "Warning: $file not found in repo, skipping."
	fi
done

echo "Pushed Doom config from repo to $DEST_DIR."
