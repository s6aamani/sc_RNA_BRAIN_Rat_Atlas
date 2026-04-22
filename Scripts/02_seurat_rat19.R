library(Seurat)
library(ggplot2)
library(dplyr)

# -----------------------------------------------------------------------------
# Step 3 Seurat workflow for rat19 snRNA-seq
#
# This script takes the filtered Cell Ranger matrix from step 2 and performs:
# 1. object creation and metadata annotation
# 2. QC metric calculation and threshold diagnostics
# 3. QC filtering
# 4. normalization, variable feature selection, and scaling
# 5. PCA, neighbor graph construction, clustering, and UMAP
# 6. marker detection and export of analysis artifacts
#
# The script is intentionally parameterized through CLI flags so QC thresholds,
# PC usage, and clustering resolution can be changed without editing code.
#
# Typical invocation:
# Rscript Scripts/02_seurat_rat19.R \
#   --matrix_dir Analysis/cellranger/rat19/outs/filtered_feature_bc_matrix \
#   --sample rat19 \
#   --out_dir Results/rat19 \
#   --min_features 300 \
#   --max_features 7000 \
#   --max_mt 10 \
#   --dims_use 1:25 \
#   --resolution 0.6 \
#   --resolution_sweep 0.2,0.4,0.6,0.8,1.0
# -----------------------------------------------------------------------------

# ── CLI helpers ───────────────────────────────────────────────────────────────
args <- commandArgs(trailingOnly = TRUE)

parse_arg <- function(flag, default = NULL) {
  idx <- which(args == flag)
  if (length(idx) && idx < length(args)) args[idx + 1] else default
}

parse_int_arg <- function(flag, default) {
  value <- parse_arg(flag, default = as.character(default))
  value <- suppressWarnings(as.integer(value))
  if (is.na(value)) stop(flag, " must be an integer")
  value
}

parse_num_arg <- function(flag, default) {
  value <- parse_arg(flag, default = as.character(default))
  value <- suppressWarnings(as.numeric(value))
  if (is.na(value)) stop(flag, " must be numeric")
  value
}

parse_dims_arg <- function(flag, default = "1:30") {
  value <- parse_arg(flag, default = default)
  value <- gsub("\\s+", "", value)
  if (grepl("^[0-9]+:[0-9]+$", value)) {
    bounds <- as.integer(strsplit(value, ":", fixed = TRUE)[[1]])
    if (bounds[1] > bounds[2]) stop(flag, " must be ascending")
    return(seq.int(bounds[1], bounds[2]))
  }

  dims <- suppressWarnings(as.integer(strsplit(value, ",", fixed = TRUE)[[1]]))
  if (any(is.na(dims))) stop(flag, " must be a range like 1:30 or a comma list")
  unique(dims)
}

parse_resolutions_arg <- function(flag, default = "0.2,0.4,0.6,0.8,1.0") {
  value <- parse_arg(flag, default = default)
  resolutions <- suppressWarnings(as.numeric(strsplit(gsub("\\s+", "", value), ",", fixed = TRUE)[[1]]))
  if (any(is.na(resolutions))) stop(flag, " must be a comma-separated numeric list")
  unique(resolutions)
}

make_cluster_col <- function(resolution) {
  paste0("RNA_snn_res.", format(resolution, trim = TRUE, scientific = FALSE))
}

label_cluster_plot <- function(df, cluster_col) {
  centers <- aggregate(cbind(umap_1, umap_2) ~ cluster, data = df, FUN = median)

  ggplot(df, aes(x = umap_1, y = umap_2, color = cluster)) +
    geom_point(size = 0.2, alpha = 0.8) +
    geom_text(
      data = centers,
      aes(x = umap_1, y = umap_2, label = cluster),
      inherit.aes = FALSE,
      color = "black",
      fontface = "bold",
      size = 3
    ) +
    labs(title = cluster_col, color = "Cluster") +
    theme_classic()
}

