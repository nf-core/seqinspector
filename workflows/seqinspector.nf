/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// modules
include { BWAMEM2_MEM                } from '../modules/nf-core/bwamem2/mem'
include { FASTQC                     } from '../modules/nf-core/fastqc'
include { FASTQSCREEN_FASTQSCREEN    } from '../modules/nf-core/fastqscreen/fastqscreen'
include { MULTIQC as MULTIQC_GLOBAL  } from '../modules/nf-core/multiqc'
include { MULTIQC as MULTIQC_PER_TAG } from '../modules/nf-core/multiqc'
include { RUNDIRPARSER               } from '../modules/local/rundirparser'
include { SAMTOOLS_INDEX             } from '../modules/nf-core/samtools/index'
include { SEQFU_STATS                } from '../modules/nf-core/seqfu/stats'
include { SEQTK_SAMPLE               } from '../modules/nf-core/seqtk/sample'

// subworkflow
include { QC_BAM                     } from '../subworkflows/local/qc_bam'

// functions
include { methodsDescriptionText     } from '../subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { paramsSummaryMap           } from 'plugin/nf-schema'
include { paramsSummaryMultiqc       } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { reportIndexMultiqc         } from '../subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { samplesheetToList          } from 'plugin/nf-schema'
include { softwareVersionsToYAML     } from 'plugin/nf-core-utils'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SEQINSPECTOR {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    bait_intervals
    bwamem2_index
    fasta_reference
    fastq_screen_references
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir
    ref_dict
    ref_fai
    sample_size
    skip_tools
    sort_bam
    target_intervals

    main:
    ch_multiqc_files = channel.empty()
    ch_multiqc_extra_files = channel.empty()
    ch_bwamem2_mem = channel.empty()
    ch_samtools_index = channel.empty()

    //
    // MODULE: Parse rundir info
    //
    if (!("rundirparser" in skip_tools)) {

        // Branch the samplesheet channel based on rundir presence
        ch_rundir_branch = ch_samplesheet.branch { meta, _reads ->
            with_rundir: meta.rundir.size() > 0
            without_rundir: true
        }

        // Log warnings for samples without rundir
        ch_rundir_branch.without_rundir.subscribe { meta, _reads ->
            log.warn("Sample '${meta.id}' does not have a rundir specified")
        }

        // From samplesheet channel serving (sampleMetaObj, sampleReadsPath) tuples:
        // --> Create new rundir channel serving (rundirMetaObj, rundirPath) tuples
        ch_rundir = ch_rundir_branch.with_rundir
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

        ch_rundir.ifEmpty { log.warn("No samples with rundir found, skipping RUNDIRPARSER") }

        RUNDIRPARSER(ch_rundir)

        ch_multiqc_files = ch_multiqc_files.mix(RUNDIRPARSER.out.multiqc)
    }


    //
    // MODULE: Run Seqtk sample to perform subsampling
    //
    if (!("seqtk_sample" in skip_tools) && sample_size > 0) {
        SEQTK_SAMPLE(ch_samplesheet.map { meta, reads -> [meta, reads, sample_size] })

        ch_sample = SEQTK_SAMPLE.out.reads
    }
    else {
        // No subsampling
        ch_sample = ch_samplesheet
    }

    //
    // MODULE: Run FastQC
    //
    if (!("fastqc" in skip_tools)) {
        FASTQC(ch_sample)

        ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)
    }

    //
    // Module: Run SeqFu stats
    //
    if (!("seqfu_stats" in skip_tools)) {
        SEQFU_STATS(ch_samplesheet.map { meta, reads -> [[id: "seqfu", sample_id: meta.id, tags: meta.tags], reads] })

        // Parse the stats TSV file
        SEQFU_STATS.out.stats
            .map { meta, stats -> [meta.sample_id, stats] }
            .splitCsv(header: true, sep: '\t')
            .map { sample_id, row ->
                // Check if requested sample size exceeds available reads
                def sample_reads = row['#Seq'].toInteger()
                if (sample_size > sample_reads) {
                    log.warn("${sample_id}: Requested sample_size (${sample_size}) is larger than available reads (${sample_reads}). Pipeline will continue with ${sample_reads} reads.")
                }
            }

        ch_multiqc_files = ch_multiqc_files.mix(SEQFU_STATS.out.multiqc)
    }

    //
    // MODULE: Run FastQ Screen
    //

    // Parse the reference info needed to create a FastQ Screen config file
    // and transpose it into a tuple containing lists for each property

    if (!("fastqscreen" in skip_tools)) {
        ch_fastqscreen_refs = channel.fromList(
                samplesheetToList(
                    fastq_screen_references,
                    "${projectDir}/assets/schema_fastq_screen_references.json",
                )
            )
            .toList()
            .transpose()
            .toList()

        FASTQSCREEN_FASTQSCREEN(ch_sample, ch_fastqscreen_refs)

        ch_multiqc_files = ch_multiqc_files.mix(FASTQSCREEN_FASTQSCREEN.out.txt)
    }

    // MODULE: Align reads with BWA-MEM2
    if (!("picard_collecthsmetrics" in skip_tools || "picard_collectmultiplemetrics" in skip_tools)) {
        BWAMEM2_MEM(
            ch_sample,
            bwamem2_index,
            fasta_reference,
            sort_bam,
        )
        ch_bwamem2_mem = BWAMEM2_MEM.out.bam

        SAMTOOLS_INDEX(ch_bwamem2_mem)

        ch_samtools_index = SAMTOOLS_INDEX.out.bai

        QC_BAM(
            ch_bwamem2_mem,
            ch_samtools_index,
            fasta_reference,
            ref_fai,
            bait_intervals ? channel.fromPath(bait_intervals).collect() : channel.empty(),
            target_intervals ? channel.fromPath(target_intervals).collect() : channel.empty(),
            ref_dict,
            skip_tools,
        )

        ch_multiqc_files = ch_multiqc_files.mix(QC_BAM.out.multiple_metrics, QC_BAM.out.hs_metrics)
    }

    // Collate and save software versions
    //
    def collated_versions = softwareVersionsToYAML(
        softwareVersions: channel.topic("versions"),
        nextflowVersion: workflow.nextflow.version,
    ).collectFile(
        storeDir: "${outdir}/pipeline_info",
        name: 'nf_core_' + 'seqinspector_software_' + 'mqc_' + 'versions.yml',
        sort: true,
        newLine: true,
    )

    //
    // MODULE: MultiQC
    //

    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(collated_versions)

    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")

    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(
        channel.value(paramsSummaryMultiqc(summary_params)).collectFile(name: 'workflow_summary_mqc.yaml')
    )

    ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)

    ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_extra_files = ch_multiqc_extra_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))

    // Add index to other MultiQC reports
    ch_tags = ch_multiqc_files.map { meta, _files -> meta.tags }.flatten().unique()

    ch_multiqc_extra_files_global = ch_multiqc_extra_files.mix(
        ch_tags.toList().map { tag_list -> reportIndexMultiqc(tag_list) }.collectFile(name: 'multiqc_index_mqc.yaml')
    )

    MULTIQC_GLOBAL(
        ch_multiqc_files.map { _meta, files -> [files] }.flatten().collect().combine(ch_multiqc_extra_files_global.collect()).map { files ->
            [
                [id: 'seqinspector'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    ch_multiqc_extra_files_tag = ch_multiqc_extra_files.mix(
        ch_tags.toList().map { tag_list -> reportIndexMultiqc(tag_list, false) }.collectFile(name: 'multiqc_index_mqc.yaml')
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
        .map { sample_tag, config, samples ->
            [[id: sample_tag], samples.flatten(), config]
        }

    MULTIQC_PER_TAG(
        tagged_mqc_files.map { meta, files, config ->
            [
                meta,
                files,
                [
                    config,
                    multiqc_config
                        ? file(multiqc_config, checkIfExists: true)
                        : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                ],
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    emit:
    global_report   = MULTIQC_GLOBAL.out.report.map { _meta, report -> [report] }.toList() // channel: [ /path/to/multiqc_report.html ]
    grouped_reports = MULTIQC_PER_TAG.out.report.map { _meta, report -> [report] }.toList() // channel: [ /path/to/multiqc_report.html ]
}
