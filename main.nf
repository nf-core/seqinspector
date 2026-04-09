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

include { SEQINSPECTOR             } from './workflows/seqinspector'
include { PIPELINE_INITIALISATION  } from './subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { PIPELINE_COMPLETION      } from './subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { PREPARE_GENOME           } from './subworkflows/local/prepare_genome'
include { UNTAR as UNTAR_KRAKEN2DB } from './modules/nf-core/untar'
include { getGenomeAttribute       } from 'plugin/nf-core-utils'
include { defineToolsList          } from './subworkflows/local/utils_nfcore_seqinspector_pipeline'

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

    main:
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
        params.kraken2_db,
    )

    PREPARE_GENOME(
        params.fasta,
        params.bwamem2,
        params.dict,
        params.fai,
        params.genome ?: 'custom',
        tools,
    )

    // KRAKEN2_DB initialisation
    def ch_kraken2_db = channel.empty()
    if ('kraken2' in tools) {
        UNTAR_KRAKEN2DB(channel.fromPath(params.kraken2_db, checkIfExists: true).map { file -> [[id: 'kraken2_db'], file] }.filter { (params.kraken2_db.endsWith('.gz')) })
        ch_kraken2_db = params.kraken2_db.endsWith('.gz')
            ? UNTAR_KRAKEN2DB.out.untar.map { _meta, archive -> [archive] }.collect()
            : channel.fromPath(params.kraken2_db, checkIfExists: true).collect()
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
        params.kraken2_save_reads,
        params.kraken2_save_readclassifications,
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
        NFCORE_SEQINSPECTOR.out.report_global.map { _meta, report -> [report] }.toList(),
    )

    publish:
    bam_bai                = NFCORE_SEQINSPECTOR.out.bam_bai
    kraken2_db             = ch_kraken2_db
    multiqc_global         = NFCORE_SEQINSPECTOR.out.data_global.mix(NFCORE_SEQINSPECTOR.out.plots_global, NFCORE_SEQINSPECTOR.out.report_global)
    multiqc_grouped_data   = NFCORE_SEQINSPECTOR.out.data_groups
    multiqc_grouped_plots  = NFCORE_SEQINSPECTOR.out.plots_groups
    multiqc_grouped_report = NFCORE_SEQINSPECTOR.out.report_groups
    references             = channel.empty().mix(
        PREPARE_GENOME.out.bwamem2,
        PREPARE_GENOME.out.dict,
        PREPARE_GENOME.out.fai,
    )
    reports                = channel.topic("multiqc_files")
    subsampled             = NFCORE_SEQINSPECTOR.out.subsampled
}

output {
    bam_bai {
        path { meta, bam, index ->
            bam >> "mapped/${meta.id}/"
            index >> "mapped/${meta.id}/"
        }
    }
    kraken2_db {
        path "kraken2_db"
    }
    multiqc_global {
        path "multiqc/global_report"
    }
    multiqc_grouped_data {
        path { meta, file ->
            file >> "multiqc/group_reports/${meta.id}/multiqc_data"
        }
    }
    multiqc_grouped_plots {
        path { meta, file ->
            file >> "multiqc/group_reports/${meta.id}/multiqc_plots"
        }
    }
    multiqc_grouped_report {
        path { meta, file ->
            file >> "multiqc/group_reports/${meta.id}/multiqc_report.html"
        }
    }
    references {
        path "references/"
    }
    reports {
        path { meta, process, tool, file ->
            file >> (tool == 'krona'
                ? "reports/kraken2/${tool}/${meta.id}/"
                : tool == 'picard'
                    ? "reports/${process.tokenize(':').last().toLowerCase()}/${meta.id}/"
                    : tool == 'rundirparser' || tool == 'seqfu'
                        ? "reports/${tool}/${meta.id}/${meta.id}_${file.name}"
                        : "reports/${tool}/${meta.id}/")
        }
    }
    subsampled {
        path { meta, _fastq ->
            "subsampled/${meta.id}/"
        }
    }
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
    kraken2_save_reads
    kraken2_save_readclassifications

    main:
    //
    // WORKFLOW: Run pipeline
    //
    SEQINSPECTOR(
        samplesheet,
        params.bait_intervals,
        bwamem2,
        params.checkqc_config,
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
        kraken2_save_reads,
        kraken2_save_readclassifications,
    )

    emit:
    bam_bai       = SEQINSPECTOR.out.bam_bai
    data_global   = SEQINSPECTOR.out.data_global // channel: /path/to/multiqc_report.html
    data_groups   = SEQINSPECTOR.out.data_groups // channel: /path/to/multiqc_report.html
    plots_global  = SEQINSPECTOR.out.plots_global // channel: /path/to/multiqc_report.html
    plots_groups  = SEQINSPECTOR.out.plots_groups // channel: /path/to/multiqc_report.html
    report_global = SEQINSPECTOR.out.report_global // channel: /path/to/multiqc_report.html
    report_groups = SEQINSPECTOR.out.report_groups // channel: /path/to/multiqc_report.html
    subsampled    = SEQINSPECTOR.out.subsampled
}