# ── Parameters ────────────────────────────────────────────────────────────────
# These flags control the main biological and computational decisions:
# - QC retention thresholds for nuclei
# - number of variable genes
# - number of PCs to compute and use
# - default clustering resolution and comparison grid
# - marker stringency thresholds
matrix_dir <- parse_arg("--matrix_dir", default = "Analysis/cellranger/rat19/outs/filtered_feature_bc_matrix")
sample_id  <- parse_arg("--sample", default = "rat19")
out_dir    <- parse_arg("--out_dir", default = ".")
treatment  <- parse_arg("--treatment", default = "sal-sal")
rat_id     <- parse_arg("--rat_id", default = sample_id)
min_cells <- parse_int_arg("--min_cells", default = 3)
initial_min_features <- parse_int_arg("--initial_min_features", default = 200)
min_features <- parse_int_arg("--min_features", default = 200)
max_features <- parse_int_arg("--max_features", default = 6000)
max_mt <- parse_num_arg("--max_mt", default = 20)
n_variable_features <- parse_int_arg("--n_variable_features", default = 3000)
n_pcs_compute <- parse_int_arg("--n_pcs_compute", default = 50)
dims_use <- parse_dims_arg("--dims_use", default = "1:30")
default_resolution <- parse_num_arg("--resolution", default = 0.5)
resolution_sweep <- parse_resolutions_arg("--resolution_sweep", default = "0.2,0.4,0.6,0.8,1.0")
marker_min_pct <- parse_num_arg("--marker_min_pct", default = 0.25)
marker_logfc_threshold <- parse_num_arg("--marker_logfc_threshold", default = 0.5)
seed <- parse_int_arg("--seed", default = 1234)

if (is.null(matrix_dir)) stop("--matrix_dir is required")
if (min_features >= max_features) stop("--min_features must be smaller than --max_features")
if (max_mt < 0) stop("--max_mt must be non-negative")
if (max(dims_use) > n_pcs_compute) stop("--dims_use cannot exceed --n_pcs_compute")

resolution_sweep <- sort(unique(c(resolution_sweep, default_resolution)))
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
set.seed(seed)

# ── Load counts and annotate ──────────────────────────────────────────────────
# Technical replicates are already merged by CellRanger (--sample list).
counts <- Read10X(data.dir = matrix_dir)
rat_obj <- CreateSeuratObject(
  counts = counts,
  project = sample_id,
  min.cells = min_cells,
  min.features = initial_min_features
)
rat_obj$sample <- sample_id
rat_obj$treatment <- treatment
rat_obj$rat <- rat_id

# ── QC metrics and diagnostics ────────────────────────────────────────────────
# QC is calculated before filtering so the user can inspect the full nucleus
# distribution and see which barcodes would pass the chosen thresholds.
rat_obj[["percent.mt"]] <- PercentageFeatureSet(rat_obj, pattern = "^Mt-")
qc_features <- c("nFeature_RNA", "nCount_RNA", "percent.mt")
qc_data <- rat_obj[[]][, qc_features, drop = FALSE]
qc_data$barcode <- rownames(qc_data)
qc_data$pass_qc <- with(
  qc_data,
  nFeature_RNA > min_features &
    nFeature_RNA < max_features &
    percent.mt < max_mt
)
qc_data$high_feature_outlier <- qc_data$nFeature_RNA > (median(qc_data$nFeature_RNA) + 3 * mad(qc_data$nFeature_RNA))

write.csv(
  qc_data,
  file.path(out_dir, paste0(sample_id, "_qc_metadata.csv")),
  row.names = FALSE
)

qc_summary <- data.frame(
  sample = sample_id,
  initial_cells = nrow(qc_data),
  pass_qc_cells = sum(qc_data$pass_qc),
  filtered_cells = sum(!qc_data$pass_qc),
  min_features = min_features,
  max_features = max_features,
  max_mt = max_mt,
  initial_min_features = initial_min_features,
  median_features = median(qc_data$nFeature_RNA),
  median_counts = median(qc_data$nCount_RNA),
  median_percent_mt = median(qc_data$percent.mt),
  high_feature_outliers = sum(qc_data$high_feature_outlier)
)
write.csv(
  qc_summary,
  file.path(out_dir, paste0(sample_id, "_qc_summary.csv")),
  row.names = FALSE
)

