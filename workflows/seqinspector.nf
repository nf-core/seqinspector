include { samplesheetToList             } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// nf-core
include { BWAMEM2_MEM                   } from '../modules/nf-core/bwamem2/mem'
include { FASTQC                        } from '../modules/nf-core/fastqc'
include { FASTQSCREEN_FASTQSCREEN       } from '../modules/nf-core/fastqscreen/fastqscreen'
include { PICARD_COLLECTMULTIPLEMETRICS } from '../modules/nf-core/picard/collectmultiplemetrics'
include { SAMTOOLS_FAIDX                } from '../modules/nf-core/samtools/faidx'
include { SAMTOOLS_INDEX                } from '../modules/nf-core/samtools/index'
include { SEQFU_STATS                   } from '../modules/nf-core/seqfu/stats'
include { RUNDIRPARSER                  } from '../modules/local/rundirparser'
include { SEQTK_SAMPLE                  } from '../modules/nf-core/seqtk/sample'
include { QC_BAM                        } from '../subworkflows/local/qc_bam'

include { MULTIQC as MULTIQC_GLOBAL     } from '../modules/nf-core/multiqc'
include { MULTIQC as MULTIQC_PER_TAG    } from '../modules/nf-core/multiqc'

include { paramsSummaryMap              } from 'plugin/nf-schema'
include { paramsSummaryMultiqc          } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML        } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText        } from '../subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { reportIndexMultiqc            } from '../subworkflows/local/utils_nfcore_seqinspector_pipeline'

