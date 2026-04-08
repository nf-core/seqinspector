process TOULLIGQC {
    label 'process_low'
    tag "${meta.id}"

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/toulligqc:2.8.4--pyhdfd78af_0'
        : 'biocontainers/toulligqc:2.8.4--pyhdfd78af_0'}"

    input:

    tuple val(meta), path(ontfile)

    output:
    tuple val(meta), val("${task.process}"), val('toulligqc'), path("report.data"), emit: report_data, topic: multiqc_files
    tuple val(meta), val("${task.process}"), val('toulligqc'), path("report.html"), emit: report_html, topic: multiqc_files, optional: true
    tuple val(meta), val("${task.process}"), val('toulligqc'), path("images"), emit: images, topic: multiqc_files
    tuple val("${task.process}"), val('toulligqc'), eval('toulligqc --version'), emit: versions_toulligqc, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    def input_file = "${ontfile}".endsWith(".fastq") || "${ontfile}".endsWith(".fastq.gz") || "${ontfile}".endsWith(".fq") || "${ontfile}".endsWith(".fq.gz")
        ? "--fastq ${ontfile}"
        : "${ontfile}".endsWith(".txt") || "${ontfile}".endsWith(".txt.gz")
            ? "--sequencing-summary-source ${ontfile}"
            : "${ontfile}".endsWith(".bam") ? "--bam ${ontfile}" : ''

    """
    toulligqc \\
        ${input_file} \\
        --report-name toulligqc \\
        --output-directory ${prefix} \\
        ${args}

    # Remove empty folder
    rmdir ${prefix}

    # Move files
    mv ${prefix}toulligqc/images .
    mv ${prefix}toulligqc/report.* .

    # Remove now empty folder
    rmdir ${prefix}toulligqc
    """

    stub:
    """
    mkdir images
    touch images/Correlation_between_read_length_and_PHRED_score.html
    touch images/Distribution_of_read_lengths.html
    touch images/PHRED_score_density_distribution.html
    touch images/Read_count_histogram.html
    touch images/plotly.min.js
    touch report.data
    touch report.html
    """
}
