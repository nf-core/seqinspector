/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FASTQC                        } from '../modules/nf-core/fastqc/main'
include { FASTQSCREEN_FASTQSCREEN       } from '../modules/nf-core/fastqscreen/fastqscreen/main'

include { MULTIQC as MULTIQC_GLOBAL     } from '../modules/nf-core/multiqc/main'
include { MULTIQC as MULTIQC_PER_LANE   } from '../modules/nf-core/multiqc/main'
include { MULTIQC as MULTIQC_PER_GROUP  } from '../modules/nf-core/multiqc/main'
include { MULTIQC as MULTIQC_PER_RUNDIR } from '../modules/nf-core/multiqc/main'

include { paramsSummaryMap              } from 'plugin/nf-validation'
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
    // MODULE: Run FastQC
    //
    FASTQC (
        ch_samplesheet
    )
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    //
    // MODULE: Run FastQ Screen
    //

    FASTQSCREEN_FASTQSCREEN (
        ch_samplesheet
        Channel.fromPath('/Users/franziska.franziska/Desktop/sequinspector_other_files/fastq_screen_config_file.conf')
    )

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_pipeline_software_mqc_versions.yml',
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

    MULTIQC_GLOBAL (
        ch_multiqc_files
            .map { meta, file -> file }
            .mix(ch_multiqc_extra_files)
            .collect(),
        ch_multiqc_config.toList(),
        Channel.empty().toList(),
        ch_multiqc_logo.toList()
    )

    // Generate reports by lane
    multiqc_extra_files_per_lane = ch_multiqc_files
        .filter { meta, sample -> meta.lane }
        .map { meta, sample -> [lane: meta.lane] }
        .unique()
        .combine(ch_multiqc_extra_files)

    lane_mqc_files = ch_multiqc_files
        .filter { meta, sample -> meta.lane }
        .mix(multiqc_extra_files_per_lane)
        .map { meta, sample -> [ "[LANE:${meta.lane}]", meta, sample ] }
        .groupTuple()
        .tap { mqc_by_lane }
        .collectFile{
            lane, meta, samples -> [
                "${lane}_multiqc_extra_config.yml",
                """
                    |output_fn_name: \"${lane}_multiqc_report.html\"
                    |data_dir_name:  \"${lane}_multiqc_data\"
                    |plots_dir_name: \"${lane}_multiqc_plots\"
                """.stripMargin()
            ]
        }
        .map { file -> [ (file =~ /(\[LANE:.+\])/)[0][1], file ] }
        .join(mqc_by_lane)
        .multiMap { lane, config, meta , samples_per_lane ->
            samples_per_lane: samples_per_lane
            config: config
        }

    MULTIQC_PER_LANE(
        lane_mqc_files.samples_per_lane,
        ch_multiqc_config.toList(),
        lane_mqc_files.config,
        ch_multiqc_logo.toList()
    )

    // Generate reports by group
    multiqc_extra_files_per_group = ch_multiqc_files
        .filter { meta, sample -> meta.group }
        .map { meta, sample -> meta.group }
        .unique()
        .map { group -> [group:group] }
        .combine(ch_multiqc_extra_files)

    group_mqc_files = ch_multiqc_files
        .filter { meta, sample -> meta.group }
        .mix(multiqc_extra_files_per_group)
        .map { meta, sample -> [ "[GROUP:${meta.group}]", meta, sample ] }
        .groupTuple()
        .tap { mqc_by_group }
        .collectFile{
            group, meta, samples -> [
                "${group}_multiqc_extra_config.yml",
                """
                    |output_fn_name: \"${group}_multiqc_report.html\"
                    |data_dir_name:  \"${group}_multiqc_data\"
                    |plots_dir_name: \"${group}_multiqc_plots\"
                """.stripMargin()
            ]
        }
        .map { file -> [ (file =~ /(\[GROUP:.+\])/)[0][1], file ] }
        .join(mqc_by_group)
        .multiMap { group, config, meta , samples_per_group ->
            samples_per_group: samples_per_group
            config: config
        }

    MULTIQC_PER_GROUP(
        group_mqc_files.samples_per_group,
        ch_multiqc_config.toList(),
        group_mqc_files.config,
        ch_multiqc_logo.toList()
    )

    // Generate reports by rundir
    multiqc_extra_files_per_rundir = ch_multiqc_files
        .filter { meta, sample -> meta.rundir }
        .map { meta, sample -> meta.rundir }
        .unique()
        .map { rundir -> [rundir:rundir] }
        .combine(ch_multiqc_extra_files)

    rundir_mqc_files = ch_multiqc_files
        .filter { meta, sample -> meta.rundir }
        .mix(multiqc_extra_files_per_rundir)
        .map { meta, sample -> [ "[RUNDIR:${meta.rundir.name}]", meta, sample ] }
        .groupTuple()
        .tap { mqc_by_rundir }
        .collectFile{
            rundir, meta, samples -> [
                "${rundir}_multiqc_extra_config.yml",
                """
                    |output_fn_name: \"${rundir}_multiqc_report.html\"
                    |data_dir_name:  \"${rundir}_multiqc_data\"
                    |plots_dir_name: \"${rundir}_multiqc_plots\"
                """.stripMargin()
            ]
        }
        .map { file -> [ (file =~ /(\[RUNDIR:.+\])/)[0][1], file ] }
        .join(mqc_by_rundir)
        .multiMap { rundir, config, meta , samples_per_rundir ->
            samples_per_rundir: samples_per_rundir
            config: config
        }

    MULTIQC_PER_RUNDIR(
        rundir_mqc_files.samples_per_rundir,
        ch_multiqc_config.toList(),
        rundir_mqc_files.config,
        ch_multiqc_logo.toList()
    )

    emit:
    global_report = MULTIQC_GLOBAL.out.report.toList()      // channel: /path/to/multiqc_report.html
    lane_reports = MULTIQC_PER_LANE.out.report.toList()     // channel: [ /path/to/multiqc_report.html ]
    group_reports = MULTIQC_PER_GROUP.out.report.toList()   // channel: [ /path/to/multiqc_report.html ]
    rundir_reports = MULTIQC_PER_RUNDIR.out.report.toList() // channel: [ /path/to/multiqc_report.html ]
    versions       = ch_versions                            // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
