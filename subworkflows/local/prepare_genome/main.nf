//
// Prepare reference genome files

include { BWAMEM2_INDEX                   } from '../../../modules/nf-core/bwamem2/index'
include { PICARD_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/picard/createsequencedictionary'
include { SAMTOOLS_FAIDX                  } from '../../../modules/nf-core/samtools/faidx'

workflow PREPARE_GENOME {
    take:
    fasta // path(fasta)
    bwamem2 // path(bwamem2/)
    dict // path(dict)
    fai // path(fai)
    genome // val('genome')
    tools // list('tools')

    main:
    // Initialize all channels that will be used to generate references files
    def ch_fasta = fasta ? channel.fromPath(file(fasta)).map { fasta_ -> [[id: genome], fasta_] }.collect() : channel.empty()
    def ch_bwamem2 = channel.empty()
    def ch_dict = channel.empty()
    def ch_fai = channel.empty()

    // Use pre-built index when --bwamem2 parameter is provided or build index from reference FASTA if necessary
    if (bwamem2) {
        ch_bwamem2 = channel.fromPath(bwamem2)
            .map { index_dir -> tuple([id: genome], index_dir) }
            .collect()
    }
    else {
        BWAMEM2_INDEX(ch_fasta.filter { 'picard_collecthsmetrics' in tools || 'picard_collectmultiplemetrics' in tools })
        ch_bwamem2 = BWAMEM2_INDEX.out.index
    }

    // Use pre-built index when --dict parameter is provided or build index from reference FASTA if necessary
    if (dict) {
        ch_dict = channel.fromPath(dict).map { _dict -> [[id: genome], dict] }
    }
    else {
        PICARD_CREATESEQUENCEDICTIONARY(ch_fasta.filter { 'picard_collecthsmetrics' in tools })
        ch_dict = PICARD_CREATESEQUENCEDICTIONARY.out.reference_dict
    }

    // Use pre-built index when --fai parameter is provided or build index from reference FASTA if necessary
    if (fai) {
        ch_fai = channel.fromPath(fai)
            .map { index_dir -> tuple([id: genome], index_dir) }
            .collect()
    }
    else {
        SAMTOOLS_FAIDX(
            ch_fasta.map { meta, _fasta -> [meta, _fasta, []] }.filter { 'picard_collecthsmetrics' in tools || 'picard_collectmultiplemetrics' in tools },
            false,
        )
        ch_fai = SAMTOOLS_FAIDX.out.fai
    }

    emit:
    bwamem2 = ch_bwamem2
    dict    = ch_dict
    fai     = ch_fai
    fasta   = ch_fasta
}
