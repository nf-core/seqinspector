//
// Prepare reference genome files

include { BWAMEM2_INDEX  } from '../../../modules/nf-core/bwamem2/index'
include { SAMTOOLS_FAIDX } from '../../../modules/nf-core/samtools/faidx'

workflow PREPARE_GENOME {

    take:
    ch_reference_fasta
    bwamem2
    skip_tools

    main:
    // Initialize all channels that might be used later
    ch_bwamem2_index      = channel.empty()
    ch_reference_fai      = channel.empty()
    ch_versions           = channel.empty()

    if (!("bwamem2_index" in skip_tools)) {
        if (bwamem2) {
            // Use pre-built index when --bwamem2 parameter is provided
            ch_bwamem2_index = channel.fromPath(bwamem2, checkIfExists: true)
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
        ch_reference_fai = SAMTOOLS_FAIDX.out.fai
        ch_versions = ch_versions.mix(SAMTOOLS_FAIDX.out.versions)
    }

    emit:
    bwamem2_index = ch_bwamem2_index
    reference_fai = ch_reference_fai
    versions      = ch_versions

}
