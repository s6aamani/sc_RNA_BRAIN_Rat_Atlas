#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

// ─────────────────────────────────────────────────────────────────────────────
// PROCESS 1: CellRanger count (merges technical replicates via --sample list)
// Reference: Ensembl mRatBN7.2 release 108, pre-built by dasmeh
// ─────────────────────────────────────────────────────────────────────────────
process CELLRANGER_COUNT {
    tag "${params.sample_id}"

    output:
    path "${params.sample_id}/outs", emit: outs_dir

    publishDir "${params.cellranger_dir}", mode: 'copy', overwrite: true

    script:
    """
    ${params.cellranger} count \\
        --id=${params.sample_id} \\
        --transcriptome=${params.ref_dir} \\
        --fastqs=${params.fastq_dir} \\
        --sample=${params.samples} \\
        --localcores=${task.cpus} \\
        --localmem=60 \\
        --create-bam=false
    """
}

// ─────────────────────────────────────────────────────────────────────────────
// PROCESS 2: Seurat QC, clustering, markers
// ─────────────────────────────────────────────────────────────────────────────
process SEURAT_ANALYSIS {
    tag "${params.sample_id}"

    input:
    path matrix_dir

    output:
    path "*.pdf",                          emit: plots
    path "*.csv",                          emit: markers
    path "${params.sample_id}_seurat.rds", emit: rds

    publishDir "${params.results_dir}", mode: 'copy', overwrite: true,
               pattern: "*.{pdf,csv}"
    publishDir "${params.data_dir}",    mode: 'copy', overwrite: true,
               pattern: "*.rds"

    script:
    """
    Rscript ${projectDir}/02_seurat_rat19.R \\
        --matrix_dir ${matrix_dir} \\
        --sample     ${params.sample_id} \\
        --out_dir    .
    """
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW
// ─────────────────────────────────────────────────────────────────────────────
workflow {
    matrix_path = "${params.cellranger_dir}/${params.sample_id}/outs/filtered_feature_bc_matrix"

    if (file(matrix_path).exists()) {
        log.info "CellRanger output found at ${matrix_path} — skipping CELLRANGER_COUNT"
        matrix_ch = Channel.value(file(matrix_path))
    } else {
        log.info "Running CellRanger count..."
        CELLRANGER_COUNT()
        matrix_ch = CELLRANGER_COUNT.out.outs_dir.map { it.resolve('filtered_feature_bc_matrix') }
    }

    SEURAT_ANALYSIS(matrix_ch)
}
