# `02_seurat_rat19.R` Documentation

This document describes the upgraded Seurat workflow in
[`02_seurat_rat19.R`](02_seurat_rat19.R).
It explains what the script does, how each parameter affects the result, and
which output files are written.

## Purpose

This script is the third analysis step in the repo:

1. build or provide a Cell Ranger reference
2. run Cell Ranger on the rat19 FASTQs
3. run Seurat on the filtered feature-barcode matrix

Input:
- `Analysis/cellranger/rat19/outs/filtered_feature_bc_matrix`

Main outputs:
- QC plots and QC summary tables
- PCA diagnostics
- UMAPs for the selected clustering and a resolution sweep
- marker gene tables
- processed Seurat object

## Workflow Overview

The script performs the following stages.

### 1. Parse CLI arguments

The script uses command-line flags rather than hard-coded thresholds so you can
change QC and clustering decisions without editing the file.

### 2. Load the matrix and create a Seurat object

It reads the Cell Ranger matrix with `Read10X()` and then creates a Seurat
object with `CreateSeuratObject()`.

Important distinction:
- `--initial_min_features` affects the very first object creation step
- `--min_features`, `--max_features`, and `--max_mt` define the explicit QC
  filter applied later

This keeps the early object permissive and makes the real QC step explicit.

### 3. Compute QC metrics

The script calculates:
- `nFeature_RNA`
- `nCount_RNA`
- `percent.mt`

It then labels each nucleus as pass/fail based on your chosen thresholds and
flags high-feature outliers using `median + 3 * MAD` as a crude doublet proxy.

### 4. Write QC plots and QC tables

Before filtering, the script exports:
- violin plots for `nFeature_RNA`, `nCount_RNA`, and `percent.mt`
- scatter plots of `nCount_RNA` vs `nFeature_RNA` and `nCount_RNA` vs
  `percent.mt`
- per-barcode QC metadata
- one-row QC summary statistics

This is the part you use to judge whether your thresholds are sensible.

### 5. Filter nuclei

The filter is:

```r
nFeature_RNA > min_features &
nFeature_RNA < max_features &
percent.mt < max_mt
```

This is intentionally simple and transparent.

### 6. Normalize and choose variable features

The script then runs:
- `NormalizeData()`
- `FindVariableFeatures()`
- `ScaleData()`

These steps prepare the expression matrix for PCA and graph-based clustering.

### 7. Run PCA, neighbors, clustering, and UMAP

The script:
- computes `--n_pcs_compute` principal components
- uses `--dims_use` when building the neighbor graph
- runs clustering over every value in `--resolution_sweep`
- sets `--resolution` as the active identity class
- runs UMAP once using the selected PCs

Because clustering is done across a resolution grid, you can compare multiple
granularities from the same run.

### 8. Save PCA diagnostics and cluster visualizations

The script writes:
- an elbow plot
- a per-PC variance table
- a default UMAP using the active clustering
- a multi-page UMAP PDF showing the full resolution sweep
- cluster size tables

### 9. Call markers and save outputs

The script runs `FindAllMarkers()` on the active clustering only. It saves:
- the full marker table
- a top-10-per-cluster marker summary
- metadata table
- UMAP coordinates
- full Seurat object as `.rds`

## Parameters

### Required in practice

- `--matrix_dir`
  Path to the Cell Ranger MEX directory.
- `--sample`
  Sample name used in output filenames and metadata.
- `--out_dir`
  Output directory for plots, tables, and the RDS.

### Metadata flags

- `--treatment`
  Stored in `rat_obj$treatment`.
- `--rat_id`
  Stored in `rat_obj$rat`.

These are not computational parameters, but they are useful for downstream
integration and metadata tracking.

### QC thresholds

- `--min_cells`
  Passed to `CreateSeuratObject()`. A gene must appear in at least this many
  nuclei to be kept.
  Default: `3`

- `--initial_min_features`
  Passed to `CreateSeuratObject()`. A barcode must have at least this many
  detected genes to be kept in the initial object.
  Default: `200`

- `--min_features`
  Lower QC threshold applied later with `subset()`.
  Default: `200`

- `--max_features`
  Upper QC threshold applied later with `subset()`.
  Default: `6000`

- `--max_mt`
  Maximum mitochondrial percentage.
  Default: `20`

How to choose them for snRNA-seq brain data:
- start by inspecting `*_qc_metrics.pdf` and `*_qc_scatter.pdf`
- set `--min_features` above the low-feature debris tail
- set `--max_features` below the obvious high-feature/high-count outlier tail
- treat `--max_mt` as a permissive sanity filter rather than the main QC gate

For nuclei, high intronic content is expected and mito usually matters less
than in whole-cell scRNA-seq.

### Feature selection and PCA

- `--n_variable_features`
  Number of highly variable genes to retain.
  Default: `3000`

