#!/bin/bash

#SBATCH --job-name=nf_rat19
#SBATCH --partition=normal
#SBATCH -n 2
#SBATCH --mem-per-cpu=4000M
#SBATCH --time=24:00:00
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

module load openjdk

SCRIPTS_DIR="${SCRIPTS_DIR:-${SCRIPT_DIR}}"
NXF_BIN="${NXF_BIN:-}"

if [[ -z "${NXF_BIN}" ]]; then
  if [[ -x "${SCRIPTS_DIR}/nextflow" ]]; then
    NXF_BIN="${SCRIPTS_DIR}/nextflow"
  else
    NXF_BIN="$(command -v nextflow || true)"
  fi
fi

if [[ -z "${NXF_BIN}" ]]; then
  echo "ERROR: nextflow not found. Set NXF_BIN or place nextflow on PATH." >&2
  exit 1
fi

echo "Nextflow version: $($NXF_BIN -version)"

# ── Run pipeline ──────────────────────────────────────────────────────────────
$NXF_BIN run "$SCRIPTS_DIR/main.nf" \
    -c "$SCRIPTS_DIR/nextflow.config" \
    -resume

echo "Pipeline complete."
