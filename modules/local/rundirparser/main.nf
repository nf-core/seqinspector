process RUNDIRPARSER {
    tag "${rundir.simpleName}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/41/412df2cdcf04e0a12971ba61b12cacaa5a49705442afe99ad96668bebbb8f880/data'
        : 'community.wave.seqera.io/library/pip_pyyaml_xmltodict:a4e48bd1ab4b6a53'}"

    input:
    tuple val(dir_meta), path(rundir)

    output:
    tuple val(dir_meta), path("*_mqc.*"), emit: multiqc
    tuple val("${task.process}"), val('Python'), eval("python --version |& sed '1!d ; s/Python //'"), emit: versions_python, topic: versions
    tuple val("${task.process}"), val('PyYAML'), eval("python -c 'import yaml; print(yaml.__version__)'"), emit: versions_pyyaml, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def input_tar = rundir.toString().endsWith(".tar.gz") ? true : false
    def input_dir = input_tar ? rundir.toString() - '.tar.gz' : rundir
    """
    if [ ! -d ${input_dir} ]; then
        mkdir -p ${input_dir}
    fi

    if ${input_tar}; then
        ## Ensures --strip-components only applied when top level of tar contents is a directory
        ## If just files or multiple directories, place all in ${input_dir}

        if [[ \$(tar -taf ${rundir} | grep -o -P "^.*?\\/" | uniq | wc -l) -eq 1 ]]; then
            tar \\
                -C ${input_dir} --strip-components 1 \\
                -xavf \\
                ${rundir}
        else
            tar \\
                -C ${input_dir} \\
                -xavf \\
                ${rundir}
        fi
    fi

    # TODO: check what kind of seq platfrom to decide which script to use
    parse_illumina.py ${input_dir}
    """

    stub:
    """
    touch ${rundir}_mqc.yml
    """
}
