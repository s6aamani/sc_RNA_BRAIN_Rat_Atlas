#!/usr/bin/env bash
set -euo pipefail

# How to use:
# 1) Run: bash Scripts/rserver/start_rstudio.sh
# 2) Check logs/rstudio-geo-server.<jobid>.out for tunnel/login instructions.
# 3) Stop the session with: scancel -f <jobid>

# Keep the RStudio session close to the analysis stack while using the newer
# RStudio container available on this cluster.
module purge || true
module load "${GNU_MODULE:-gnu9/9.4.0}"
module load "${R_MODULE:-R-src/4.4.2}"
module load "${RSTUDIO_MODULE:-RStudio/4.4.3-geo}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOGS_DIR="${PROJECT_DIR}/logs"
R_BIN="${R_BIN:-/opt/ohpc/pub/libs/gnu9/R-src/4.4.2/bin/R}"
RSERVER_SLURM="${RSERVER_SLURM:-/opt/ohpc/pub/apps/containers/rstudio-4.4.3-geo/start-rserver.slurm}"
EXTRA_BIND="${EXTRA_BIND:-/masc_shared:/masc_shared}"
SRC_USER_LIB="${SRC_USER_LIB:-/home/$USER/R/x86_64-pc-linux-gnu-library/4.4}"
ROCKER_USER_LIB="${ROCKER_USER_LIB:-/home/$USER/R/rocker-rstudio/4.4.3-geo}"
R_HOME_DIR="$("${R_BIN}" RHOME)"
R_LIB_DIR="${R_HOME_DIR}/lib"

if [[ ! -d "${PROJECT_DIR}" ]]; then
  echo "ERROR: Project directory not found: ${PROJECT_DIR}" >&2
  exit 1
fi

if [[ ! -x "${R_BIN}" ]]; then
  echo "ERROR: R binary not executable: ${R_BIN}" >&2
  exit 1
fi

if [[ ! -f "${RSERVER_SLURM}" ]]; then
  echo "ERROR: RStudio SLURM template not found: ${RSERVER_SLURM}" >&2
  exit 1
fi

export RSTUDIO_WHICH_R="${R_BIN}"
export RENV_CONFIG_EXTERNAL_LIBRARIES="${ROCKER_USER_LIB}"
export R_HOME="${R_HOME_DIR}"
unset R_LIBS
unset R_LIBS_SITE
# Inside the rocker container, point R at the rocker-specific library. Pure-R
# packages are symlinked from SRC_USER_LIB into ROCKER_USER_LIB by the mirror
# step below; compiled packages must be installed natively in ROCKER_USER_LIB
# (see Scripts/rserver/rebuild_native_pkgs.R).
export R_LIBS_USER="${ROCKER_USER_LIB}"
export SINGULARITYENV_RENV_CONFIG_EXTERNAL_LIBRARIES="${RENV_CONFIG_EXTERNAL_LIBRARIES}"
export APPTAINERENV_RENV_CONFIG_EXTERNAL_LIBRARIES="${RENV_CONFIG_EXTERNAL_LIBRARIES}"
export SINGULARITYENV_R_LIBS_SITE="${R_LIBS_USER}"
export APPTAINERENV_R_LIBS_SITE="${R_LIBS_USER}"
export SINGULARITYENV_R_HOME="${R_HOME}"
export APPTAINERENV_R_HOME="${R_HOME}"

# Avoid inherited conda envs overriding start-rserver internals.
if [[ -n "${CONDA_DEFAULT_ENV:-}" ]]; then
  conda deactivate || true
fi
unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
unset CONDA_PROMPT_MODIFIER
unset PYTHONHOME
unset PYTHONPATH

clean_path="$(
  printf '%s\n' "$PATH" \
    | tr ':' '\n' \
    | awk '$0 !~ /(conda|miniconda|miniforge|mambaforge)/' \
    | paste -sd: -
)"
export PATH="/usr/bin:/bin:$(dirname "${R_BIN}"):${clean_path}"

if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
  clean_ld_library_path="$(
    printf '%s\n' "$LD_LIBRARY_PATH" \
      | tr ':' '\n' \
      | awk '$0 !~ /(conda|miniconda|miniforge|mambaforge)/' \
      | paste -sd: -
  )"
  export LD_LIBRARY_PATH="${R_LIB_DIR}:${clean_ld_library_path}"
