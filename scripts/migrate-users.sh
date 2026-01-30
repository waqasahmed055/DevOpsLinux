#!/bin/bash

# Define source and destination base directories
SRC_BASE="/home"
DEST_BASE="migrate/home"

# List of users (replace with actual usernames)
USERS=("user1" "user2" "user3")

# Loop through each user
for USER in "${USERS[@]}"; do
    SRC_DIR="$SRC_BASE/$USER/.ssh"
    DEST_DIR="$DEST_BASE/$USER/.ssh"
    
    # Check if source .ssh directory exists
    if [ -d "$SRC_DIR" ]; then
        # Create destination directory
        mkdir -p "$DEST_DIR"
        # Copy .ssh directory preserving permissions
        cp -rp "$SRC_DIR"/. "$DEST_DIR"/
        echo "Copied $SRC_DIR to $DEST_DIR"
    else
        echo "Warning: $SRC_DIR does not exist, skipping..."
    fi
done
