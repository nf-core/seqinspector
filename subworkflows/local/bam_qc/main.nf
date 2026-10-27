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

    ch_hsmetrics_in = ch_bam_bai.combine(ch_bait_intervals).combine(ch_target_intervals)

    PICARD_COLLECTHSMETRICS(
        ch_hsmetrics_in.filter { ("picard_collecthsmetrics" in tools) },
        ch_reference_fasta,
        ch_reference_fai,
        ch_ref_dict,
        [[:], []],
    )

    PICARD_COLLECTMULTIPLEMETRICS(
        ch_bam_bai.filter { ("picard_collectmultiplemetrics" in tools) },
        ch_reference_fasta,
        ch_reference_fai,
    )
}