else
  export LD_LIBRARY_PATH="${R_LIB_DIR}"
fi

export SINGULARITYENV_LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"
export APPTAINERENV_LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"

# Mirror the canonical user library into rocker-rstudio so the container sees
# the same package builds as non-container R jobs — but ONLY for pure-R packages.
# Packages with compiled code (a libs/ dir with .so files) must be built against
# the rocker container's BLAS/LAPACK (libopenblas), not OpenHPC's libRlapack.so.
# Mirroring those via symlink drags in .so files that cannot resolve their
# shared-library deps inside the container (e.g. spam -> libRlapack.so not found).
mkdir -p "${ROCKER_USER_LIB}"
if [[ -d "${SRC_USER_LIB}" ]]; then
  backup_stamp="$(date +%Y%m%d-%H%M%S)"
  while IFS= read -r pkgdir; do
    pkg="$(basename "${pkgdir}")"
    [[ "${pkg}" == 00LOCK* ]] && continue
    # Skip packages with compiled shared objects — they must be installed
    # natively inside the rocker container.
    if compgen -G "${pkgdir}/libs/*.so" > /dev/null; then
      continue
    fi
    dst_pkg="${ROCKER_USER_LIB}/${pkg}"
    if [[ -L "${dst_pkg}" ]]; then
      current_target="$(readlink "${dst_pkg}")"
      if [[ "${current_target}" == "${pkgdir}" ]]; then
        continue
      fi
      rm -f "${dst_pkg}"
    elif [[ -e "${dst_pkg}" ]]; then
      mv "${dst_pkg}" "${dst_pkg}.bak-${backup_stamp}"
    fi
    ln -s "${pkgdir}" "${dst_pkg}"
  done < <(find "${SRC_USER_LIB}" -mindepth 1 -maxdepth 1 -type d | sort)
fi

mkdir -p "${LOGS_DIR}"
cd "${LOGS_DIR}"

echo "Launching RStudio with:"
echo "  project: ${PROJECT_DIR}"
echo "  log dir: ${LOGS_DIR}"
echo "  RSTUDIO_WHICH_R=${RSTUDIO_WHICH_R}"
echo "  R version: $("${R_BIN}" --version | head -n 1)"
echo "  python3: $(command -v python3) ($(python3 --version 2>&1))"

tmp_slurm="$(mktemp "${TMPDIR:-/tmp}/start-rserver.XXXXXX.slurm")"
tmp_slurm2="$(mktemp "${TMPDIR:-/tmp}/start-rserver.XXXXXX.slurm")"
trap 'rm -f "${tmp_slurm}" "${tmp_slurm2}"' EXIT
cp "${RSERVER_SLURM}" "${tmp_slurm}"

# Extend site defaults to make /masc_shared visible inside the RStudio container.
if grep -q '^export SINGULARITY_BIND=' "${tmp_slurm}"; then
  if ! grep -q '/masc_shared:/masc_shared' "${tmp_slurm}"; then
    sed -E 's#^(export SINGULARITY_BIND=".*)"$#\1,'"${EXTRA_BIND}"'"#' "${tmp_slurm}" > "${tmp_slurm2}"
    mv "${tmp_slurm2}" "${tmp_slurm}"
  fi
else
  echo "ERROR: Could not locate SINGULARITY_BIND in ${RSERVER_SLURM}" >&2
  exit 1
fi

# Start sessions in the project root inside the container.
if ! grep -q -- '--server-working-dir' "${tmp_slurm}"; then
  awk -v wd="${PROJECT_DIR}" '
    BEGIN { inserted=0 }
    {
      print
      if ($0 ~ /rserver --www-port \$\{PORT\} \\/ && inserted == 0) {
        print "        --server-working-dir " wd " \\"
        inserted=1
      }
    }
    END {
      if (inserted == 0) {
        exit 43
      }
    }
  ' "${tmp_slurm}" > "${tmp_slurm2}" || {
    rc=$?
    if [[ "${rc}" -eq 43 ]]; then
      echo "ERROR: Could not locate rserver command block in ${RSERVER_SLURM}" >&2
    else
      echo "ERROR: Failed to patch rserver working directory." >&2
    fi
    exit 1
  }
  mv "${tmp_slurm2}" "${tmp_slurm}"
fi

# Submit from the logs directory so the session log stays in the project-level logs folder.
sbatch --chdir "${LOGS_DIR}" "${tmp_slurm}"