pdf(file.path(out_dir, paste0(sample_id, "_qc_metrics.pdf")), width = 11, height = 5)
for (feat in qc_features) {
  plot_df <- data.frame(sample = sample_id, value = qc_data[[feat]], pass_qc = qc_data$pass_qc)
  qc_plot <- ggplot(plot_df, aes(x = sample, y = value, fill = pass_qc)) +
    geom_violin(color = NA, scale = "width", trim = TRUE) +
    geom_boxplot(width = 0.15, outlier.shape = NA, fill = "white") +
    scale_fill_manual(values = c("TRUE" = "#4C78A8", "FALSE" = "#E45756")) +
    labs(title = paste(sample_id, feat), x = NULL, y = feat, fill = "Pass QC") +
    theme_bw() +
    theme(plot.title = element_text(hjust = 0.5))
  print(qc_plot)
}
dev.off()

pdf(file.path(out_dir, paste0(sample_id, "_qc_scatter.pdf")), width = 12, height = 5)
print(
  ggplot(qc_data, aes(x = nCount_RNA, y = nFeature_RNA, color = pass_qc)) +
    geom_point(size = 0.25, alpha = 0.5) +
    scale_color_manual(values = c("TRUE" = "#4C78A8", "FALSE" = "#E45756")) +
    labs(
      title = paste(sample_id, "nCount_RNA vs nFeature_RNA"),
      x = "nCount_RNA",
      y = "nFeature_RNA",
      color = "Pass QC"
    ) +
    theme_classic()
)
print(
  ggplot(qc_data, aes(x = nCount_RNA, y = percent.mt, color = pass_qc)) +
    geom_point(size = 0.25, alpha = 0.5) +
    scale_color_manual(values = c("TRUE" = "#4C78A8", "FALSE" = "#E45756")) +
    geom_hline(yintercept = max_mt, linetype = "dashed", color = "grey40") +
    labs(
      title = paste(sample_id, "nCount_RNA vs percent.mt"),
      x = "nCount_RNA",
      y = "percent.mt",
      color = "Pass QC"
    ) +
    theme_classic()
)
dev.off()

# ── Filter nuclei ─────────────────────────────────────────────────────────────
# Filtering is intentionally simple and transparent here. The script records
# the pass/fail status in *_qc_metadata.csv so thresholds can be revisited.
rat_obj <- subset(
  rat_obj,
  subset = nFeature_RNA > min_features &
    nFeature_RNA < max_features &
    percent.mt < max_mt
)

# ── Normalize and select informative genes ───────────────────────────────────
# NormalizeData adjusts for library size, FindVariableFeatures limits the
# analysis to the most informative genes, and ScaleData standardizes expression.
rat_obj <- NormalizeData(rat_obj, verbose = FALSE)
rat_obj <- FindVariableFeatures(rat_obj, nfeatures = n_variable_features, verbose = FALSE)
rat_obj <- ScaleData(rat_obj, verbose = FALSE)

# ── PCA, graph construction, clustering, and UMAP ────────────────────────────
# Clustering is run over a resolution sweep first so the same neighborhood graph
# can be compared at multiple granularities. The chosen --resolution becomes the
# active identity class used for the default UMAP and marker calling.
rat_obj <- RunPCA(rat_obj, npcs = n_pcs_compute, verbose = FALSE, seed.use = seed)
rat_obj <- FindNeighbors(rat_obj, dims = dims_use, verbose = FALSE)

for (resolution in resolution_sweep) {
  rat_obj <- FindClusters(rat_obj, resolution = resolution, verbose = FALSE)
}

default_cluster_col <- make_cluster_col(default_resolution)
Idents(rat_obj) <- default_cluster_col
rat_obj <- RunUMAP(rat_obj, dims = dims_use, verbose = FALSE, seed.use = seed)

# ── PCA diagnostics ───────────────────────────────────────────────────────────
# The elbow plot and accompanying table make the dims_use decision explicit.
pca_stdev <- rat_obj[["pca"]]@stdev
pca_diag <- data.frame(
  pc = seq_along(pca_stdev),
  stdev = pca_stdev,
  variance = pca_stdev^2,
  pct_variance = (pca_stdev^2) / sum(pca_stdev^2) * 100,
  cumulative_pct_variance = cumsum((pca_stdev^2) / sum(pca_stdev^2) * 100)
)
write.csv(
  pca_diag,
  file.path(out_dir, paste0(sample_id, "_pca_diagnostics.csv")),
  row.names = FALSE
)

