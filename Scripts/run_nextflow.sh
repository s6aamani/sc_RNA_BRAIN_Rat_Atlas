#!/bin/bash

#SBATCH --job-name=nf_rat19
#SBATCH --partition=normal
#SBATCH -n 2
#SBATCH --mem-per-cpu=4000M
#SBATCH --output=%x.%j.out
#SBATCH --error=%x.%j.err

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXF_BIN="$SCRIPTS_DIR/../opt/nextflow"

# ── Install Nextflow if not present ──────────────────────────────────────────
if [ ! -f "$NXF_BIN" ]; then
    echo "Nextflow not found — installing..."
    curl -fsSL https://get.nextflow.io | bash
    mv nextflow "$NXF_BIN"
    chmod +x "$NXF_BIN"
fi

echo "Nextflow version: $($NXF_BIN -version)"

# ── Run pipeline ──────────────────────────────────────────────────────────────
$NXF_BIN run "$SCRIPTS_DIR/main.nf" \
    -c "$SCRIPTS_DIR/nextflow.config" \
    -with-report \
    -with-timeline \
    -resume

echo "Pipeline complete."
