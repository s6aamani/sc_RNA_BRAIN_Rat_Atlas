#!/bin/bash

#SBATCH --job-name=cellranger_rat19
#SBATCH --partition=normal
#SBATCH -n 16
#SBATCH --mem-per-cpu=4000M
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CELLRANGER="${CELLRANGER_BIN:-${PROJECT_DIR}/opt/cellranger-10.0.0/cellranger}"
FASTQ_DIR="${FASTQ_DIR:-${PROJECT_DIR}/External/fastqs}"
TRANSCRIPTOME="${TRANSCRIPTOME:-${PROJECT_DIR}/External/rat_ref/mRatBN7.2}"
OUT_DIR="${OUT_DIR:-${PROJECT_DIR}/Analysis/cellranger}"
SAMPLE_ID="${SAMPLE_ID:-rat19}"
SAMPLE_NAMES="${SAMPLE_NAMES:-c-Li19-sal-sal,d-Li19-sal-sal}"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

echo "[$(date)] Running merged CellRanger count for ${SAMPLE_ID}..."
$CELLRANGER count \
    --id="${SAMPLE_ID}" \
    --transcriptome="$TRANSCRIPTOME" \
    --fastqs="$FASTQ_DIR" \
    --sample="$SAMPLE_NAMES" \
    --localcores=16 \
    --localmem=60 \
    --create-bam=false

echo "[$(date)] Done."
echo "Outputs:"
echo "  ${OUT_DIR}/${SAMPLE_ID}/outs/filtered_feature_bc_matrix"
echo "  ${OUT_DIR}/${SAMPLE_ID}/outs/filtered_feature_bc_matrix.h5"
