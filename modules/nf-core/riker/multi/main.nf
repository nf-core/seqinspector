process RIKER_MULTI {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/62/62ce363fc85eaa178522adfc3ddbc4a145d7a4136981e060151886e34e7a55d5/data' :
        'community.wave.seqera.io/library/riker:0.3.0--56fa17ae2be0828f' }"

    input:
    tuple val(meta),  path(bam), path(bai), path(baits, stageAs: "baits/*"), path(targets, stageAs: 'targets/*')
    tuple val(meta2), path(fasta), path(fai)

    output:
    tuple val(meta), val("${task.process}"), val('riker'), path("*.alignment-metrics.txt")             , optional: true, emit: alignment_metrics, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.base-distribution-by-cycle.txt")    , optional: true, emit: base_dist, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.mean-quality-by-cycle.txt")         , optional: true, emit: mean_qual, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.quality-score-distribution.txt")    , optional: true, emit: qual_dist, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.error-mismatch.txt")                , optional: true, emit: error_mismatch, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.error-overlap.txt")                 , optional: true, emit: error_overlap, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.error-indel.txt")                   , optional: true, emit: error_indel, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.gcbias-detail.txt")                 , optional: true, emit: gcbias_detail, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.gcbias-summary.txt")                , optional: true, emit: gcbias_summary, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.hybcap-metrics.txt")                , optional: true, emit: hybcap_metrics, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.hybcap-per-target.txt")             , optional: true, emit: hybcap_per_target, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.hybcap-per-base.txt*")              , optional: true, emit: hybcap_per_base, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.isize-metrics.txt")                 , optional: true, emit: isize_metrics, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.isize-histogram.txt")               , optional: true, emit: isize_histogram, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.wgs-metrics.txt")                   , optional: true, emit: wgs_metrics, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('riker'), path("*.wgs-coverage.txt")                  , optional: true, emit: wgs_coverage, topic: multiqc_files
    tuple val(meta), path("*.pdf")                               , optional: true, emit: pdf
    tuple val("${task.process}"), val('riker'), eval("riker --version 2>&1 | sed 's/riker //'") , topic: versions, emit: versions_riker

    when:
    task.ext.when == null || task.ext.when

    script:
    def args        = task.ext.args ?: ''
    def prefix      = task.ext.prefix ?: "${meta.id}"
    def ref         = fasta ? "-r ${fasta}" : ''
    if ((baits as Boolean) ^ (targets as Boolean)) {
        error "RIKER_MULTI: both 'baits' and 'targets' must be provided together, or neither"
    }
    def hybcap_opts = (baits && targets) ? "--hybcap::baits ${baits} --hybcap::targets ${targets}" : ''
    """
    riker multi \\
        -i ${bam} \\
        ${ref} \\
        -o ${prefix} \\
        --threads ${task.cpus} \\
        ${hybcap_opts} \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.alignment-metrics.txt
    touch ${prefix}.base-distribution-by-cycle.txt
    touch ${prefix}.mean-quality-by-cycle.txt
    touch ${prefix}.quality-score-distribution.txt
    touch ${prefix}.error-mismatch.txt
    touch ${prefix}.error-overlap.txt
    touch ${prefix}.error-indel.txt
    touch ${prefix}.gcbias-detail.txt
    touch ${prefix}.gcbias-summary.txt
    touch ${prefix}.hybcap-metrics.txt
    touch ${prefix}.hybcap-per-target.txt
    touch ${prefix}.hybcap-per-base.txt
    touch ${prefix}.isize-metrics.txt
    touch ${prefix}.isize-histogram.txt
    touch ${prefix}.wgs-metrics.txt
    touch ${prefix}.wgs-coverage.txt
    touch ${prefix}.base-distribution-by-cycle.pdf
    touch ${prefix}.gcbias-chart.pdf
    touch ${prefix}.isize-histogram.pdf
    touch ${prefix}.mean-quality-by-cycle.pdf
    touch ${prefix}.quality-score-distribution.pdf
    touch ${prefix}.wgs-coverage.pdf
    """
}
