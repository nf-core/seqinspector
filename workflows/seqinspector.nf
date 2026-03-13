/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/


// modules
include { BWAMEM2_MEM                } from '../modules/nf-core/bwamem2/mem'
include { FASTP                      } from '../modules/nf-core/fastp'
include { FASTQC                     } from '../modules/nf-core/fastqc'
include { FASTQE                     } from '../modules/nf-core/fastqe'
include { FASTQSCREEN_FASTQSCREEN    } from '../modules/nf-core/fastqscreen/fastqscreen'
include { FQ_LINT                    } from '../modules/nf-core/fq/lint'
include { MULTIQC as MULTIQC_GLOBAL  } from '../modules/nf-core/multiqc'
include { MULTIQC as MULTIQC_PER_TAG } from '../modules/nf-core/multiqc'
include { MULTIQCSAV as MULTIQC_SAV  } from '../modules/nf-core/multiqcsav'
include { RUNDIRPARSER               } from '../modules/local/rundirparser'
include { SAMTOOLS_INDEX             } from '../modules/nf-core/samtools/index'
include { SEQFU_STATS                } from '../modules/nf-core/seqfu/stats'
include { SEQTK_SAMPLE               } from '../modules/nf-core/seqtk/sample'
include { TOULLIGQC                  } from '../modules/nf-core/toulligqc'

