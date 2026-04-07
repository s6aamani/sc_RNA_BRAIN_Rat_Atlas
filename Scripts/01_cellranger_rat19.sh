#!/bin/bash

#SBATCH --job-name=cellranger_rat19
#SBATCH --partition=normal
#SBATCH -n 16
#SBATCH --mem-per-cpu=4000M
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err

set -euo pipefail

CELLRANGER=/masc_shared/ag_maj/sc_RNA_BRAIN_Rat_Atlas/opt/cellranger-10.0.0/cellranger
FASTQ_DIR=/masc_shared/ag_maj/dasmeh/P2024065NOS
TRANSCRIPTOME=/masc_shared/ag_maj/sc_RNA_BRAIN_Rat_Atlas/External/rat_ref/mRatBN7.2
OUT_DIR=/masc_shared/ag_maj/sc_RNA_BRAIN_Rat_Atlas/Data/rat19

cd "$OUT_DIR"

echo "[$(date)] Running CellRanger count for c-Li19-sal-sal..."
$CELLRANGER count \
    --id=c-Li19-sal-sal \
    --transcriptome="$TRANSCRIPTOME" \
    --fastqs="$FASTQ_DIR" \
    --sample=c-Li19-sal-sal \
    --localcores=16 \
    --localmem=60 \
    --create-bam=false

echo "[$(date)] Running CellRanger count for d-Li19-sal-sal..."
$CELLRANGER count \
    --id=d-Li19-sal-sal \
    --transcriptome="$TRANSCRIPTOME" \
    --fastqs="$FASTQ_DIR" \
    --sample=d-Li19-sal-sal \
    --localcores=16 \
    --localmem=60 \
    --create-bam=false

echo "[$(date)] Done."
echo "Outputs:"
echo "  ${OUT_DIR}/c-Li19-sal-sal/outs/filtered_feature_bc_matrix.h5"
echo "  ${OUT_DIR}/d-Li19-sal-sal/outs/filtered_feature_bc_matrix.h5"
