#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

// ─────────────────────────────────────────────────────────────────────────────
// PROCESS 1: Download mRatBN7.2 + build CellRanger reference
// ─────────────────────────────────────────────────────────────────────────────
process BUILD_REF {
    tag "mRatBN7.2"

    output:
    path "mRatBN7.2", emit: ref

    publishDir "${params.ref_dir}", mode: 'copy', overwrite: false

    script:
    """
    wget -q "https://ftp.ensembl.org/pub/release-${params.ensembl_release}/fasta/rattus_norvegicus/dna/Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa.gz"
    gunzip Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa.gz

    wget -q "https://ftp.ensembl.org/pub/release-${params.ensembl_release}/gtf/rattus_norvegicus/Rattus_norvegicus.mRatBN7.2.${params.ensembl_release}.gtf.gz"
    gunzip Rattus_norvegicus.mRatBN7.2.${params.ensembl_release}.gtf.gz

    ${params.cellranger} mkgtf \\
        Rattus_norvegicus.mRatBN7.2.${params.ensembl_release}.gtf \\
        Rattus_norvegicus.mRatBN7.2.filtered.gtf \\
        --attribute=gene_biotype:protein_coding \\
        --attribute=gene_biotype:lncRNA

    ${params.cellranger} mkref \\
        --genome=mRatBN7.2 \\
        --fasta=Rattus_norvegicus.mRatBN7.2.dna.toplevel.fa \\
        --genes=Rattus_norvegicus.mRatBN7.2.filtered.gtf \\
        --nthreads=${task.cpus} \\
        --memgb=60
    """
}

// ─────────────────────────────────────────────────────────────────────────────
// PROCESS 2: CellRanger count (merges technical replicates via --sample list)
// ─────────────────────────────────────────────────────────────────────────────
process CELLRANGER_COUNT {
    tag "${params.sample_id}"

    input:
    path ref

    output:
    path "${params.sample_id}/outs/filtered_feature_bc_matrix.h5", emit: h5
    path "${params.sample_id}/outs/web_summary.html",               emit: summary

    publishDir "${params.data_dir}", mode: 'copy', overwrite: true

    script:
    """
    ${params.cellranger} count \\
        --id=${params.sample_id} \\
        --transcriptome=${ref} \\
        --fastqs=${params.fastq_dir} \\
        --sample=${params.samples} \\
        --localcores=${task.cpus} \\
        --localmem=60 \\
        --create-bam=false
    """
}

// ─────────────────────────────────────────────────────────────────────────────
// PROCESS 3: Seurat QC, clustering, markers
// ─────────────────────────────────────────────────────────────────────────────
process SEURAT_ANALYSIS {
    tag "${params.sample_id}"

    input:
    path h5

    output:
    path "*.pdf",               emit: plots
    path "*.csv",               emit: markers
    path "${params.sample_id}_seurat.rds", emit: rds

    publishDir "${params.results_dir}", mode: 'copy', overwrite: true,
               pattern: "*.{pdf,csv}"
    publishDir "${params.data_dir}",    mode: 'copy', overwrite: true,
               pattern: "*.rds"

    script:
    """
    Rscript ${projectDir}/02_seurat_rat19.R \\
        --h5       ${h5} \\
        --sample   ${params.sample_id} \\
        --out_dir  .
    """
}

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW
// ─────────────────────────────────────────────────────────────────────────────
workflow {
    // Skip BUILD_REF if reference already exists
    ref_path = "${params.ref_dir}/mRatBN7.2"
    ref_exists = file(ref_path).exists()

    if (ref_exists) {
        log.info "Reference already exists at ${ref_path} — skipping BUILD_REF"
        ref_ch = Channel.value(file(ref_path))
    } else {
        log.info "Building rat reference genome..."
        BUILD_REF()
        ref_ch = BUILD_REF.out.ref
    }

    CELLRANGER_COUNT(ref_ch)
    SEURAT_ANALYSIS(CELLRANGER_COUNT.out.h5)
}
