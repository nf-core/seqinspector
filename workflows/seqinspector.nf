/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// modules
include { BWAMEM2_MEM                  } from '../modules/nf-core/bwamem2/mem'
include { CHECKQC                      } from '../modules/nf-core/checkqc'
include { FASTP                        } from '../modules/nf-core/fastp'
include { FASTQC                       } from '../modules/nf-core/fastqc'
include { FASTQE                       } from '../modules/nf-core/fastqe'
include { FASTQSCREEN_FASTQSCREEN      } from '../modules/nf-core/fastqscreen/fastqscreen'
include { FQ_LINT                      } from '../modules/nf-core/fq/lint'
include { MULTIQC as MULTIQC_PER_TAG   } from '../modules/nf-core/multiqc'
include { MULTIQCSAV as MULTIQC_GLOBAL } from '../modules/nf-core/multiqcsav'
include { RUNDIRPARSER                 } from '../modules/local/rundirparser'
include { SAMTOOLS_INDEX               } from '../modules/nf-core/samtools/index'
include { SEQFU_STATS                  } from '../modules/nf-core/seqfu/stats'
include { SEQTK_SAMPLE                 } from '../modules/nf-core/seqtk/sample'
include { SEQUALI                      } from '../modules/nf-core/sequali/main'
include { TOULLIGQC                    } from '../modules/nf-core/toulligqc'

// subworkflow
include { BAM_QC                       } from '../subworkflows/local/bam_qc'
include { FASTQ_QC_PHYLOGENETIC        } from '../subworkflows/local/fastq_qc_phylogenetic'

