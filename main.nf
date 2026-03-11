#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    nf-core/seqinspector
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/nf-core/seqinspector
    Website: https://nf-co.re/seqinspector
    Slack  : https://nfcore.slack.com/channels/seqinspector
----------------------------------------------------------------------------------------

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

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    GENOME PARAMETER VALUES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

params.fasta   = getGenomeAttribute('fasta')
params.bwamem2 = getGenomeAttribute('bwamem2')
params.dict    = getGenomeAttribute('dict')

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    def fasta = params.fasta
        ? channel.fromPath(params.fasta, checkIfExists: true).map { file -> tuple([id: file.name], file) }.collect()
        : channel.empty()

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
        setup_tools(params.tools_setup, params.tools, params.skip_tools),
        params.fasta,
    )

    PREPARE_GENOME(
        fasta,
        params.bwamem2,
        setup_tools(params.tools_setup, params.tools, params.skip_tools),
        params.dict,
    )

    //
    // WORKFLOW: Run main workflow
    //
    NFCORE_SEQINSPECTOR(
        PIPELINE_INITIALISATION.out.samplesheet,
        fasta,
        PREPARE_GENOME.out.bwamem2_index,
        PREPARE_GENOME.out.reference_dict,
        PREPARE_GENOME.out.reference_fai,
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
    bwamem2_index
    dict
    fasta_fai

    main:
    //
    // WORKFLOW: Run pipeline
    //
    SEQINSPECTOR(
        samplesheet,
        params.bait_intervals,
        bwamem2_index,
        fasta,
        params.fastq_screen_references,
        params.multiqc_config,
        params.multiqc_logo,
        params.multiqc_methods_description,
        params.outdir,
        dict,
        fasta_fai,
        params.sample_size,
        setup_tools(params.tools_setup, params.tools, params.skip_tools),
        params.sort_bam,
        params.target_intervals,
    )

    emit:
    global_report   = SEQINSPECTOR.out.global_report // channel: /path/to/multiqc_report.html
    grouped_reports = SEQINSPECTOR.out.grouped_reports // channel: /path/to/multiqc_report.html
}

// FUNCTIONS

def setup_tools(input_setup, input_tools, input_skip) {

    // Trying hopefully a simpler approach than https://github.com/nf-core/seqinspector/pull/23

    // All tools available (cf tools from schema)
    // fastqc|fastqscreen|picard_collecthsmetrics|picard_collectmultiplemetrics|rundirparser|seqfu_stats
    // Other tools are run by default if a downstream tools is selected
    // SEQTK_SAMPLE is run by default if params.sample > 0, and is therefore not in this list

    // Any tools in skip tools will override any selection made via tools or tools_setup

    def setup_list = input_setup ? input_setup.tokenize(',').sort().unique() : ['no_setup']
    def tools_list = input_tools ? input_tools.tokenize(',').sort().unique() : []
    def skip_list = input_skip ? input_skip.tokenize(',').sort().unique() : []

    // Current list actually used are default, minimal and promethion
    // The others are here as a showcase for what could be done

    if ('all' in setup_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'picard_collecthsmetrics'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'rundirparser'
        tools_list << 'seqfu_stats'
    }
    if ('bam' in setup_list) {
        tools_list << 'picard_collecthsmetrics'
        tools_list << 'picard_collectmultiplemetrics'
    }
    if ('fastq' in setup_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
    }
    if ('default' in setup_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'rundirparser'
        tools_list << 'seqfu_stats'
    }
    if ('illumina' in setup_list) {
        tools_list << 'rundirparser'
        tools_list << 'seqfu_stats'
    }
    if ('minimal' in setup_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'seqfu_stats'
    }
    if ('ont' in setup_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'seqfu_stats'
    }

    tools_list = tools_list.sort().unique() - skip_list

    return tools_list
}