pdf(file.path(out_dir, paste0(sample_id, "_elbow.pdf")), width = 7, height = 5)
print(
  ggplot(pca_diag, aes(x = pc, y = pct_variance)) +
    geom_line(color = "#4C78A8") +
    geom_point(color = "#4C78A8", size = 1.2) +
    geom_vline(xintercept = max(dims_use), linetype = "dashed", color = "#E45756") +
    labs(
      title = paste(sample_id, "PCA elbow"),
      x = "Principal component",
      y = "Percent variance explained"
    ) +
    theme_classic()
)
dev.off()

# ── UMAP outputs ──────────────────────────────────────────────────────────────
# The default UMAP uses the active clustering resolution. A separate PDF saves
# the same embedding colored by every requested resolution in the sweep.
umap_df <- as.data.frame(Embeddings(rat_obj, reduction = "umap"))
colnames(umap_df)[1:2] <- c("umap_1", "umap_2")
umap_df$barcode <- rownames(umap_df)
umap_df$seurat_clusters <- as.character(Idents(rat_obj))
write.csv(
  umap_df,
  file.path(out_dir, paste0(sample_id, "_umap_embeddings.csv")),
  row.names = FALSE
)

default_plot_df <- umap_df
default_plot_df$cluster <- default_plot_df$seurat_clusters

pdf(file.path(out_dir, paste0(sample_id, "_umap.pdf")), width = 7, height = 6)
print(label_cluster_plot(default_plot_df, default_cluster_col) +
  labs(title = paste(sample_id, "clusters")))
dev.off()

pdf(file.path(out_dir, paste0(sample_id, "_resolution_sweep_umap.pdf")), width = 14, height = 8)
for (resolution in resolution_sweep) {
  cluster_col <- make_cluster_col(resolution)
  sweep_df <- umap_df
  sweep_df$cluster <- as.character(rat_obj[[cluster_col, drop = TRUE]])
  print(label_cluster_plot(sweep_df, cluster_col))
}
dev.off()

cluster_sizes <- do.call(
  rbind,
  lapply(resolution_sweep, function(resolution) {
    cluster_col <- make_cluster_col(resolution)
    counts_tbl <- as.data.frame(table(rat_obj[[cluster_col, drop = TRUE]]), stringsAsFactors = FALSE)
    colnames(counts_tbl) <- c("cluster", "n_cells")
    counts_tbl$resolution <- resolution
    counts_tbl
  })
)
write.csv(
  cluster_sizes,
  file.path(out_dir, paste0(sample_id, "_cluster_sizes.csv")),
  row.names = FALSE
)

# ── Marker genes ──────────────────────────────────────────────────────────────
# Marker calling is performed on the active identity class only. Both the full
# marker table and a top-10 per-cluster summary are written for inspection.
markers <- FindAllMarkers(
  rat_obj,
  only.pos = TRUE,
  min.pct = marker_min_pct,
  logfc.threshold = marker_logfc_threshold,
  verbose = FALSE
)

write.csv(
  markers,
  file.path(out_dir, paste0(sample_id, "_markers_all.csv")),
  row.names = FALSE
)

if (nrow(markers) > 0) {
  top10 <- markers |>
    group_by(cluster) |>
    slice_max(order_by = avg_log2FC, n = 10, with_ties = FALSE) |>
    ungroup()
} else {
  top10 <- markers
}

write.csv(
  top10,
  file.path(out_dir, paste0(sample_id, "_markers_top10.csv")),
  row.names = FALSE
)

# ── Persist object and metadata ───────────────────────────────────────────────
# Save both the Seurat object and flat tables so downstream users can inspect
# results without loading the RDS immediately.
metadata <- rat_obj[[]]
metadata$barcode <- rownames(metadata)
write.csv(
  metadata,
  file.path(out_dir, paste0(sample_id, "_metadata.csv")),
  row.names = FALSE
)

saveRDS(rat_obj, file.path(out_dir, paste0(sample_id, "_seurat.rds")))

cat("Done.\n")
cat("Cells before QC:", qc_summary$initial_cells, "\n")
cat("Cells after QC:", ncol(rat_obj), "\n")
cat("Default clustering resolution:", default_resolution, "\n")
cat("Clusters:", nlevels(Idents(rat_obj)), "\n")
cat("PCs used:", paste(dims_use, collapse = ","), "\n")
