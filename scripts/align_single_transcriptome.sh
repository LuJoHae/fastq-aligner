#!/bin/bash

# set -euo pipefail

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
            echo "Usage: $0 --data-dir <dir> --gtf <file> --genome <file> --star-index <dir> --output <dir>" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
MISSING_ARGS=()
[ -z "${DATA_DIR:-}" ] && MISSING_ARGS+=("--data-dir")
[ -z "${GTF_FILE:-}" ] && MISSING_ARGS+=("--gtf")
[ -z "${GENOME_FA:-}" ] && MISSING_ARGS+=("--genome")
[ -z "${STAR_INDEX_DIR:-}" ] && MISSING_ARGS+=("--star-index")
[ -z "${OUTPUT_DIR:-}" ] && MISSING_ARGS+=("--output")

if [ ${#MISSING_ARGS[@]} -gt 0 ]; then
    echo "Error: Missing required argument(s): ${MISSING_ARGS[*]}" >&2
    echo "Usage: $0 --data-dir <dir> --gtf <file> --genome <file> --star-index <dir> --output <dir>" >&2
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

shopt -s nullglob
ALL_FASTQ_FILES=($DATA_DIR/*)
echo "Number of files found: ${#ALL_FASTQ_FILES[*]}"
echo "Found all these files: ${ALL_FASTQ_FILES[*]}"
TASK_ID=${SLURM_ARRAY_TASK_ID-0}
echo "Processing sample with ID: $TASK_ID"
FASTQ_FILE=${ALL_FASTQ_FILES[${TASK_ID}]}
echo "Processing sample file: $FASTQ_FILE"

# Create sample-specific output directory
SAMPLE_ID=$(basename "$FASTQ_FILE" .fastq.gz)
SAMPLE_OUTPUT_DIR="$OUTPUT_DIR/$SAMPLE_ID"
mkdir -p "$SAMPLE_OUTPUT_DIR"

# Run STAR alignment
STAR \
    --runThreadN "$SLURM_CPUS_ON_NODE" \
    --genomeDir "$STAR_INDEX_DIR" \
    --readFilesIn "$FASTQ_FILE" \
    --readFilesCommand zcat \
    --outFileNamePrefix "${SAMPLE_OUTPUT_DIR}/" \
    --outSAMtype BAM SortedByCoordinate \
    --outSAMunmapped Within \
    --outSAMattributes Standard \
    --quantMode GeneCounts \
    --twopassMode Basic

echo "STAR alignment completed for sample $SAMPLE_ID"