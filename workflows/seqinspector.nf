include { samplesheetToList } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { SEQTK_SAMPLE                  } from '../modules/nf-core/seqtk/sample/main'
include { FASTQC                        } from '../modules/nf-core/fastqc/main'
include { SEQFU_STATS                   } from '../modules/nf-core/seqfu/stats'
include { FASTQSCREEN_FASTQSCREEN       } from '../modules/nf-core/fastqscreen/fastqscreen/main'
include { RUNDIRPARSER                  } from '../modules/local/rundirparser/main'

include { MULTIQC as MULTIQC_GLOBAL     } from '../modules/nf-core/multiqc/main'
include { MULTIQC as MULTIQC_PER_TAG    } from '../modules/nf-core/multiqc/main'

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
    ch_samplesheet               // channel: samplesheet read in from --input

    main:
    skip_tools = params.skip_tools ? params.skip_tools.split(',') : []

    ch_versions            = Channel.empty()
    ch_multiqc_files       = Channel.empty()
    ch_multiqc_extra_files = Channel.empty()
    ch_multiqc_reports     = Channel.empty()

    //
    // MODULE: Parse rundir info
    //
    if (!("rundirparser" in skip_tools)) {

        ch_rundir = ch_samplesheet
            // Group by rundir to merge tags from samples with the same rundir
            .map { meta, _reads -> [meta.rundir, meta] }
            .groupTuple()
            // Create a new meta object with merged tags for each unique rundir
            .map { rundir, metas ->
                // Collect all tags across all samples with this rundir
                def all_tags = metas.collect { it.tags }.flatten().unique()
                // Create a new meta object with the merged tags
                def dir_meta = [tags: all_tags, dirname: rundir.simpleName]
                // Return the new structure
                [dir_meta, rundir]
            }

        RUNDIRPARSER( ch_rundir )
        ch_multiqc_files = ch_multiqc_files.mix(RUNDIRPARSER.out.multiqc)
        ch_versions = ch_versions.mix(RUNDIRPARSER.out.versions.first())
    }

    //
    // MODULE: Run Seqtk sample to perform subsampling
    //
    if (!("seqtk_sample" in skip_tools) && params.sample_size > 0) {
        ch_sample_sized = SEQTK_SAMPLE(
            ch_samplesheet.map {
                meta, reads -> [meta, reads, params.sample_size]
            }
        ).reads
        ch_versions = ch_versions.mix(SEQTK_SAMPLE.out.versions.first())
    } else {
        // No subsampling
        ch_sample_sized = ch_samplesheet
    }

    //
    // MODULE: Run FastQC
    //
    if (!("fastqc" in skip_tools)) {
        FASTQC (
            ch_sample_sized.map {
                meta, subsampled -> [meta, subsampled]
            }
        )
        ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)
        ch_versions = ch_versions.mix(FASTQC.out.versions.first())
    }


    //
    // Module: Run SeqFu stats
    //
    if (!("seqfu_stats" in skip_tools)) {
        SEQFU_STATS (
            ch_samplesheet
        )
        ch_multiqc_files = ch_multiqc_files.mix(SEQFU_STATS.out.multiqc)
        ch_versions = ch_versions.mix(SEQFU_STATS.out.versions.first())
    }

    //
    // MODULE: Run FastQ Screen
    //

    // Parse the reference info needed to create a FastQ Screen config file
    // and transpose it into a tuple containing lists for each property

    if (!("fastqscreen" in skip_tools)) {
        ch_fastqscreen_refs = Channel
            .fromList(samplesheetToList(
                params.fastq_screen_references,
                "${projectDir}/assets/schema_fastq_screen_references.json"
            ))
            .toList()
            .transpose()
            .toList()

        FASTQSCREEN_FASTQSCREEN (
            ch_samplesheet,
            ch_fastqscreen_refs
        )
        ch_multiqc_files = ch_multiqc_files.mix(FASTQSCREEN_FASTQSCREEN.out.txt)
        ch_versions = ch_versions.mix(FASTQSCREEN_FASTQSCREEN.out.versions.first())
    }

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'seqinspector_software_'  + 'mqc_'  + 'versions.yml',
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

    summary_params = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(
        paramsSummaryMultiqc(summary_params))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description = Channel.value(
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

    MULTIQC_GLOBAL (
        ch_multiqc_files
            .map { _meta, file -> file }
            .mix(ch_multiqc_extra_files)
            .collect(),
        ch_multiqc_config.toList(),
        [],
        ch_multiqc_logo.toList(),
        [],
        []
    )

    ch_tags = ch_multiqc_files
        .map { meta, _sample -> meta.tags }
        .flatten()
        .unique()

    multiqc_extra_files_per_tag = ch_tags
        .combine(ch_multiqc_extra_files)

    // Group samples by tag
    tagged_mqc_files = ch_tags
        .combine(ch_multiqc_files)
        .filter { sample_tag, meta, _sample -> sample_tag in meta.tags }
        .map { sample_tag, _meta, sample -> [sample_tag, sample] }
        .mix(multiqc_extra_files_per_tag)
        .groupTuple()
        .tap { mqc_by_tag }
        .collectFile {
            sample_tag, _samples ->
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
        .multiMap { _sample_tag, config, samples ->
            samples_per_tag: samples.flatten()
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
