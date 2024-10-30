process SYLPH_PROFILE {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/sylph:0.6.1--h4ac6f70_0' :
        'biocontainers/sylph:0.6.1--h4ac6f70_0' }"

    input:
    tuple val(meta), path(sketch_fastq), path(sketch_fastq_genome)   

    output:
    tuple val(meta), path('profile_out.tsv'), emit: profile_out

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    
    """
    sylph profile \\
          $args \\
          $sketch_fastq \\
          $sketch_fastq_genome \\
          -o profile_out.tsv
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: \$(sylph -V|awk '{print \$2}')
    END_VERSIONS
          
    """

    stub:
    """
    touch profile_out.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: \$(sylph -V|awk '{print \$2}')
    END_VERSIONS
    """

}