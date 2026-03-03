//
// A quality check subworkflow for processed bam files.
//

include { PICARD_COLLECTHSMETRICS       } from '../../../modules/nf-core/picard/collecthsmetrics'
include { PICARD_COLLECTMULTIPLEMETRICS } from '../../../modules/nf-core/picard/collectmultiplemetrics'

workflow QC_BAM {
    take:
    ch_bam // channel: [mandatory] [ val(meta), path(bam)]
    ch_bai // channel: [mandatory] [ val(meta), path(bai) ]
    ch_reference_fasta // channel: [mandatory] [ val(meta), path(reference_fasta) ]
    ch_reference_fai // channel: [mandatory] [ val(meta), path(reference_fai) ]
    ch_bait_intervals // channel: [mandatory for picard_collecthsmetrics] [ val(meta), path(bait_intervals) ]
    ch_target_intervals // channel: [mandatory for picard_collecthsmetrics] [ val(meta), path(target_intervals) ]
    ch_ref_dict // channel: [mandatory for picard_collecthsmetrics] [ val(meta), path(ref_dict) ]
    skip_tools

    main:
    ch_multiple_metrics = channel.empty()
    ch_hs_metrics = channel.empty()

    ch_bam_bai = ch_bam.join(ch_bai, failOnDuplicate: true, failOnMismatch: true)

    if (!("picard_collectmultiplemetrics" in skip_tools)) {

        PICARD_COLLECTMULTIPLEMETRICS(
            ch_bam_bai,
            ch_reference_fasta,
            ch_reference_fai,
        )

        ch_multiple_metrics = PICARD_COLLECTMULTIPLEMETRICS.out.metrics
    }

    if (!("picard_collecthsmetrics" in skip_tools)) {

        ch_hsmetrics_in = ch_bam_bai.combine(ch_bait_intervals).combine(ch_target_intervals)

        PICARD_COLLECTHSMETRICS(
            ch_hsmetrics_in,
            ch_reference_fasta,
            ch_reference_fai,
            ch_ref_dict,
            [[], []],
        )

        ch_hs_metrics = PICARD_COLLECTHSMETRICS.out.metrics
    }

    emit:
    hs_metrics       = ch_hs_metrics
    multiple_metrics = ch_multiple_metrics
}
