#!/bin/bash

set -euo pipefail

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --csv)
            CSV_FILE="$2"
            shift 2
            ;;
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --gtf)
            GTF_FILE="$2"
            shift 2
            ;;
        --genome)
            GENOME_FA="$2"
            shift 2
            ;;
        --star-index)
            STAR_INDEX_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 --csv <file> --data-dir <dir> --gtf <file> --genome <file> --star-index <dir> --output <dir>" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
MISSING_ARGS=()
[ -z "${CSV_FILE:-}" ] && MISSING_ARGS+=("--csv")
[ -z "${DATA_DIR:-}" ] && MISSING_ARGS+=("--data-dir")
[ -z "${GTF_FILE:-}" ] && MISSING_ARGS+=("--gtf")
[ -z "${GENOME_FA:-}" ] && MISSING_ARGS+=("--genome")
[ -z "${STAR_INDEX_DIR:-}" ] && MISSING_ARGS+=("--star-index")
[ -z "${OUTPUT_DIR:-}" ] && MISSING_ARGS+=("--output")

if [ ${#MISSING_ARGS[@]} -gt 0 ]; then
    echo "Error: Missing required argument(s): ${MISSING_ARGS[*]}" >&2
    echo "Usage: $0 --csv <file> --data-dir <dir> --gtf <file> --genome <file> --star-index <dir> --output <dir>" >&2
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Read the specific row for this array task
LINE_NUM=$((SLURM_ARRAY_TASK_ID))
ROW=$(sed -n "${LINE_NUM}p" "$CSV_FILE")

# Parse CSV columns
IFS=',' read -r SAMPLE_ID FILE_ID1 FILE_ID2 LIBRARY_TYPE <<< "$ROW"

echo "Processing sample: $SAMPLE_ID"
echo "File ID 1: $FILE_ID1"
echo "File ID 2: $FILE_ID2"
echo "Library type: $LIBRARY_TYPE"

# Skip if library type is not TRANSCRIPTOMIC
if [ "$LIBRARY_TYPE" != "TRANSCRIPTOMIC" ]; then
    echo "Skipping sample $SAMPLE_ID - library type is $LIBRARY_TYPE (not TRANSCRIPTOMIC)"
    exit 0
fi

# Locate FASTQ files in their respective directories
DIR1="$DATA_DIR/$FILE_ID1"
DIR2="$DATA_DIR/$FILE_ID2"

FASTQ1=$(find "$DIR1" -maxdepth 1 -name "*.fastq.gz" -type f)
FASTQ2=$(find "$DIR2" -maxdepth 1 -name "*.fastq.gz" -type f)

if [ -z "$FASTQ1" ] || [ -z "$FASTQ2" ]; then
    echo "Error: Could not find FASTQ files in $DIR1 or $DIR2" >&2
    exit 1
fi

# Determine which file ends in 1 and which ends in 2
BASENAME1=$(basename "$FASTQ1" .fastq.gz)
BASENAME2=$(basename "$FASTQ2" .fastq.gz)

LAST_CHAR1="${BASENAME1: -1}"
LAST_CHAR2="${BASENAME2: -1}"

if [ "$LAST_CHAR1" = "1" ] && [ "$LAST_CHAR2" = "2" ]; then
    READ1="$FASTQ1"
    READ2="$FASTQ2"
elif [ "$LAST_CHAR1" = "2" ] && [ "$LAST_CHAR2" = "1" ]; then
    READ1="$FASTQ2"
    READ2="$FASTQ1"
else
    echo "Error: Could not determine which file is read 1 and which is read 2" >&2
    exit 1
fi

echo "Read 1: $READ1"
echo "Read 2: $READ2"

# Create sample-specific output directory
SAMPLE_OUTPUT_DIR="$OUTPUT_DIR/$SAMPLE_ID"
mkdir -p "$SAMPLE_OUTPUT_DIR"

# Run STAR alignment
STAR \
    --runThreadN "$SLURM_CPUS_ON_NODE" \
    --genomeDir "$STAR_INDEX_DIR" \
    --readFilesIn "$READ1" "$READ2" \
    --readFilesCommand zcat \
    --outFileNamePrefix "${SAMPLE_OUTPUT_DIR}/" \
    --outSAMtype BAM SortedByCoordinate \
    --outSAMunmapped Within \
    --outSAMattributes Standard \
    --quantMode GeneCounts \
    --twopassMode Basic

echo "STAR alignment completed for sample $SAMPLE_ID"
