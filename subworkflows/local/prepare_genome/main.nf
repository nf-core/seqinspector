//
// Prepare reference genome files

include { BWAMEM2_INDEX                   } from '../../../modules/nf-core/bwamem2/index'
include { PICARD_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/picard/createsequencedictionary'
include { SAMTOOLS_FAIDX                  } from '../../../modules/nf-core/samtools/faidx'

workflow PREPARE_GENOME {
    take:
    fasta //tuple val(meta), path(fasta)
    bwamem2 // path(bwamem2/)
    dict // path(dict)
    fai // path(fai)
    genome // val('genome')
    tools // list('tools')

    main:
    // Initialize all channels that might be used later
    ch_bwamem2 = channel.empty()
    ch_dict = channel.empty()
    ch_fai = channel.empty()

    // Use pre-built index when --bwamem2 parameter is provided or build index from reference FASTA if necessary
    if (bwamem2) {
        ch_bwamem2 = channel.fromPath(bwamem2, checkIfExists: true)
            .map { index_dir -> tuple([id: genome], index_dir) }
            .collect()
    }
    else {
        BWAMEM2_INDEX(fasta.filter { 'picard_collecthsmetrics' in tools || 'picard_collectmultiplemetrics' in tools })
        ch_bwamem2 = BWAMEM2_INDEX.out.index
    }

    // Use pre-built index when --dict parameter is provided or build index from reference FASTA if necessary
    if (dict) {
        ch_dict = channel.fromPath(dict, checkIfExists: true).map { _dict -> [[id: dict.simpleName], dict] }
    }
    else {
        PICARD_CREATESEQUENCEDICTIONARY(fasta.filter { 'picard_collecthsmetrics' in tools })
        ch_dict = PICARD_CREATESEQUENCEDICTIONARY.out.reference_dict
    }

    // Use pre-built index when --fai parameter is provided or build index from reference FASTA if necessary
    if (fai) {
        ch_fai = channel.fromPath(fai, checkIfExists: true)
            .map { index_dir -> tuple([id: genome], index_dir) }
            .collect()
    }
    else {
        SAMTOOLS_FAIDX(
            fasta.map { meta, _fasta -> [meta, fasta, []] }.filter { 'picard_collecthsmetrics' in tools || 'picard_collectmultiplemetrics' in tools },
            false,
        )
        ch_fai = SAMTOOLS_FAIDX.out.fai
    }

    emit:
    bwamem2_index  = ch_bwamem2
    reference_dict = ch_dict
    reference_fai  = ch_fai
}