// subworkflow
include { PHYLOGENETIC_QC            } from '../subworkflows/local/phylogenetic_qc'
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
    tools
    target_intervals
    kraken2_db
    kraken2_save_reads
    kraken2_save_readclassifications

    main:
    ch_multiqc_files = channel.empty()
    ch_multiqc_extra_files = channel.empty()
    ch_global_reports = channel.empty()
    ch_sav_reports = channel.empty()

    //
    // MODULE: Run FQ_LINT to catch early errors
    //
    FQ_LINT(ch_samplesheet.filter { ("fq_lint" in tools) })

    if ("fq_lint" in tools) {
        // This catches all FASTQs that pass linting
        // If you use an error strategy that allows FQ_LINT to fail,
        // only valid FASTQ files will be passed to the next module
        ch_samplesheet = FQ_LINT.out.lint.join(ch_samplesheet).map { meta, _fq_lint, reads -> [meta, reads] }
    }

    //
    // MODULE: Parse rundir info
    //
    if ('rundirparser' in tools) {

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
            .flatMap { rundir, metas ->
                // Collect all unique tags into a list
                def all_tags = metas.collect { meta -> meta.tags }.flatten().unique()
                // Create a new meta object whose attributes are...
                //  1. tags: The list of merged tags, used for grouping MultiQC reports
                //  2. dirname: The simple name of the rundir, used for setting unique output names in publishDir
                def dir_meta = [tags: all_tags, dirname: rundir.simpleName]
                // Return the new structure, to...
                //  1. Feed into rundir specific processes
                //  2. Mix with the ch_multiqc_files channel downstream
                [[dir_meta, rundir]]
            }
        ch_rundir.count().view()
        // remove this

        ch_rundir.ifEmpty {
            log.warn("No samples with rundir found, skipping RUNDIRPARSER")
        }

        RUNDIRPARSER(ch_rundir)

        ch_multiqc_files = ch_multiqc_files.mix(RUNDIRPARSER.out.multiqc)
    }

    //
    // MODULE: Determine whether to run Multiqc_global or Multiqc_sav
    //

    if ('multiqcsav' in tools) {
        // Determine if we need global MultiQC based on conditions
        ch_need_global = ch_rundir_branch.without_rundir
            .count()
            .combine(ch_rundir.count())
            .map { samples_without, rundir_count ->
                def need_global = (samples_without > 0) || (rundir_count > 1) || (rundir_count == 0)
                log.info("need_global.....${need_global}")
                if (need_global) {
                    if (samples_without > 0) {
                        log.warn("Samples without rundir found, will run global MultiQC instead")
                    }
                    if (rundir_count > 1) {
                        log.warn("More than one rundir found, will run global MultiQC instead")
                    }
                    if (rundir_count == 0) {
                        log.warn("No samples with rundir found, will run global MultiQC instead")
                    }
                }
                return need_global ? "run_global" : "run_sav"
            }
    }

    ch_need_global
        .branch { need_global ->
            run_global: need_global == "run_global"
            run_sav: need_global == "run_sav"
        }
        .set { ch_multiqc_decision }

    //
    // MODULE: Run Seqtk sample
    //

    SEQTK_SAMPLE(ch_samplesheet.map { meta, reads -> [meta, reads, sample_size] }.filter { sample_size })

    ch_sample = sample_size ? SEQTK_SAMPLE.out.reads : ch_samplesheet

    //
    // MODULE: Run FastQC on subsampled reads
    //
    FASTQC(ch_sample.filter { 'fastqc' in tools })

    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)

    // FASTQE
    FASTQE(ch_sample.filter { 'fastqe' in tools })

    ch_multiqc_files = ch_multiqc_files.mix(FASTQE.out.tsv)

    //
    // MODULE: Run fastp for adapter trimming and quality filtering
    //

    FASTP(
        ch_sample.map { meta, reads -> [meta, reads, []] }.filter { 'fastp' in tools },
        true,
        false,
        false,
    )

    ch_multiqc_files = ch_multiqc_files.mix(FASTP.out.json)

    // ch_trimmed = 'fastp' in tools ? FASTP.out.reads : ch_sample

    //
    // Module: Run SeqFu stats
    //
    SEQFU_STATS(ch_samplesheet.map { meta, reads -> [[id: "seqfu", sample_id: meta.id, tags: meta.tags], reads] }.filter { 'seqfu_stats' in tools })

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

    //
    // MODULE: Run FastQ Screen
    //

    // Parse the reference info needed to create a FastQ Screen config file
    // and transpose it into a tuple containing lists for each property

    FASTQSCREEN_FASTQSCREEN(
        ch_sample.filter { 'fastqscreen' in tools },
        channel.fromList(
            samplesheetToList(
                fastq_screen_references,
                "${projectDir}/assets/schema_fastq_screen_references.json",
            )
        ).toList().transpose().toList(),
    )

    ch_multiqc_files = ch_multiqc_files.mix(FASTQSCREEN_FASTQSCREEN.out.txt)

    // MODULE: Align reads with BWA-MEM2
    def sort_bam = true
    // we always sort bam
    BWAMEM2_MEM(
        ch_sample.filter { ('picard_collecthsmetrics' in tools) || ('picard_collectmultiplemetrics' in tools) },
        bwamem2_index,
        fasta_reference,
        sort_bam,
    )

    SAMTOOLS_INDEX(BWAMEM2_MEM.out.bam)

    ch_bam_bai = BWAMEM2_MEM.out.bam.join(SAMTOOLS_INDEX.out.index, failOnDuplicate: true, failOnMismatch: true)

    QC_BAM(
        ch_bam_bai,
        fasta_reference,
        ref_fai,
        bait_intervals ? channel.fromPath(bait_intervals).collect() : channel.empty(),
        target_intervals ? channel.fromPath(target_intervals).collect() : channel.empty(),
        ref_dict,
        tools,
    )

    ch_multiqc_files = ch_multiqc_files.mix(QC_BAM.out.multiple_metrics, QC_BAM.out.hs_metrics)

    //
    // SUBWORKFLOW: Run kraken2 and produce krona plots
    //

    if ('kraken2' in tools) {
        PHYLOGENETIC_QC(
            ch_samplesheet,
            kraken2_db,
            kraken2_save_reads,
            kraken2_save_readclassifications,
        )
        ch_multiqc_files = ch_multiqc_files.mix(PHYLOGENETIC_QC.out.mqc)
    }

    //
    // MODULE: Run ToulligQC
    //

    // This provides useful stats of long reads

    TOULLIGQC(ch_samplesheet.filter { "toulligqc" in tools })

    ch_multiqc_files.mix(TOULLIGQC.out.report_data)

    //
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

    ch_global_input = ch_multiqc_files
        .map { _meta, files -> [files] }
        .flatten()
        .collect()
        .combine(ch_multiqc_extra_files_global.collect())
        .map { files ->
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
    log.info("ch_global_input.... ${ch_global_input}")
    // Run global MultiQC only when needed
    ch_global_reports = ch_multiqc_decision.run_global.view { it -> log.info("globsl decision.... ${it}") }.filter { decision ->
        decision
            == "run_global"
    }.concat(ch_global_input.collect()).last().view { it -> log.info("final global files.....${it}") }
        | MULTIQC_GLOBAL

    ch_sav_input = ch_rundir
        .map { metas, rundir ->
            log.info("metas, rundir......${metas}....${rundir}")
            def xml = []
            def interop = []

            rundir.eachFileRecurse { file ->
                if (file.fileName.toString() in ['RunInfo.xml', 'RunParameters.xml']) {
                    xml << file
                }
                else if (file.parent.name == 'InterOp' && file.fileName.toString().endsWith(".bin")) {
                    interop << file
                }
            }
            log.info("xml, interop......${xml}....${interop[0]}")
            return [metas, xml, interop]
        }
        .combine(
            ch_multiqc_files.map { _meta, files -> files }.flatten().collect().combine(ch_multiqc_extra_files_global.collect()).map { files -> [files.flatten()] }
        )
        .map { meta, xml, interop, extra_files ->
            return [
                meta,
                xml,
                interop,
                extra_files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }

    log.info("sav ch_sav_input.collect() ...${ch_sav_input.collect()}")
    // Run SAV MultiQC only when needed
    ch_sav_reports = ch_multiqc_decision.run_sav.view { it -> log.info("sav decision ...${it}") }.filter { decision ->
        decision
            == "run_sav"
    }.combine(
        ch_sav_input.map { _decision, files ->
            log.info("Passing files to MULTIQC_SAV:............. ${files}")
            return files
        }
    ).view { it -> log.info("final sav files.....${it}") }
        | MULTIQC_SAV


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
    global_report   = ch_global_reports.report.mix(ch_sav_reports.report).map { _meta, report -> [report] }.toList() // channel: [ /path/to/multiqc_report.html ]
    grouped_reports = MULTIQC_PER_TAG.out.report.map { _meta, report -> [report] }.toList() // channel: [ /path/to/multiqc_report.html ]
}