// functions
include { methodsDescriptionText       } from '../subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { paramsSummaryMap             } from 'plugin/nf-schema'
include { paramsSummaryMultiqc         } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { reportIndexMultiqc           } from '../subworkflows/local/utils_nfcore_seqinspector_pipeline'
include { samplesheetToList            } from 'plugin/nf-schema'
include { softwareVersionsToYAML       } from 'plugin/nf-core-utils'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SEQINSPECTOR {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    bait_intervals
    bwamem2
    checkqc_config
    fasta
    fastq_screen_references
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir
    dict
    fai
    sample_size
    tools
    target_intervals
    kraken2_db
    kraken2_save_reads
    kraken2_save_readclassifications

    main:
    ch_multiqc_files = channel.empty()
    ch_multiqc_extra_files = channel.empty()

    // STEP 00: EARLY SKIP FAILING MALFORMED FASTQ FILES

    //
    // MODULE: Run FQ_LINT to catch early errors
    //

    FQ_LINT(ch_samplesheet.filter { ('fq_lint' in tools) })

    // This catches all FASTQs that pass linting
    // If you use an error strategy that allows FQ_LINT to fail,
    // only valid FASTQ files will be passed to the next module
    ch_samplesheet = 'fq_lint' in tools
        ? FQ_LINT.out.lint.join(ch_samplesheet).map { meta, _process, _tool, _fq_lint, reads -> [meta, reads] }
        : ch_samplesheet

    // STEP 01: ILLUMINA RUNDIR INFORMATION

    // Parse RUNDIR INFO

    // Calculate the global rundir_number for the entire samplesheet
    rundir_number = ch_samplesheet
        .map { meta, _reads -> [meta.rundir ? meta.rundir.simpleName : 'no_rundir'] }
        .flatten()
        .unique()
        .collect()
        .map { rundir -> [rundir.size()] }

    ch_rundir = ch_samplesheet
        .map { meta, _reads -> [meta.rundir ?: null, meta] }
        .groupTuple()
        .combine(rundir_number)
        .map { rundir, meta, _rundir_number ->
            // Return for all the rundir specific processes and to mix with ch_multiqc_files
            //   - meta: (map)
            //     - id: Simple name of the rundir, used for setting unique output names in publishDir
            //     - samples: List all sample of the rundir
            //     - rundir_number: number of total rundir, no rundir counts as one
            //     - tags: List of merged tags, used for grouping MultiQC reports
            //   - rundir: path to rundir or null when no rundir
            [
                [
                    id: rundir ? rundir.simpleName : 'no_rundir',
                    samples: rundir ? false : meta.collect { meta_ -> meta_.id }.flatten().unique().sort(),
                    rundir_number: _rundir_number,
                    tags: meta.collect { meta_ -> meta_.tags }.flatten().unique(),
                ],
                rundir ? file(rundir, checkIfExists: true) : null,
            ]
        }

    // Log warnings for samples without rundir
    if (('checkqc' in tools) || ('multiqcsav' in tools) || ('rundirparser' in tools)) {
        ch_rundir.map { meta, rundir ->
            if (!rundir) {
                log.warn("No rundir for sample(s): ${meta.samples.join(', ')}")
            }
        }

        if ('checkqc' in tools) {
            ch_rundir
                .filter { _meta, rundir -> rundir }
                .ifEmpty { log.warn("No samples with rundir found, skipping CHECKQC") }
        }

        if ('multiqcsav' in tools) {
            // To get multiQC to run even when no tools are being run
            if (tools.size == 1) {
                ch_multiqc_files = ch_multiqc_files.mix(ch_rundir.map { meta, _rundir -> [meta, []] })
            }

            ch_rundir
                .filter { _meta, rundir -> rundir }
                .ifEmpty { log.warn("No samples with rundir found, skipping MULTIQC_SAV") }
        }

        if ('rundirparser' in tools) {
            ch_rundir
                .filter { _meta, rundir -> rundir }
                .ifEmpty { log.warn("No samples with rundir found, skipping RUNDIRPARSER") }
        }
    }

    //
    // MODULE: CHECKQC
    //

    CHECKQC(
        ch_rundir.filter { _meta, rundir -> (rundir && 'checkqc' in tools) },
        checkqc_config
            ? file(checkqc_config, checkIfExists: true)
            : [],
    )

    //
    // MODULE: RUNDIRPARSER
    //

    RUNDIRPARSER(ch_rundir.filter { _meta, rundir -> (rundir && 'rundirparser' in tools) })

    // STEP 01: LONGREADS

    //
    // MODULE: TOULLIGQC
    // This provides useful stats of long reads

    TOULLIGQC(ch_samplesheet.filter { 'toulligqc' in tools })

    // STEP 02: BASIC QC ON FASTQ FILES

    //
    // MODULE: SEQFU_STATS
    //

    SEQFU_STATS(ch_samplesheet.filter { 'seqfu_stats' in tools })

    // Parse the stats TSV file
    SEQFU_STATS.out.stats
        .splitCsv(header: true, sep: '\t')
        .map { meta, row ->
            // Check if requested sample size exceeds available reads
            def sample_reads = row['#Seq'].toInteger()
            if (sample_size > sample_reads) {
                log.warn("${meta.id}: Requested sample_size (${sample_size}) is larger than available reads (${sample_reads}). Pipeline will continue with ${sample_reads} reads.")
            }
        }

    // STEP 03: SUBSAMPLE

    //
    // MODULE: SEQTK_SAMPLE
    // Any downstream tool will be run on subsampled reads if seqtk is run
    //

    SEQTK_SAMPLE(ch_samplesheet.map { meta, reads -> [meta, reads, sample_size] }.filter { sample_size })
    ch_sample = sample_size ? SEQTK_SAMPLE.out.reads : ch_samplesheet

    // STEP 04: MORE QC ON FASTQ FILES (CAN BE SUMSAMPLED)

    FASTQC(ch_sample.filter { 'fastqc' in tools })

    FASTQE(ch_sample.filter { 'fastqe' in tools })

    //
    // MODULE: FASTP for adapter trimming and quality filtering
    //   Default behavior we currently don't support

    def discard_trimmed_pass = true
    def save_trimmed_fail = false
    def save_merged = false

    FASTP(
        ch_sample.map { meta, reads -> [meta, reads, []] }.filter { 'fastp' in tools },
        discard_trimmed_pass,
        save_trimmed_fail,
        save_merged,
    )

    //
    // MODULE: SEQUALI
    //
    
    SEQUALI (
        ch_sample.map {
            meta, reads -> [meta, reads]
        }.filter { 'sequali' in tools }
    )

    // STEP 05: FASTQSCREEN

    //
    // MODULE: Run FASTQSCREEN
    //   Parse the reference info needed to create a FastQ Screen config file
    //   and transpose it into a tuple containing lists for each property

    FASTQSCREEN_FASTQSCREEN(
        ch_sample.filter { 'fastqscreen' in tools },
        channel.fromList(
            samplesheetToList(
                fastq_screen_references,
                "${projectDir}/assets/schema_fastq_screen_references.json",
            )
        ).toList().transpose().toList(),
    )

    // STEP 06: METAGENOMIC QC

    //
    // SUBWORKFLOW: FASTQ_QC_PHYLOGENETIC
    //   Run KRAKEN2 and produce KRONA plots

    if ('kraken2' in tools) {
        FASTQ_QC_PHYLOGENETIC(
            ch_sample,
            kraken2_db,
            kraken2_save_reads,
            kraken2_save_readclassifications,
        )
    }

    // STEP 07: fastq AND QC ON BAM FILES

    //
    // MODULE: BWAMEM2_MEM to align reads
    //   Always sort bam

    def sort_bam = true

    BWAMEM2_MEM(
        ch_sample.filter { ('picard_collecthsmetrics' in tools) || ('picard_collectmultiplemetrics' in tools) },
        bwamem2,
        fasta,
        sort_bam,
    )

    //
    // MODULE: SAMTOOLS_INDEX to create BAM index
    //

    SAMTOOLS_INDEX(BWAMEM2_MEM.out.bam)

    bam_bai = BWAMEM2_MEM.out.bam.join(SAMTOOLS_INDEX.out.index, failOnDuplicate: true, failOnMismatch: true)

    //
    // SUBWORKFLOW: BAM_QC
    //   Run picard_collecthsmetrics and/or picard_collectmultiplemetrics

    BAM_QC(
        bam_bai,
        fasta,
        fai,
        bait_intervals ? channel.fromPath(bait_intervals).collect() : channel.empty(),
        target_intervals ? channel.fromPath(target_intervals).collect() : channel.empty(),
        dict,
        tools,
    )

    // Collate and save software versions
    def collated_versions = softwareVersionsToYAML(
        softwareVersions: channel.topic("versions"),
        nextflowVersion: workflow.nextflow.version,
    ).collectFile(
        storeDir: "${outdir}/pipeline_info",
        name: 'nf_core_' + 'seqinspector_software_' + 'mqc_' + 'versions.yml',
        sort: true,
        newLine: true,
    )

    def collated_reports = channel.topic("multiqc_files")
        .map { meta, _process, _tool, reports -> [meta, reports] }

    // STEP 08: MULTIQC (GLOBAL USING SAV AND PER TAG)

    //
    // MODULE: MultiQC
    //

    ch_multiqc_files = ch_multiqc_files.mix(collated_reports)
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

    //
    // Run MultiQC for all samples with SAV plugin
    // tuple  val(meta), path(xml), path(interop_bin, stageAs: "InterOp/*"), path(extra_multiqc_files, stageAs: "?/*"), path(multiqc_config, stageAs: "?/*"), path(multiqc_logo), path(replace_names), path(sample_names)
    //

    ch_multiqc_global_files = ch_multiqc_files
        .map { _meta, files -> [files] }
        .collect()
        .combine(ch_multiqc_extra_files_global.collect())
        .map { files -> [[id: 'seqinspector'], files] }

    MULTIQC_GLOBAL(
        ch_rundir.map { meta, rundir ->
            def xml = []
            def interop = []

            if ((rundir) && ('multiqcsav' in tools)) {
                if (meta.rundir_number > 1) {
                    log.warn("More than one rundir, or sample(s) missing rundir, skipping MULTIQC_SAV")
                }
                else if (rundir.toString().endsWith('tar.gz')) {
                    log.warn("Rundir: ${meta.id} is a tar.gz")
                }
                else {
                    interop = files(file(rundir).resolve("InterOp/*.bin"), checkIfExists: true)
                    xml = files(file(rundir).resolve("*.xml"), checkIfExists: true)
                }
            }
            return [[id: 'seqinspector'], xml, interop]
        }.join(ch_multiqc_global_files, by: 0).map { meta, xml, interop, multiqc_files ->
            def final_xml = xml.flatten().unique()
            def final_interop = interop.flatten().unique()
            return [
                meta,
                final_xml,
                final_interop,
                multiqc_files.flatten().unique(),
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    // Group samples by tag

    multiqc_extra_files_per_tag = ch_tags.combine(
        ch_multiqc_extra_files.mix(
            ch_tags.toList().map { tag_list -> reportIndexMultiqc(tag_list, false) }.collectFile(name: 'multiqc_index_mqc.yaml')
        )
    )

    ch_multiqc_per_tag_files = ch_tags
        .combine(ch_multiqc_files)
        .filter { sample_tag, meta, _sample -> sample_tag in meta.tags }
        .map { sample_tag, _meta, sample -> [sample_tag, sample] }
        .mix(multiqc_extra_files_per_tag)
        .groupTuple()
        .tap { mqc_by_tag }
        .collectFile { sample_tag, _samples ->
            [
                "${sample_tag}_multiqc_extra_config.yml",
                """
                    |output_fn_name: \"${sample_tag}_multiqc_report.html\"
                    |data_dir_name:  \"${sample_tag}_multiqc_data\"
                    |plots_dir_name: \"${sample_tag}_multiqc_plots\"
                """.stripMargin(),
            ]
        }
        .map { file -> [(file.getName() =~ /(.+?)_multiqc/)[0][1], file] }
        .join(mqc_by_tag)

    //
    // Run MultiQC per tag
    //

    MULTIQC_PER_TAG(
        ch_multiqc_per_tag_files.map { sample_tag, config, files ->
            [
                [id: sample_tag],
                files.flatten(),
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
    bam_bai       = bam_bai
    data_global   = MULTIQC_GLOBAL.out.data // channel: [ /path/to/multiqc_data/ ]
    data_groups   = MULTIQC_PER_TAG.out.data // channel: [ /path/to/multiqc_data/ ]
    plots_global  = MULTIQC_GLOBAL.out.plots // channel: [ /path/to/multiqc_plots/ ]
    plots_groups  = MULTIQC_PER_TAG.out.plots // channel: [ /path/to/multiqc_plots/ ]
    report_global = MULTIQC_GLOBAL.out.report // channel: [ /path/to/multiqc_report.html ]
    report_groups = MULTIQC_PER_TAG.out.report // channel: [ /path/to/multiqc_report.html ]
    subsampled    = SEQTK_SAMPLE.out.reads
}
