# Cross-Species Single-Cell Brain Atlas: Rat × Mouse

A comparative single-cell transcriptomic atlas project quantifying conservation
and divergence of cell types and gene-expression programs between rat and mouse
brain.

This repository currently implements the **rat-side processing pipeline**,
centered on sample `rat19` (10x Genomics single-nucleus RNA-seq, saline/saline
control). It covers:

- optional Cell Ranger reference construction
- Cell Ranger counting for merged technical replicates
- Seurat-based QC, clustering, PCA/UMAP diagnostics, and marker detection
- an interactive RStudio launcher for the cluster

Cross-species integration with mouse atlases is the next milestone and is
outlined under [Planned Downstream Atlas Work](#planned-downstream-atlas-work).

## Overview

This project is organized as a lightweight HPC-friendly workflow for:

1. building or reusing a rat Cell Ranger reference
2. running `cellranger count` on the rat19 FASTQs
3. running a parameterized Seurat workflow on the filtered matrix

The current dataset is:
- species: `Rattus norvegicus`
- assay: 10x Genomics single-nucleus RNA-seq
- sample: `rat19`
- technical replicates merged in Cell Ranger:
  `c-Li19-sal-sal`, `d-Li19-sal-sal`

## Repository Layout

```text
sc_RNA_BRAIN_Rat_Atlas/
├── Scripts/
│   ├── 00_build_rat_ref.sh      # Optional local Cell Ranger reference build
│   ├── 01_cellranger_rat19.sh   # Standalone Cell Ranger count
│   ├── 02_seurat_rat19.R        # Parameterized Seurat workflow
│   ├── 02_seurat_rat19.md       # Detailed documentation for step 3
│   ├── main.nf                  # Nextflow workflow
│   ├── nextflow.config          # Nextflow config for SLURM execution
│   ├── run_nextflow.sh          # SLURM launcher for Nextflow
│   └── rserver/                 # RStudio-on-SLURM helpers
│       ├── start_rstudio.sh         # Submit an rserver SLURM job
│       └── rebuild_native_pkgs.R    # One-time rocker-container package fix
├── Analysis/                    # Generated Cell Ranger and Nextflow outputs
├── Data/                        # Generated Seurat objects and downstream data
├── External/                    # Generated/local references
├── Results/                     # Generated plots, tables, reports
├── logs/                        # Generated runtime logs
└── opt/                         # Local tools, e.g. Cell Ranger binary
```

Generated outputs under `Analysis/`, `Data/`, `Results/`, `External/`, and
`logs/` are ignored by Git except for `.gitkeep` placeholders.

## Pipeline Steps

| Step | Script | Purpose | Main output |
|------|--------|---------|-------------|
| 1 | `Scripts/00_build_rat_ref.sh` | Download Ensembl mRatBN7.2 reference files and build a local Cell Ranger reference | `External/rat_ref/mRatBN7.2` |
| 2 | `Scripts/01_cellranger_rat19.sh` | Run `cellranger count` on merged technical replicates | `Analysis/cellranger/rat19/outs` |
| 3 | `Scripts/02_seurat_rat19.R` | Run QC, PCA, clustering, UMAP, and marker detection in Seurat | `Results/rat19/*`, `Data/rat19/rat19_seurat.rds` |

## Requirements

### Compute environment

- Linux HPC or workstation environment
- SLURM for the provided batch scripts
- enough local/shared storage for Cell Ranger outputs

### Software

- Cell Ranger 10.0.0
- Nextflow
- Java / OpenJDK
- R 4.4.x

### R packages

- `Seurat`
- `SeuratObject`
- `ggplot2`
- `dplyr`

## Data Inputs

The current scripts assume:

- FASTQ directory:
  `/masc_shared/ag_maj/dasmeh/P2024065NOS`
- prebuilt reference used by Nextflow:
  `/masc_shared/ag_maj/dasmeh/10X/Rat/Rattus_norvegicus_genome`

These paths are cluster-specific. If you move the repo to another environment,
update:
- `Scripts/01_cellranger_rat19.sh`
- `Scripts/nextflow.config`
- optionally `Scripts/00_build_rat_ref.sh`

## Running The Workflow

### Option 1: Nextflow on SLURM

```bash
cd Scripts
sbatch run_nextflow.sh
```

This is the preferred entry point when running on the configured cluster. The
launcher uses `-resume` so reruns pick up from previous successful work.

### Option 2: Run steps manually

Build a local reference if needed:

```bash
sbatch Scripts/00_build_rat_ref.sh
```

Run Cell Ranger:

```bash
sbatch Scripts/01_cellranger_rat19.sh
```

Run Seurat manually:

```bash
module load openjdk R-src/4.4.2
Rscript Scripts/02_seurat_rat19.R \
  --matrix_dir Analysis/cellranger/rat19/outs/filtered_feature_bc_matrix \
  --sample rat19 \
  --out_dir Results/rat19
```

Detailed Seurat argument documentation is in
[`Scripts/02_seurat_rat19.md`](Scripts/02_seurat_rat19.md).

## Environment Overrides

The scripts now support environment-variable overrides so the repo can be moved
between systems without editing hard-coded absolute paths.

Common overrides:
- `CELLRANGER_BIN`
- `FASTQ_DIR`
- `RAT_REF_DIR`
- `CELLRANGER_OUT_DIR`
- `SEURAT_RESULTS_DIR`
- `SEURAT_DATA_DIR`
- `NXF_WORK_DIR`
- `NXF_BIN`

Example:

```bash
export CELLRANGER_BIN=/path/to/cellranger
export FASTQ_DIR=/path/to/fastqs
export RAT_REF_DIR=/path/to/reference
cd Scripts
sbatch run_nextflow.sh
```

## Seurat Step Outputs

The upgraded Seurat script writes:

- QC summaries:
  `*_qc_summary.csv`, `*_qc_metadata.csv`
- QC plots:
  `*_qc_metrics.pdf`, `*_qc_scatter.pdf`
- PCA diagnostics:
  `*_pca_diagnostics.csv`, `*_elbow.pdf`
- clustering and embeddings:
  `*_umap.pdf`, `*_resolution_sweep_umap.pdf`, `*_cluster_sizes.csv`,
  `*_umap_embeddings.csv`
- markers and metadata:
  `*_markers_all.csv`, `*_markers_top10.csv`, `*_metadata.csv`
- processed object:
  `*_seurat.rds`

## Interactive RStudio

```bash
bash Scripts/rserver/start_rstudio.sh
```

The launcher writes instructions to `logs/rstudio-geo-server.<jobid>.out`.
Stop the session with:

```bash
scancel -f <jobid>
```

### R libraries: batch vs interactive

The launcher uses two R libraries:

- `~/R/x86_64-pc-linux-gnu-library/4.4/` — **batch jobs** (OpenHPC `R-src/4.4.2` module)
- `~/R/rocker-rstudio/4.4.3-geo/` — **interactive sessions** (rocker `4.4.3-geo` container)

Pure-R packages are auto-symlinked from the batch library into the rocker
library on each launch. Compiled packages must be installed natively in the
rocker library because the two R builds use different BLAS/LAPACK and dragging
`.so` files across them fails with `libRlapack.so: cannot open shared object
file`.

After your first rserver launch, run **once** inside R:

```r
source("Scripts/rserver/rebuild_native_pkgs.R")
```

This installs Seurat and its native dependencies against the container's
libopenblas. Future launches just work.

## GitHub Notes

This repository is set up to keep code and lightweight documentation in Git,
while ignoring:

- Cell Ranger outputs
- Nextflow working directories and runtime files
- logs and SLURM outputs
- local binaries and large data files
- editor- and machine-specific files

Before publishing, review cluster-specific absolute paths in the scripts and
decide whether they should remain as local defaults or be replaced with
project-level parameters.

## Current Scope And Limitations

The repo is currently a single-sample processing and first-pass exploration
workflow. It does not yet include:

- doublet detection
- ambient RNA correction
- batch correction or multi-sample integration
- cell type annotation
- cross-species rat-mouse integration
- formal downstream differential expression framework

## Planned Downstream Atlas Work

The original broader plan for this project is:

1. data preparation and ortholog mapping
2. cross-species integration
3. cell type annotation transfer
4. conservation vs divergence analysis
5. functional interpretation
6. visualization and atlas figures

Those steps are not implemented yet in this repository.
