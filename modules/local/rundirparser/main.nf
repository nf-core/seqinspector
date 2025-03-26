process RUNDIRPARSER {
    tag "$rundir.simpleName"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/41/412df2cdcf04e0a12971ba61b12cacaa5a49705442afe99ad96668bebbb8f880/data' :
        'community.wave.seqera.io/library/pip_pyyaml_xmltodict:a4e48bd1ab4b6a53' }"

    input:
    tuple val(dir_meta), path(rundir)

    output:
    tuple val(dir_meta), path("*_mqc.*"), emit: multiqc
    path "versions.yml",                  emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    # TODO: check what kind of seq platfrom to decide which script to use
    rundirparser.py ${rundir}
    parse_illumina.py ${rundir}

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
