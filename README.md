# Cross-Species Single-Cell Brain Atlas: Rat × Mouse

A large-scale comparative single-cell transcriptomic atlas quantifying conservation and divergence of cell types and gene expression programs between rat and mouse brain.

## Overview

Using preprocessed rat scRNA-seq data integrated with established mouse brain atlases, this project maps homologous cell populations, identifies species-specific transcriptional signatures, and evaluates the translational fidelity of rodent models.

## Analysis Pipeline

| Step | Description |
|------|-------------|
| 1 | **Data Preparation** — ortholog mapping (rat ↔ mouse), shared gene space filtering |
| 2 | **Cross-Species Integration** — scVI/scANVI joint embedding |
| 3 | **Cell Type Annotation** — label transfer mouse → rat, mapping confidence |
| 4 | **Conservation vs Divergence** — DE within matched cell types, Jaccard index, correlation |
| 5 | **Functional Interpretation** — GO/KEGG pathway enrichment |
| 6 | **Visualization** — joint UMAP, heatmaps, dotplots, Sankey diagrams |

## Directory Structure

```
sc_RNA_BRAIN_Rat_Atlas/
├── Data/          # Raw and processed count matrices (not tracked by git)
├── External/      # Reference mouse atlas, ortholog tables (not tracked by git)
├── Scripts/       # Analysis scripts (R and Python)
├── Analysis/      # Intermediate analysis outputs (not tracked by git)
└── Results/       # Figures and final outputs (not tracked by git)
```

## Data

**Rat:** 10x Genomics scRNA-seq, *Rattus norvegicus*, 32 samples (P2024-065-NOS).  
Treatment groups: saline, amphetamine, lithium.  
Processed with CellRanger 7.1.0 against the *Rattus norvegicus* reference genome.

**Mouse:** Reference atlas (TBD — Allen Brain Cell Atlas / Zeisel et al. 2018).

## Requirements

### R (≥ 4.4)
- Seurat
- clusterProfiler
- ggplot2, dplyr, tidyr

### Python (≥ 3.9)
- scvi-tools
- scanpy
- anndata

## Usage

Scripts are numbered in execution order under `Scripts/`. See individual script headers for dependencies and inputs.

## Citation

> *In preparation.*
