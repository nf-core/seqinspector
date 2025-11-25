//
// A quality check subworkflow for processed bam files.
//

include { PICARD_COLLECTMULTIPLEMETRICS } from '../../../modules/nf-core/picard/collectmultiplemetrics/main'
include { PICARD_COLLECTHSMETRICS } from '../../../modules/nf-core/picard/collecthsmetrics/main'
include { PICARD_CREATESEQUENCEDICTIONARY } from '../../../modules/nf-core/picard/createsequencedictionary/main'

workflow QC_BAM {
    take:
    ch_bam
    ch_bai
    ch_reference_fasta
    ch_reference_fasta_fai
    run_picard_collecthsmetrics
    ch_bait_intervals
    ch_target_intervals
    ref_dict

    main:

    ch_metrics = channel.empty()
    ch_versions = channel.empty()

    ch_bam_bai = ch_bam.join(ch_bai, failOnDuplicate: true, failOnMismatch: true)

    PICARD_COLLECTMULTIPLEMETRICS(
        ch_bam_bai,
        ch_reference_fasta,
        ch_reference_fasta_fai,
    )
    
    ch_metrics = ch_metrics.mix(PICARD_COLLECTMULTIPLEMETRICS.out.metrics)
    ch_versions = ch_versions.mix(PICARD_COLLECTMULTIPLEMETRICS.out.versions.first())

    if (run_picard_collecthsmetrics) {

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
            ch_reference_fasta_fai,
            ch_ref_dict,
            [[], []],
        )

        ch_metrics = ch_metrics.mix(PICARD_COLLECTHSMETRICS.out.metrics)
        ch_versions = ch_versions.mix(PICARD_COLLECTHSMETRICS.out.versions.first())
    }

    emit:
    metrics = ch_metrics
    versions = ch_versions
}
