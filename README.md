# Cross-Species Single-Cell Brain Atlas: Rat × Mouse

A large-scale comparative single-cell transcriptomic atlas quantifying conservation and divergence of cell types and gene expression programs between rat and mouse brain.

## Overview

Using preprocessed rat scRNA-seq data integrated with established mouse brain atlases, this project maps homologous cell populations, identifies species-specific transcriptional signatures, and evaluates the translational fidelity of rodent models.

## Project Structure

```
sc_RNA_BRAIN_Rat_Atlas/
├── Scripts/
│   ├── main.nf                  # Nextflow pipeline (3 steps)
│   ├── nextflow.config          # SLURM executor + resource config
│   ├── run_nextflow.sh          # Pipeline launcher (submit this)
│   ├── 00_build_rat_ref.sh      # Download mRatBN7.2 + cellranger mkref
│   ├── 01_cellranger_rat19.sh   # CellRanger count (standalone SLURM)
│   └── 02_seurat_rat19.R        # QC, clustering, marker detection
├── Data/                        # CellRanger outputs + Seurat objects (not tracked)
├── External/                    # Reference genomes (not tracked)
├── Results/                     # Figures and tables (not tracked)
├── Analysis/                    # Intermediate files (not tracked)
└── opt/                         # CellRanger 10.0.0 binary (not tracked)
```

## Analysis Pipeline

| Step | Script | Description |
|------|--------|-------------|
| 1 | `00_build_rat_ref.sh` | Download Ensembl mRatBN7.2 (release 112), filter GTF, run `cellranger mkref` |
| 2 | `01_cellranger_rat19.sh` | `cellranger count` — merges technical replicates via `--sample` list |
| 3 | `02_seurat_rat19.R` | QC filtering, normalization, PCA, UMAP, clustering, marker genes |

## Running the Pipeline

**Recommended — Nextflow (handles SLURM job chaining and resumability):**
```bash
cd Scripts/
sbatch run_nextflow.sh
```

Nextflow auto-installs if not present. Use `-resume` (already set) to restart from a failed step without rerunning completed ones.

**Manual — run steps individually:**
```bash
sbatch Scripts/00_build_rat_ref.sh          # ~2–3h, run once
sbatch Scripts/01_cellranger_rat19.sh       # ~3–5h, depends on step 1
Rscript Scripts/02_seurat_rat19.R \
  --h5 Data/rat19/rat19/outs/filtered_feature_bc_matrix.h5 \
  --sample rat19 --out_dir Results/rat19    # depends on step 2
```

## Data

**Rat:** 10x Genomics scRNA-seq, *Rattus norvegicus*, project P2024-065-NOS.
- Rat 19: 2 technical replicates (`c-Li19-sal-sal`, `d-Li19-sal-sal`), saline/saline control
- FASTQs: `/masc_shared/ag_maj/dasmeh/P2024065NOS/`
- Processed with CellRanger 10.0.0 against Ensembl mRatBN7.2 (release 112)

**Mouse reference atlas:** TBD — Allen Brain Cell Atlas / Zeisel et al. 2018

## Full Atlas Plan

| Step | Description |
|------|-------------|
| 1 | **Data Preparation** — ortholog mapping (rat ↔ mouse), shared gene space filtering |
| 2 | **Cross-Species Integration** — scVI/scANVI joint embedding |
| 3 | **Cell Type Annotation** — label transfer mouse → rat, mapping confidence |
| 4 | **Conservation vs Divergence** — DE within matched cell types, Jaccard index, correlation |
| 5 | **Functional Interpretation** — GO/KEGG pathway enrichment |
| 6 | **Visualization** — joint UMAP, heatmaps, dotplots, Sankey diagrams |

## Requirements

### R (≥ 4.4)
- Seurat, SeuratObject
- clusterProfiler
- ggplot2, dplyr, tidyr

### Python (≥ 3.9) — for cross-species integration
- scvi-tools, scanpy, anndata

### Other
- CellRanger 10.0.0 (`opt/cellranger-10.0.0/`)
- Nextflow ≥ 23 (auto-installed by `run_nextflow.sh`)
- SLURM cluster

## Citation

> *In preparation.*
