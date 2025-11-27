//
// Prepare reference genome files

include { BWAMEM2_INDEX                 } from '../../../modules/nf-core/bwamem2/index'
include { SAMTOOLS_FAIDX                } from '../../../modules/nf-core/samtools/faidx'
include { PICARD_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/picard/createsequencedictionary/main'

workflow PREPARE_GENOME {

    take:
    ch_reference_fasta
    bwamem2
    skip_tools
    run_picard_collecthsmetrics  // value: [mandatory] [ bool ]
    ref_dict                     // value: [mandatory] [ path(ref_dict) ]

    main:
    // Initialize all channels that might be used later
    ch_bwamem2_index      = channel.empty()
    ch_reference_fai      = channel.empty()
    ch_reference_fasta    = channel.empty()
    ch_ref_dict           = channel.empty()
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

    if (run_picard_collecthsmetrics){
        if (ref_dict) {
        ch_ref_dict = channel.fromPath(ref_dict, checkIfExists: true).map { [[id: it.simpleName], it] }
        }
        else {
            PICARD_CREATESEQUENCEDICTIONARY(
                ch_reference_fasta
            )
            ch_ref_dict = PICARD_CREATESEQUENCEDICTIONARY.out.reference_dict
            ch_versions = ch_versions.mix(PICARD_CREATESEQUENCEDICTIONARY.out.versions)
        }
    }

    emit:
    bwamem2_index = ch_bwamem2_index
    reference_fai = ch_reference_fai
    ref_dict      = ch_ref_dict
    versions      = ch_versions

}
