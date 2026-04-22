# Rebuild native-code R packages inside the rocker-rstudio container so their
# .so files link against the container's BLAS (libopenblas) instead of
# OpenHPC's libRlapack.so. Run this ONCE from inside an rserver session:
#
#   source("Scripts/rserver/rebuild_native_pkgs.R")
#
# After it finishes, library(Seurat) should load cleanly. Pure-R packages are
# still symlinked from the batch library by start_rstudio.sh — only compiled
# packages need to be reinstalled here.

rocker_lib <- "~/R/rocker-rstudio/4.4.3-geo"
rocker_lib <- path.expand(rocker_lib)
dir.create(rocker_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(rocker_lib, .libPaths()))

cran <- "https://cloud.r-project.org"

# Seurat pulls in the bulk of the native deps; install it first so the solver
# picks the right versions, then sweep any remaining gaps.
core <- c("Matrix", "spam", "SeuratObject", "Seurat")
install.packages(core, lib = rocker_lib, repos = cran, Ncpus = 4)

# Anything else that the batch library had as native but is still missing here.
batch_lib <- "~/R/x86_64-pc-linux-gnu-library/4.4"
batch_lib <- path.expand(batch_lib)
has_so <- function(pkg) {
  length(Sys.glob(file.path(batch_lib, pkg, "libs", "*.so"))) > 0
}
batch_pkgs <- list.dirs(batch_lib, recursive = FALSE, full.names = FALSE)
native <- batch_pkgs[vapply(batch_pkgs, has_so, logical(1))]
installed_here <- rownames(installed.packages(lib.loc = rocker_lib))
missing <- setdiff(native, installed_here)

# Filter to CRAN-available names (Bioconductor packages handled separately).
cran_avail <- rownames(available.packages(repos = cran))
missing_cran <- intersect(missing, cran_avail)
missing_bioc <- setdiff(missing, cran_avail)

if (length(missing_cran)) {
  install.packages(missing_cran, lib = rocker_lib, repos = cran, Ncpus = 4)
}

if (length(missing_bioc)) {
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager", lib = rocker_lib, repos = cran)
  }
  BiocManager::install(missing_bioc, lib = rocker_lib, update = FALSE, ask = FALSE)
}

cat("Done. Installed in:", rocker_lib, "\n")
cat("Try: library(Seurat)\n")
