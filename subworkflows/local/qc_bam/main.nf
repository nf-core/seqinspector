//
// A quality check subworkflow for processed bam files.
//

include { PICARD_COLLECTHSMETRICS } from '../../../modules/nf-core/picard/collecthsmetrics/main'
include { PICARD_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/picard/createsequencedictionary/main'

workflow QC_BAM {
    take:

        ch_bam_bai
        ch_reference_fasta
        ch_reference_fasta_fai

    main:

        ch_versions = channel.empty()


        ch_bait_intervals = channel
            .fromPath(params.bait_intervals)
            .collect()

        ch_target_intervals = channel
            .fromPath(params.target_intervals)
            .collect()


        ch_hsmetrics_in = ch_bam_bai
            .combine(ch_bait_intervals)
            .combine(ch_target_intervals)


        if (!params.ref_dict) {
            PICARD_CREATESEQUENCEDICTIONARY(
                ch_reference_fasta
            )
            ch_ref_dict = PICARD_CREATESEQUENCEDICTIONARY.out.reference_dict
            ch_versions = ch_versions.mix(PICARD_CREATESEQUENCEDICTIONARY.out.versions)
        }
        else {
            ch_ref_dict = channel.fromPath(params.ref_dict).map { [[id: it.simpleName], it] }
        }

        PICARD_COLLECTHSMETRICS(
            ch_hsmetrics_in,
            ch_reference_fasta,
            ch_reference_fasta_fai,
            ch_ref_dict,
            [[], []],
        )
        ch_versions = ch_versions.mix(PICARD_COLLECTHSMETRICS.out.versions.first())


    emit:

        hs_metrics = PICARD_COLLECTHSMETRICS.out.metrics
        versions = ch_versions

}