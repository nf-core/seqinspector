process FASTQSCREEN_FASTQSCREEN {
    tag "$meta.id | $meta2.database_name"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/fc/fc53eee7ca23c32220a9662fbb63c67769756544b6d74a1ee85cf439ea79a7ee/data' :
        'community.wave.seqera.io/library/fastq-screen_perl-gdgraph:5c1786a5d5bc1309'}"

    input:
    tuple val(meta), path(reads)  // .fastq files
    tuple val(meta2), path(database) // [[database_name,  database_notes], database_path]

    output:
    tuple val(meta), path("*.txt")     , emit: txt
    tuple val(meta), path("*.png")     , emit: png  , optional: true
    tuple val(meta), path("*.html")    , emit: html
    tuple val(meta), path("*.fastq.gz"), emit: fastq, optional: true
    path "versions.yml"                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def args = task.ext.args ?: ""
    // 'Database name','Genome path and basename','Notes'
    """
    echo "Writing config"
    echo "DATABASE    ${meta2.database_name}    ./${database}/genome    ${meta2.database_notes}" > fastq_screen.conf
    echo "Wrote config"

    fastq_screen \\
        --conf fastq_screen.conf \\
        --threads ${task.cpus} \\
        --aligner ${meta2.database_notes.toLowerCase()} \\
        $reads \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqscreen: \$(echo \$(fastq_screen --version 2>&1) | sed 's/^.*FastQ Screen v//; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch test_1_screen.html
    touch test_1_screen.png
    touch test_1_screen.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqscreen: \$(echo \$(fastq_screen --version 2>&1) | sed 's/^.*FastQ Screen v//; s/ .*\$//')
    END_VERSIONS
    """

}
