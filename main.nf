#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/seqinspector
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/nf-core/seqinspector
    Website: https://nf-co.re/seqinspector
    Slack  : https://nfcore.slack.com/channels/seqinspector
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { SEQINSPECTOR            } from './workflows/seqinspector'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { PREPARE_GENOME          } from './subworkflows/local/prepare_genome'
include { getGenomeAttribute      } from 'plugin/nf-core-utils'
include { defineToolsList         } from './subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { UNTAR as UNTAR_KRAKEN2_DB } from './modules/nf-core/untar'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    GENOME PARAMETER VALUES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

params.bwamem2 = getGenomeAttribute('bwamem2')
params.dict    = getGenomeAttribute('dict')
params.fai     = getGenomeAttribute('fai')
params.fasta   = getGenomeAttribute('fasta')

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    def tools = defineToolsList(params.tools_bundle, params.tools, params.skip_tools)

    //
    // SUBWORKFLOW: Run initialisation tasks
    //

    PIPELINE_INITIALISATION(
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.help,
        params.help_full,
        params.show_hidden,
        tools,
        params.fasta,
    )

    PREPARE_GENOME(
        params.fasta,
        params.bwamem2,
        params.dict,
        params.fai,
        params.genome ?: 'custom',
        tools,
    )

    // KRAKEN2 Parameter Initialisation:
    if ('kraken2' in tools) {
        if (params.kraken2_db && params.kraken2_db.endsWith('.gz')) {
            UNTAR_KRAKEN2_DB( [ [:], params.kraken2_db ] )
            ch_kraken2_db = UNTAR_KRAKEN2_DB.out.untar.map { it[1] }
        } else if (params.kraken2_db) {
            ch_kraken2_db = Channel.fromPath(params.kraken2_db, checkIfExists: true).collect()
        } else {
            error "kraken2 is selected but --kraken2_db is not set"
        }
    } else {
        ch_kraken2_db = Channel.empty()
    }

    //
    // WORKFLOW: Run main workflow
    //
    NFCORE_SEQINSPECTOR(
        PIPELINE_INITIALISATION.out.samplesheet,
        PREPARE_GENOME.out.fasta,
        PREPARE_GENOME.out.bwamem2,
        PREPARE_GENOME.out.dict,
        PREPARE_GENOME.out.fai,
        tools,
        ch_kraken2_db,
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION(
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
        NFCORE_SEQINSPECTOR.out.global_report,
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow NFCORE_SEQINSPECTOR {
    take:
    samplesheet // channel: samplesheet read in from --input
    fasta
    bwamem2
    dict
    fai
    tools
    kraken2_db

    main:
    //
    // WORKFLOW: Run pipeline
    //
    SEQINSPECTOR(
        samplesheet,
        params.bait_intervals,
        bwamem2,
        fasta,
        params.fastq_screen_references,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir,
        dict,
        fai,
        params.sample_size,
        tools,
        params.target_intervals,
        kraken2_db,
    )

    emit:
    global_report   = SEQINSPECTOR.out.global_report // channel: /path/to/multiqc_report.html
    grouped_reports = SEQINSPECTOR.out.grouped_reports // channel: /path/to/multiqc_report.html
}
