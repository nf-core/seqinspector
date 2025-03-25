process RUNDIRPARSER {
    tag "$rundir.baseName"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ad/ad2bcce70756f81c07c7e2ffd9b66213bf48ace786466395ac3a402840df2ffb/data' :
        'community.wave.seqera.io/library/pip_pyyaml:c2ecf27a7f63796e' }"

    input:
    tuple val(joint_meta), path(rundir)

    output:
    tuple val(joint_meta), path("*_rundir_mqc.*"), emit: multiqc
    path "versions.yml",                    emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${rundir.baseName}"
    """
    rundirparser.py ${rundir}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Python: \$(python --version |& sed '1!d ; s/Python //')
        PyYAML: \$(python -c "import yaml; print(yaml.__version__)")
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${rundir.baseName}"
    // TODO nf-core: A stub section should mimic the execution of the original module as best as possible
    //               Have a look at the following examples:
    //               Simple example: https://github.com/nf-core/modules/blob/818474a292b4860ae8ff88e149fbcda68814114d/modules/nf-core/bcftools/annotate/main.nf#L47-L63
    //               Complex example: https://github.com/nf-core/modules/blob/818474a292b4860ae8ff88e149fbcda68814114d/modules/nf-core/bedtools/split/main.nf#L38-L54
    """
    touch rundir_mqc.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Python: stub_version
        PyYAML: stub_version
    END_VERSIONS
    """
}
