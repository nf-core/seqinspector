/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { SEQTK_SAMPLE                  } from '../modules/nf-core/seqtk/sample/main'
include { FASTQC                        } from '../modules/nf-core/fastqc/main'

include { MULTIQC as MULTIQC_GLOBAL     } from '../modules/nf-core/multiqc/main'
include { MULTIQC as MULTIQC_PER_TAG    } from '../modules/nf-core/multiqc/main'

include { PHYLOGENETIC_QC               } from '../subworkflows/local/phylogenetic_qc'

include { paramsSummaryMap              } from 'plugin/nf-schema'
include { paramsSummaryMultiqc          } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML        } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText        } from '../subworkflows/local/utils_nfcore_seqinspector_pipeline'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SEQINSPECTOR {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    main:

    ch_versions            = Channel.empty()
    ch_multiqc_files       = Channel.empty()
    ch_multiqc_extra_files = Channel.empty()
    ch_multiqc_reports     = Channel.empty()

    //
    // MODULE: Run Seqtk sample to perform subsampling
    //
    if (params.sample_size > 0 ) {
        ch_sample_sized = SEQTK_SAMPLE(
            ch_samplesheet.map {
                meta, reads -> [meta, reads, params.sample_size]
            }
        ).reads
        ch_versions = ch_versions.mix(SEQTK_SAMPLE.out.versions.first())
    } else {
        // No do subsample
        ch_sample_sized = ch_samplesheet
    }

    //
    // MODULE: Run FastQC
    //
    FASTQC (
        ch_sample_sized.map {
            meta, subsampled -> [meta, subsampled]
        }
    )
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    //
    // SUBWORKFLOW: Run kraken2 and produce krona plots
    //
    PHYLOGENETIC_QC (
        ch_samplesheet
    )
    ch_multiqc_files = ch_multiqc_files.mix(PHYLOGENETIC_QC.out.mqc)
    ch_versions = ch_versions.mix(PHYLOGENETIC_QC.out.versions.first())


    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
            .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  + 'pipeline_software_' +  'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_logo   = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params                        = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary                   = Channel.value(
        paramsSummaryMultiqc(summary_params))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(ch_collated_versions)
    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    //            .map { meta, file -> file }
    MULTIQC_GLOBAL (
        ch_multiqc_files
            .map { meta, file -> file }
            .mix(ch_multiqc_extra_files)
            .collect(),
        ch_multiqc_config.toList(),
        [],
        ch_multiqc_logo.toList(),
        [],
        []
    )

    ch_tags = ch_multiqc_files
        .map { meta, sample -> meta.tags }
        .flatten()
        .unique()

    multiqc_extra_files_per_tag = ch_tags
        .combine(ch_multiqc_extra_files)

    // Group samples by tag
    tagged_mqc_files = ch_tags
        .combine(ch_multiqc_files)
        .filter { sample_tag, meta, sample -> sample_tag in meta.tags }
        .map { sample_tag, meta, sample -> [sample_tag, sample] }
        .mix(multiqc_extra_files_per_tag)
        .groupTuple()
        .tap { mqc_by_tag }
        .collectFile {
            sample_tag, samples ->
            def prefix_tag = "[TAG:${sample_tag}]"
            [
                "${prefix_tag}_multiqc_extra_config.yml",
                """
                    |output_fn_name: \"${prefix_tag}_multiqc_report.html\"
                    |data_dir_name:  \"${prefix_tag}_multiqc_data\"
                    |plots_dir_name: \"${prefix_tag}_multiqc_plots\"
                """.stripMargin()
            ]
        }
        .map { file -> [ (file =~ /\[TAG:(.+)\]/)[0][1], file ] }
        .join(mqc_by_tag)
        .multiMap { sample_tag, config, samples ->
            samples_per_tag: samples
            config: config
        }

    MULTIQC_PER_TAG(
        tagged_mqc_files.samples_per_tag,
        ch_multiqc_config.toList(),
        tagged_mqc_files.config,
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    global_report   = MULTIQC_GLOBAL.out.report.toList()    // channel: [ /path/to/multiqc_report.html ]
    grouped_reports = MULTIQC_PER_TAG.out.report.toList()   // channel: [ /path/to/multiqc_report.html ]
    versions        = ch_versions                           // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
