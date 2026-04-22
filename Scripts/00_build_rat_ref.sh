#!/bin/bash

#SBATCH --job-name=rat_mkref
#SBATCH --partition=normal
#SBATCH -n 8
#SBATCH --mem-per-cpu=8000M
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CELLRANGER="${CELLRANGER_BIN:-${PROJECT_DIR}/opt/cellranger-10.0.0/cellranger}"
REF_DIR="${REF_DIR:-${PROJECT_DIR}/External/rat_ref}"
ENSEMBL_RELEASE="${ENSEMBL_RELEASE:-112}"

mkdir -p "$REF_DIR"

cd "$REF_DIR"

echo "[$(date)] Downloading mRatBN7.2 FASTA..."
wget -q "https://ftp.ensembl.org/pub/release-${ENSEMBL_RELEASE}/fasta/rattus_norvegicus/dna/Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa.gz"
gunzip Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa.gz

echo "[$(date)] Downloading GTF..."
wget -q "https://ftp.ensembl.org/pub/release-${ENSEMBL_RELEASE}/gtf/rattus_norvegicus/Rattus_norvegicus.mRatBN7.2.${ENSEMBL_RELEASE}.gtf.gz"
gunzip Rattus_norvegicus.mRatBN7.2.${ENSEMBL_RELEASE}.gtf.gz

echo "[$(date)] Filtering GTF..."
$CELLRANGER mkgtf \
    Rattus_norvegicus.mRatBN7.2.${ENSEMBL_RELEASE}.gtf \
    Rattus_norvegicus.mRatBN7.2.${ENSEMBL_RELEASE}.filtered.gtf \
    --attribute=gene_biotype:protein_coding \
    --attribute=gene_biotype:lncRNA

echo "[$(date)] Building CellRanger reference..."
$CELLRANGER mkref \
    --genome=mRatBN7.2 \
    --fasta=Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa \
    --genes=Rattus_norvegicus.mRatBN7.2.${ENSEMBL_RELEASE}.filtered.gtf \
    --nthreads=8 \
    --memgb=60

echo "[$(date)] Done. Reference at: ${REF_DIR}/mRatBN7.2"