- `--n_pcs_compute`
  Total number of PCs to compute.
  Default: `50`

- `--dims_use`
  PCs used in neighbor graph construction and UMAP. Accepts either a range like
  `1:30` or a comma list like `1,2,3,4,5,6,7,8,9,10`.
  Default: `1:30`

How to choose:
- inspect `*_elbow.pdf`
- choose a PC range that captures signal before the variance curve flattens
- for a first pass, `20` to `30` PCs is often reasonable for brain nuclei data

### Clustering

- `--resolution`
  The clustering resolution used as the active identity class.
  Default: `0.5`

- `--resolution_sweep`
  Comma-separated list of resolutions to compare.
  Default: `0.2,0.4,0.6,0.8,1.0`

How to choose:
- lower resolution merges clusters more aggressively
- higher resolution splits clusters more aggressively
- use `*_resolution_sweep_umap.pdf` and `*_cluster_sizes.csv` to judge whether
  added clusters are stable and biologically plausible

Recommended workflow:
- inspect `0.2` to `1.0`
- avoid choosing a resolution only because it “looks detailed”
- prefer marker-supported and stable clusters over maximal splitting

### Marker calling

- `--marker_min_pct`
  Minimum fraction of nuclei expressing a gene to consider it a marker.
  Default: `0.25`

- `--marker_logfc_threshold`
  Minimum log fold-change for marker reporting.
  Default: `0.5`

How to choose:
- lower values return more candidate markers, including weaker ones
- higher values return stricter marker lists
- use lower thresholds if clusters are subtle and you need more discovery
- use higher thresholds if you want cleaner marker panels

### Reproducibility

- `--seed`
  Random seed used for PCA and UMAP.
  Default: `1234`

This makes reruns more stable.

## Output Files

The script writes the following outputs under `--out_dir`.

### QC outputs

- `*_qc_summary.csv`
  One-row summary with counts before/after QC and threshold values.

- `*_qc_metadata.csv`
  Per-barcode QC table including `pass_qc` and `high_feature_outlier`.

- `*_qc_metrics.pdf`
  Violin plots for `nFeature_RNA`, `nCount_RNA`, and `percent.mt`.

- `*_qc_scatter.pdf`
  Scatter plots used to inspect QC cutoffs.

### PCA and clustering outputs

- `*_pca_diagnostics.csv`
  Per-PC standard deviation and explained variance.

- `*_elbow.pdf`
  Elbow plot with a vertical line marking the maximum PC in `--dims_use`.

- `*_umap.pdf`
  Default UMAP colored by the active clustering resolution.

- `*_resolution_sweep_umap.pdf`
  Multi-page PDF with one UMAP per resolution in the sweep.

- `*_cluster_sizes.csv`
  Number of nuclei in each cluster for each tested resolution.

- `*_umap_embeddings.csv`
  UMAP coordinates for each nucleus.

### Marker and metadata outputs

- `*_markers_all.csv`
  Full marker table from `FindAllMarkers()`.

- `*_markers_top10.csv`
  Top 10 markers per cluster by `avg_log2FC`.

- `*_metadata.csv`
  Seurat metadata table after QC and clustering.

- `*_seurat.rds`
  Full processed Seurat object.

## Example Commands

### Conservative first pass

```bash
Rscript Scripts/02_seurat_rat19.R \
  --matrix_dir Analysis/cellranger/rat19/outs/filtered_feature_bc_matrix \
  --sample rat19 \
  --out_dir Results/rat19 \
  --min_features 300 \
  --max_features 7000 \
  --max_mt 10 \
  --dims_use 1:25 \
  --resolution 0.6 \
  --resolution_sweep 0.2,0.4,0.6,0.8,1.0
```

### More permissive clustering exploration

```bash
Rscript Scripts/02_seurat_rat19.R \
  --matrix_dir Analysis/cellranger/rat19/outs/filtered_feature_bc_matrix \
  --sample rat19 \
  --out_dir Results/rat19_explore \
  --min_features 200 \
  --max_features 8000 \
  --max_mt 15 \
  --dims_use 1:30 \
  --resolution 0.8 \
  --resolution_sweep 0.2,0.4,0.6,0.8,1.0,1.2
```

## Practical Notes for This Repo

- The current dataset is rat brain single-nucleus data, not whole-cell scRNA.
- Because of that, lower transcript complexity and intronic-heavy upstream
  mapping are expected.
- Do not over-interpret mito thresholds as the main QC criterion.
- The script still uses a simple QC model. It does not perform ambient RNA
  correction, explicit doublet detection, batch correction, or annotation.

## Current Limitations

This script is better than the original version, but it is still a pragmatic
single-sample workflow.

It does not yet include:
- doublet detection
- batch integration
- cell type annotation
- ambient RNA correction
- pseudobulk DE or replicate-aware statistics

Those would belong in later workflow steps or in a more atlas-focused script.
