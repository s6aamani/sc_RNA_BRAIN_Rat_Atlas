library(Seurat)
library(ggplot2)
library(dplyr)

# ── CLI arguments ─────────────────────────────────────────────────────────────
args <- commandArgs(trailingOnly = TRUE)
parse_arg <- function(flag, default = NULL) {
  idx <- which(args == flag)
  if (length(idx) && idx < length(args)) args[idx + 1] else default
}

h5_path   <- parse_arg("--h5")
sample_id <- parse_arg("--sample", default = "rat19")
out_dir   <- parse_arg("--out_dir", default = ".")

if (is.null(h5_path)) stop("--h5 is required")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ── Load count matrix ─────────────────────────────────────────────────────────
# Technical replicates already merged by CellRanger (--sample list)
counts <- Read10X_h5(h5_path)
rat19  <- CreateSeuratObject(counts = counts, project = sample_id,
                             min.cells = 3, min.features = 200)
rat19$sample    <- sample_id
rat19$treatment <- "sal-sal"
rat19$rat       <- "rat19"

# ── QC metrics ────────────────────────────────────────────────────────────────
rat19[["percent.mt"]] <- PercentageFeatureSet(rat19, pattern = "^Mt-")

pdf(file.path(out_dir, paste0(sample_id, "_qc_metrics.pdf")), width = 10, height = 5)
print(VlnPlot(rat19,
              features = c("nFeature_RNA", "nCount_RNA", "percent.mt"),
              ncol = 3, pt.size = 0))
dev.off()

# ── Filter cells ──────────────────────────────────────────────────────────────
rat19 <- subset(rat19,
                nFeature_RNA > 200 &
                nFeature_RNA < 6000 &
                percent.mt   < 20)

# ── Normalize + variable features ────────────────────────────────────────────
rat19 <- NormalizeData(rat19)
rat19 <- FindVariableFeatures(rat19, nfeatures = 3000)
rat19 <- ScaleData(rat19)

# ── PCA + UMAP + clustering ───────────────────────────────────────────────────
rat19 <- RunPCA(rat19, npcs = 50)
rat19 <- FindNeighbors(rat19, dims = 1:30)
rat19 <- FindClusters(rat19, resolution = 0.5)
rat19 <- RunUMAP(rat19, dims = 1:30)

# ── UMAP plot ─────────────────────────────────────────────────────────────────
pdf(file.path(out_dir, paste0(sample_id, "_umap.pdf")), width = 7, height = 6)
print(DimPlot(rat19, reduction = "umap", group.by = "seurat_clusters", label = TRUE) +
      ggtitle(paste(sample_id, "— clusters")))
dev.off()

# ── Marker genes ──────────────────────────────────────────────────────────────
markers <- FindAllMarkers(rat19,
                          only.pos        = TRUE,
                          min.pct         = 0.25,
                          logfc.threshold = 0.5)

top10 <- markers |>
  group_by(cluster) |>
  slice_max(order_by = avg_log2FC, n = 10)

write.csv(top10, file.path(out_dir, paste0(sample_id, "_markers_top10.csv")),
          row.names = FALSE)

# ── Save Seurat object ────────────────────────────────────────────────────────
saveRDS(rat19, file.path(out_dir, paste0(sample_id, "_seurat.rds")))

cat("Done.\n")
cat("Cells after QC:", ncol(rat19), "\n")
cat("Clusters:", nlevels(rat19$seurat_clusters), "\n")
