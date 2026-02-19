#!/bin/bash

set -euo pipefail

# Usage: validate_fastq_file_existence.sh <csv_file> <data_dir> [--md5]
VALIDATE_MD5=false

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <csv_file> <data_dir> [--md5]" >&2
    exit 1
fi

CSV_FILE="$1"
DATA_DIR="$2"

if [ "$#" -eq 3 ]; then
    if [ "$3" = "--md5" ]; then
        VALIDATE_MD5=true
    else
        echo "Error: Unknown flag '$3'. Use --md5 for MD5 validation." >&2
        exit 1
    fi
fi

if [ ! -f "$CSV_FILE" ]; then
    echo "Error: CSV file '$CSV_FILE' not found" >&2
    exit 1
fi

# Function to validate directory contains exactly one .fastq.gz and one .fastq.gz.md5
validate_directory() {
    local dir="$1"
    local file_id="$2"

    if [ ! -d "$dir" ]; then
        echo "Error: Directory '$dir' does not exist for file_id '$file_id'" >&2
        return 1
    fi

    local fastq_count=$(find "$dir" -maxdepth 1 -name "*.fastq.gz" -type f | wc -l)
    local md5_count=$(find "$dir" -maxdepth 1 -name "*.fastq.gz.md5" -type f | wc -l)

    if [ "$fastq_count" -ne 1 ]; then
        echo "Error: Expected exactly 1 .fastq.gz file in '$dir', found $fastq_count" >&2
        return 1
    fi

    if [ "$md5_count" -ne 1 ]; then
        echo "Error: Expected exactly 1 .fastq.gz.md5 file in '$dir', found $md5_count" >&2
        return 1
    fi

    return 0
}

# Function to get fastq filename from directory
get_fastq_filename() {
    local dir="$1"
    find "$dir" -maxdepth 1 -name "*.fastq.gz" -type f -exec basename {} \;
}

# Function to validate MD5 checksum
validate_md5_checksum() {
    local dir="$1"
    local file_id="$2"

    local fastq_file=$(find "$dir" -maxdepth 1 -name "*.fastq.gz" -type f)
    local md5_file=$(find "$dir" -maxdepth 1 -name "*.fastq.gz.md5" -type f)

    if [ -z "$fastq_file" ] || [ -z "$md5_file" ]; then
        echo "Error: Could not find fastq.gz or md5 file in '$dir'" >&2
        return 1
    fi

    # Read expected MD5 from .md5 file (format is typically: "hash  filename" or just "hash")
    local expected_md5=$(awk '{print $1}' "$md5_file")

    # Compute actual MD5 of the fastq.gz file
    local actual_md5=$(md5sum "$fastq_file" | awk '{print $1}')

    if [ "$expected_md5" != "$actual_md5" ]; then
        echo "Error: MD5 checksum mismatch for '$fastq_file'" >&2
        echo "  Expected: $expected_md5" >&2
        echo "  Actual:   $actual_md5" >&2
        return 1
    fi

    return 0
}

# Function to validate filenames differ only at the last character before .fastq.gz with values "1" and "2"
validate_filename_pair() {
    local file1="$1"
    local file2="$2"

    # Remove the .fastq.gz suffix
    local base1="${file1%.fastq.gz}"
    local base2="${file2%.fastq.gz}"

    # Get the last character of the base filename
    local char1="${base1: -1}"
    local char2="${base2: -1}"

    # Check if one is "1" and the other is "2"
    if { [ "$char1" = "1" ] && [ "$char2" = "2" ]; } || { [ "$char1" = "2" ] && [ "$char2" = "1" ]; }; then
        # Check if rest of the filename is identical (everything except last char)
        local prefix1="${base1%?}"
        local prefix2="${base2%?}"

        if [ "$prefix1" != "$prefix2" ]; then
            echo "Error: Filenames differ in positions other than the last character before .fastq.gz" >&2
            echo "  File1: $file1" >&2
            echo "  File2: $file2" >&2
            return 1
        fi
    else
        echo "Error: Last character before .fastq.gz must be '1' in one file and '2' in the other" >&2
        echo "  File1 last char: '$char1'" >&2
        echo "  File2 last char: '$char2'" >&2
        return 1
    fi

    return 0
}

# Function to validate library type matches filename pattern
validate_library_pattern() {
    local filename="$1"
    local library="$2"

    if [ ${#filename} -lt 16 ]; then
        echo "Error: Filename is too short to check positions 8-15" >&2
        return 1
    fi

    local substring="${filename:8:7}"  # positions 8-15

    if [ "$library" = "GENOMIC" ]; then
        if [ "$substring" != "ngs_dna" ]; then
            echo "Error: GENOMIC library requires 'ngs_dna' at positions 8-15, found '$substring'" >&2
            return 1
        fi
    elif [ "$library" = "TRANSCRIPTOMIC" ]; then
        if [ "$substring" != "ngs_rna" ]; then
            echo "Error: TRANSCRIPTOMIC library requires 'ngs_rna' at positions 8-15, found '$substring'" >&2
            return 1
        fi
    else
        echo "Error: Unknown library type '$library'" >&2
        return 1
    fi

    return 0
}

# Main validation loop
error_count=0
line_num=0

while IFS=',' read -r sample file_id1 file_id2 library; do
    line_num=$((line_num + 1))

    # Skip empty lines
    [ -z "$file_id1" ] && continue

#    echo "Validating row $line_num: file_id1=$file_id1, file_id2=$file_id2, library=$library"

    dir1="$DATA_DIR/$file_id1"
    dir2="$DATA_DIR/$file_id2"

    # Validate both directories
    if ! validate_directory "$dir1" "$file_id1"; then
        error_count=$((error_count + 1))
        continue
    fi

    if ! validate_directory "$dir2" "$file_id2"; then
        error_count=$((error_count + 1))
        continue
    fi

    # Get filenames
    fastq1=$(get_fastq_filename "$dir1")
    fastq2=$(get_fastq_filename "$dir2")

    # Validate filename pair
    if ! validate_filename_pair "$fastq1" "$fastq2"; then
        error_count=$((error_count + 1))
        continue
    fi

    # Validate library pattern for both files
    if ! validate_library_pattern "$fastq1" "$library"; then
        error_count=$((error_count + 1))
        continue
    fi

    if ! validate_library_pattern "$fastq2" "$library"; then
        error_count=$((error_count + 1))
        continue
    fi

    # Validate MD5 checksums if flag is enabled
    if [ "$VALIDATE_MD5" = true ]; then
        if ! validate_md5_checksum "$dir1" "$file_id1"; then
            error_count=$((error_count + 1))
            continue
        fi

        if ! validate_md5_checksum "$dir2" "$file_id2"; then
            error_count=$((error_count + 1))
            continue
        fi
    fi

#    echo "✓ Row $line_num validated successfully"


done < "$CSV_FILE"

if [ $error_count -gt 0 ]; then
    echo "Validation completed with $error_count error(s)" >&2
    exit 1
else
    echo "All validations passed successfully"
    exit 0
fi
