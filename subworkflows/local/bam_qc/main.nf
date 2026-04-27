//
// A quality check subworkflow for processed bam files.
//

include { PICARD_COLLECTHSMETRICS       } from '../../../modules/nf-core/picard/collecthsmetrics'
include { PICARD_COLLECTMULTIPLEMETRICS } from '../../../modules/nf-core/picard/collectmultiplemetrics'

workflow BAM_QC {
    take:
    ch_bam_bai // channel: [mandatory] [ val(meta), path(bam), path(bai)]
    ch_reference_fasta // channel: [mandatory] [ val(meta), path(reference_fasta) ]
    ch_reference_fai // channel: [mandatory] [ val(meta), path(reference_fai) ]
    ch_bait_intervals // channel: [mandatory for picard_collecthsmetrics] [ val(meta), path(bait_intervals) ]
    ch_target_intervals // channel: [mandatory for picard_collecthsmetrics] [ val(meta), path(target_intervals) ]
    ch_ref_dict // channel: [mandatory for picard_collecthsmetrics] [ val(meta), path(ref_dict) ]
    tools

    main:

    // Fork ch_bam_bai into two named branches so both downstream consumers
    // receive every emission. Without this, the queue channel is
    // distributed (rather than broadcast) between the .combine() operator
    // feeding CollectHsMetrics and the direct process input feeding
    // CollectMultipleMetrics, causing some samples to be silently dropped
    // from one of the two paths.
    ch_bam_bai_branched = ch_bam_bai.multiMap { meta, bam, bai ->
        for_hsmetrics:    tuple(meta, bam, bai)
        for_multimetrics: tuple(meta, bam, bai)
    }

    ch_hsmetrics_in = ch_bam_bai_branched.for_hsmetrics
        .combine(ch_bait_intervals)
        .combine(ch_target_intervals)

    PICARD_COLLECTHSMETRICS(
        ch_hsmetrics_in.filter { ("picard_collecthsmetrics" in tools) },
        ch_reference_fasta,
        ch_reference_fai,
        ch_ref_dict,
        [[:], []],
    )

    PICARD_COLLECTMULTIPLEMETRICS(
        ch_bam_bai_branched.for_multimetrics.filter { ("picard_collectmultiplemetrics" in tools) },
        ch_reference_fasta,
        ch_reference_fai,
    )
}