// local
include { PREPARE_GENOME                } from '../subworkflows/local/prepare_genome'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SEQINSPECTOR {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    fasta_file
    skip_tools
    bwamem2

    main:
    ch_versions = channel.empty()
    ch_multiqc_files = channel.empty()
    ch_multiqc_extra_files = channel.empty()
    ch_bwamem2_mem = channel.empty()
    ch_samtools_index = channel.empty()
    ch_reference_fasta = fasta_file ? channel.fromPath(fasta_file, checkIfExists: true).map { file -> tuple([id: file.name], file) }.collect() : channel.value([[:], []])

    PREPARE_GENOME(
        ch_reference_fasta,
        bwamem2,
        skip_tools,
        params.run_picard_collecthsmetrics,
        params.ref_dict,
    )

    //
    // MODULE: Parse rundir info
    //
    if (!("rundirparser" in skip_tools)) {

        // From samplesheet channel serving (sampleMetaObj, sampleReadsPath) tuples:
        // --> Create new rundir channel serving (rundirMetaObj, rundirPath) tuples
        ch_rundir = ch_samplesheet
            .map { meta, _reads -> [meta.rundir, meta] }
            .groupTuple()
            .map { rundir, metas ->
                // Collect all unique tags into a list
                def all_tags = metas.collect { meta -> meta.tags }.flatten().unique()
                // Create a new meta object whose attributes are...
                //  1. tags: The list of merged tags, used for grouping MultiQC reports
                //  2. dirname: The simple name of the rundir, used for setting unique output names in publishDir
                def dir_meta = [tags: all_tags, dirname: rundir.simpleName]
                // Return the new structure, to...
                //  1. Feed into rundir specific processes
                //  2. Mix with the ch_multiqc_files channel downstream
                [dir_meta, rundir]
            }
            .view()

        RUNDIRPARSER(ch_rundir)

        ch_multiqc_files = ch_multiqc_files.mix(RUNDIRPARSER.out.multiqc)
        ch_versions = ch_versions.mix(RUNDIRPARSER.out.versions)
    }

    //
    // MODULE: Run Seqtk sample to perform subsampling
    //
    if (!("seqtk_sample" in skip_tools) && params.sample_size > 0) {
        ch_sample_sized = SEQTK_SAMPLE(
            ch_samplesheet.map { meta, reads ->
                [meta, reads, params.sample_size]
            }
        ).reads
        ch_versions = ch_versions.mix(SEQTK_SAMPLE.out.versions)
    }
    else {
        // No subsampling
        ch_sample_sized = ch_samplesheet
    }

    //
    // MODULE: Run FastQC
    //
    if (!("fastqc" in skip_tools)) {
        FASTQC(
            ch_sample_sized.map { meta, subsampled ->
                [meta, subsampled]
            }
        )
        ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)
        ch_versions = ch_versions.mix(FASTQC.out.versions)
    }


    //
    // Module: Run SeqFu stats
    //
    if (!("seqfu_stats" in skip_tools)) {
        ch_seqfu_stats = SEQFU_STATS(
            ch_samplesheet.map { meta, reads ->
                [[id: "seqfu", sample_id: meta.id, tags: meta.tags], reads]
            }
        )
        ch_seqfu_stats.stats
            .map { meta, stats ->
                {
                    // Parse the stats TSV file
                    [meta.sample_id, stats]
                }
            }
            .splitCsv(header: true, sep: '\t')
            .map { sample_id, row ->
                // Check if requested sample size exceeds available reads
                def sample_reads = row['#Seq'].toInteger()
                if (params.sample_size > sample_reads) {
                    // prntln is used here instead of log.warn/log.info as nf-test captures stdout
                    // from 'println' but buffers log messages making them unavailable for assertion
                    // This message will appear in .nextflow.log file and temporarily on runtime stdout.
                    log.warn("${sample_id}: Requested sample_size (${params.sample_size}) is larger than available reads (${sample_reads}). Pipeline will continue with ${sample_reads} reads.")
                }
            }
        ch_multiqc_files = ch_multiqc_files.mix(SEQFU_STATS.out.multiqc)
        ch_versions = ch_versions.mix(SEQFU_STATS.out.versions)
    }

    //
    // MODULE: Run FastQ Screen
    //

    // Parse the reference info needed to create a FastQ Screen config file
    // and transpose it into a tuple containing lists for each property

    if (!("fastqscreen" in skip_tools)) {
        ch_fastqscreen_refs = channel.fromList(
                samplesheetToList(
                    params.fastq_screen_references,
                    "${projectDir}/assets/schema_fastq_screen_references.json",
                )
            )
            .toList()
            .transpose()
            .toList()

        FASTQSCREEN_FASTQSCREEN(
            ch_sample_sized,
            ch_fastqscreen_refs,
        )
        ch_multiqc_files = ch_multiqc_files.mix(FASTQSCREEN_FASTQSCREEN.out.txt)
        ch_versions = ch_versions.mix(FASTQSCREEN_FASTQSCREEN.out.versions)
    }

    // MODULE: Align reads with BWA-MEM2
    if (!("bwamem2_mem" in skip_tools)) {
        BWAMEM2_MEM(
            ch_sample_sized,
            PREPARE_GENOME.out.bwamem2_index,
            ch_reference_fasta,
            params.sort_bam ?: true,
        )
        ch_bwamem2_mem = BWAMEM2_MEM.out.bam
        ch_versions = ch_versions.mix(BWAMEM2_MEM.out.versions)

        SAMTOOLS_INDEX(
            ch_bwamem2_mem
        )
        ch_samtools_index = SAMTOOLS_INDEX.out.bai
        ch_versions = ch_versions.mix(SAMTOOLS_INDEX.out.versions)
    }


    if (!("picard_collectmultiplemetrics" in skip_tools)) {

        ch_reference_fai = PREPARE_GENOME.out.reference_fai

        ch_bait_intervals = params.bait_intervals ? channel.fromPath(params.bait_intervals).collect() : channel.empty()
        ch_target_intervals = params.target_intervals ? channel.fromPath(params.target_intervals).collect() : channel.empty()

        ch_ref_dict = PREPARE_GENOME.out.ref_dict


        QC_BAM(
            ch_bwamem2_mem,
            ch_samtools_index,
            ch_reference_fasta,
            ch_reference_fai,
            params.run_picard_collecthsmetrics,
            ch_bait_intervals,
            ch_target_intervals,
            ch_ref_dict,
        )

        ch_multiqc_files = ch_multiqc_files.mix(QC_BAM.out.multiple_metrics, QC_BAM.out.hs_metrics)
        ch_versions = ch_versions.mix(QC_BAM.out.versions)
    }

    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_' + 'seqinspector_software_' + 'mqc_' + 'versions.yml',
            sort: true,
            newLine: true,
        )
        .set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //

    ch_tags = ch_multiqc_files
        .map { meta, _sample -> meta.tags }
        .flatten()
        .unique()

    ch_multiqc_config = params.multiqc_config
        ? channel.fromPath(params.multiqc_config, checkIfExists: true)
        : channel.fromPath("${projectDir}/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_logo = params.multiqc_logo
        ? channel.fromPath(params.multiqc_logo, checkIfExists: true)
        : channel.empty()

    summary_params = paramsSummaryMap(
        workflow,
        parameters_schema: "nextflow_schema.json"
    )
    ch_workflow_summary = channel.value(
        paramsSummaryMultiqc(summary_params)
    )
    ch_multiqc_custom_methods_description = params.multiqc_methods_description
        ? file(params.multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description = channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description)
    )
    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml')
    )
    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(ch_collated_versions)
    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true,
        )
    )
    // Add index to other MultiQC reports
    //ch_multiqc_extra_files_global = channel.empty()
    ch_multiqc_extra_files_global = ch_multiqc_extra_files.mix(
        ch_tags.toList().map { tag_list ->
            reportIndexMultiqc(tag_list)
        }.collectFile(
            name: 'multiqc_index_mqc.yaml'
        )
    )

    MULTIQC_GLOBAL(
        ch_multiqc_files.map { _meta, file -> file }.mix(ch_multiqc_extra_files_global).collect(),
        ch_multiqc_config.toList(),
        [],
        ch_multiqc_logo.toList(),
        [],
        [],
    )

    ch_multiqc_extra_files_tag = ch_multiqc_extra_files.mix(
        ch_tags.toList().map { tag_list ->
            reportIndexMultiqc(tag_list, false)
        }.collectFile(
            name: 'multiqc_index_mqc.yaml'
        )
    )

    multiqc_extra_files_per_tag = ch_tags.combine(ch_multiqc_extra_files_tag)

    // Group samples by tag
    tagged_mqc_files = ch_tags
        .combine(ch_multiqc_files)
        .filter { sample_tag, meta, _sample -> sample_tag in meta.tags }
        .map { sample_tag, _meta, sample -> [sample_tag, sample] }
        .mix(multiqc_extra_files_per_tag)
        .groupTuple()
        .tap { mqc_by_tag }
        .collectFile { sample_tag, _samples ->

            def prefix_tag = "[TAG:${sample_tag}]"
            [
                "${prefix_tag}_multiqc_extra_config.yml",
                """
                    |output_fn_name: \"${prefix_tag}_multiqc_report.html\"
                    |data_dir_name:  \"${prefix_tag}_multiqc_data\"
                    |plots_dir_name: \"${prefix_tag}_multiqc_plots\"
                """.stripMargin(),
            ]
        }
        .map { file -> [(file =~ /\[TAG:(.+)\]/)[0][1], file] }
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
        [],
    )

    emit:
    global_report   = MULTIQC_GLOBAL.out.report.toList() // channel: [ /path/to/multiqc_report.html ]
    grouped_reports = MULTIQC_PER_TAG.out.report.toList() // channel: [ /path/to/multiqc_report.html ]
    versions        = ch_versions // channel: [ path(versions.yml) ]
}
