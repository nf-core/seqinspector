process SOMALIERCONTAM_ATTRIBUTE {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/df/df323a03567e752b8e7a9954f7692f9074f67dbd8127d2cdf563937eb591e1e0/data'
        : 'community.wave.seqera.io/library/python_numpy_pandas_matplotlib-base:3781e1b411a92e2b'}"

    input:
    tuple val(meta), path(extract, arity: '1..*', stageAs: 'somalier/*'), path(samples)
    tuple val(meta2), path(sites)

    output:
    tuple val(meta), path("*.attribution_pairs.tsv.gz"), emit: pairs
    tuple val(meta), path("*.attribution_self.tsv")    , emit: self
    tuple val("${task.process}"), val('somalier_contam'), eval('somalier_contam.py --version | sed "s/.* //"'), emit: versions_somalier_contam, topic: versions
    tuple val("${task.process}"), val('python'), eval('python3 --version | sed "s/Python //"'), emit: versions_python, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    export OMP_NUM_THREADS=${task.cpus} OPENBLAS_NUM_THREADS=${task.cpus} MKL_NUM_THREADS=${task.cpus}

    somalier_contam.py attribute \\
        --sites ${sites} \\
        --samples ${samples} \\
        --prefix ${prefix} \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo | gzip > ${prefix}.attribution_pairs.tsv.gz
    touch ${prefix}.attribution_self.tsv
    """
}
