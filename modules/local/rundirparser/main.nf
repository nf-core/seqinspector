process RUNDIRPARSER {
    tag "$rundir.simpleName"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ad/ad2bcce70756f81c07c7e2ffd9b66213bf48ace786466395ac3a402840df2ffb/data' :
        'community.wave.seqera.io/library/pip_pyyaml:c2ecf27a7f63796e' }"

    input:
    tuple val(dir_meta), path(rundir)

    output:
    tuple val(dir_meta), path("*_mqc.*"), emit: multiqc
    path "versions.yml",                  emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    rundirparser.py ${rundir}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Python: \$(python --version |& sed '1!d ; s/Python //')
        PyYAML: \$(python -c "import yaml; print(yaml.__version__)")
    END_VERSIONS
    """

    stub:
    """
    touch rundir_mqc.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Python: stub_version
        PyYAML: stub_version
    END_VERSIONS
    """
}
