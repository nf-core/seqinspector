//
// Prepare reference genome files

include { BWAMEM2_INDEX                 } from '../../../modules/nf-core/bwamem2/index'
include { SAMTOOLS_FAIDX                } from '../../../modules/nf-core/samtools/faidx'

workflow PREPARE_GENOME {

    take:
    fasta_file
    bwa_index
    skip_tools

    main:
    // Initialize all channels that might be used later
    ch_bwamem2_index = channel.empty()
    ch_reference_fasta_fai = channel.empty()
    ch_reference_fasta = channel.empty()
    ch_versions      = channel.empty()

    if (!("bwamem2_index" in skip_tools)) {
        ch_reference_fasta = channel.fromPath(fasta_file, checkIfExists: true).map { file -> tuple([id: file.name], file) }.collect()

        if (bwa_index) {
            // Use pre-built index when --bwa_index parameter is provided
            ch_bwamem2_index = channel.fromPath(bwa_index, checkIfExists: true)
                .map { index_dir -> tuple([id: index_dir.name], index_dir) }
                .collect()

        }
        else {
            // Build index from reference FASTA when no pre-built index is provided
            BWAMEM2_INDEX(
                ch_reference_fasta
            )
            ch_bwamem2_index = BWAMEM2_INDEX.out.index
            ch_versions = ch_versions.mix(BWAMEM2_INDEX.out.versions)

        }
    }

    if (!("samtools_faidx" in skip_tools)) {

        // Assume ch_fasta emits tuple(meta, fasta)
        SAMTOOLS_FAIDX(
            ch_reference_fasta,
            [[:], []],
            true,
        )
        ch_reference_fasta_fai = SAMTOOLS_FAIDX.out.fai
        ch_versions = ch_versions.mix(SAMTOOLS_FAIDX.out.versions)
    }

 // Gather versions
    ch_versions = ch_versions.mix(BWAMEM2_INDEX.out.versions)
    ch_versions = ch_versions.mix(SAMTOOLS_FAIDX.out.versions)


    emit:
    bwamem2_index = BWAMEM2_INDEX.out.index
    reference_fasta_fai =     SAMTOOLS_FAIDX.out.fai
    versions            = ch_versions

}       
