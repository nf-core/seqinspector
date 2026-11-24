process SOMALIERCONTAM_REPORT {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/df/df323a03567e752b8e7a9954f7692f9074f67dbd8127d2cdf563937eb591e1e0/data'
        : 'community.wave.seqera.io/library/python_numpy_pandas_matplotlib-base:3781e1b411a92e2b'}"

    input:
    tuple val(meta), path(samples), path(groups), path(identity_pairs)
    tuple val(meta2), path(attribution_pairs, arity: '1..*', stageAs: 'attribution/pairs/*'), path(attribution_self, arity: '1..*', stageAs: 'attribution/self/*')
    tuple val(meta3), path(relate_samples, arity: '0..*', stageAs: 'relate/samples/*'), path(relate_pairs, arity: '0..*', stageAs: 'relate/pairs/*')
    tuple val(meta4), path(contamination_pairs, arity: '0..*', stageAs: 'contamination/pairs/*')
    tuple val(meta5), path(coverage, arity: '0..*', stageAs: 'coverage/*')

    output:
    tuple val(meta), path("*.summary.samples.tsv")      , emit: summary
    tuple val(meta), path("*.attribution.pairs.tsv.gz") , emit: attribution_pairs
    tuple val(meta), path("*.longitudinal.pairs.tsv")   , emit: longitudinal
    tuple val(meta), path("*.relatedness_flags.tsv")    , emit: flags
    tuple val(meta), path("*.attribution_llr.png")      , emit: heatmap, optional: true
    tuple val(meta), val("${task.process}"), val('somalier_contam'), path("*_mqc.tsv"), emit: multiqc, topic: multiqc_files
    tuple val("${task.process}"), val('somalier_contam'), eval('somalier_contam.py --version | sed "s/.* //"'), emit: versions_somalier_contam, topic: versions
    tuple val("${task.process}"), val('python'), eval('python3 --version | sed "s/Python //"'), emit: versions_python, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def relate_samples_arg = relate_samples ? "--relate-samples ${relate_samples.join(' ')}" : ''
    def relate_pairs_arg   = relate_pairs ? "--relate-pairs ${relate_pairs.join(' ')}" : ''
    def contamination_arg  = contamination_pairs ? "--contam-pairs ${contamination_pairs.join(' ')}" : ''
    def coverage_arg       = coverage ? "--coverage ${coverage.join(' ')}" : ''
    """
    export MPLCONFIGDIR=\$PWD/.matplotlib

    somalier_contam.py report \\
        --samples ${samples} \\
        --groups ${groups} \\
        --identity-pairs ${identity_pairs} \\
        --attribution-pairs ${attribution_pairs.join(' ')} \\
        --attribution-self ${attribution_self.join(' ')} \\
        ${relate_samples_arg} \\
        ${relate_pairs_arg} \\
        ${contamination_arg} \\
        ${coverage_arg} \\
        --prefix ${prefix} \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.summary.samples.tsv
    echo | gzip > ${prefix}.attribution.pairs.tsv.gz
    touch ${prefix}.longitudinal.pairs.tsv
    touch ${prefix}.relatedness_flags.tsv
    touch ${prefix}_summary_mqc.tsv
    """
}
