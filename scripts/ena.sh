#!/bin/bash

# --- CONFIGURATION ---
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <URL_FILE> <TARGET_DIR>"
    echo "  URL_FILE   : Path to your file containing FTP URLs."
    echo "  TARGET_DIR : Directory where files will be downloaded."
    exit 1
fi

URL_FILE="$1"              # Path to your file containing FTP URLs
TARGET_DIR="$2"

# 1. Validation
if [[ ! -f "$URL_FILE" ]]; then
    echo "Error: URL list '$URL_FILE' not found."
    exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

echo "Job started on node $(hostname) at $(date)"
echo "Downloading files to: $TARGET_DIR"
echo "----------------------------------------------------"

# 2. The Download Loop
while IFS= read -r url || [[ -n "$url" ]]; do
    # Clean the line (remove carriage returns/whitespace)
    url=$(echo "$url" | tr -d '\r' | xargs)
    
    # Skip empty lines or comments
    [[ -z "$url" || "$url" =~ ^# ]] && continue

    mkdir -p "$TARGET_DIR"

    filename=$(basename "$url")
    filepath="${TARGET_DIR}/${filename}"

    if [[ -f "$filepath" ]]; then
        echo "[SKIP] ${filename} already exists."
    else
        echo "[GET]  $url"
        
        # wget parameters:
        # -c: Resume partially downloaded files
        # -P: Save to target directory
        # --tries=10: Retry on connection failure
        # --waitretry=5: Wait 5s between retries
        wget -q -c -P "$dirpath" --tries=10 --waitretry=5 "$url"
        
        if [[ $? -eq 0 ]]; then
            echo "[DONE] Successfully downloaded $filename"
        else
            echo "[FAIL] Error downloading $url" >&2
        fi
    fi
done < "$URL_FILE"

echo "----------------------------------------------------"
echo "Job finished at $(date)"
