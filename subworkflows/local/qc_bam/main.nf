//
// A quality check subworkflow for processed bam files.
//

include { PICARD_COLLECTHSMETRICS         } from '../../../modules/nf-core/picard/collecthsmetrics/main'
include { PICARD_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/picard/createsequencedictionary/main'

workflow QC_BAM {
    take:
    ch_bam_bai           // channel: [mandatory] [ val(meta), path(bam), path(bai) ]
    ch_bait_intervals    // channel: [mandatory] [ val(meta), path(bait_intervals) ]
    ch_target_intervals  // channel: [mandatory] [ val(meta), path(target_intervals) ]
    ch_reference_fasta   // channel: [mandatory] [ val(meta), path(reference_fasta) ]
    ch_reference_fai     // channel: [mandatory] [ val(meta), path(reference_fai) ]
    ref_dict             // value:   [mandatory] [ path(ref_dict) ]

    main:
    ch_versions = channel.empty()
    ch_hsmetrics_in = ch_bam_bai
            .combine(ch_bait_intervals)
            .combine(ch_target_intervals)

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

    PICARD_COLLECTHSMETRICS(
        ch_hsmetrics_in,
        ch_reference_fasta,
        ch_reference_fai,
        ch_ref_dict,
        [[], []],
    )
    ch_versions = ch_versions.mix(PICARD_COLLECTHSMETRICS.out.versions.first())

    emit:
    hs_metrics = PICARD_COLLECTHSMETRICS.out.metrics
    versions = ch_versions
}
