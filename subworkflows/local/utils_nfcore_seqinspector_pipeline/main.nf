//
// Subworkflow with functionality specific to the nf-core/seqinspector pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { checkCondaChannels   } from 'plugin/nf-core-utils'
include { checkConfigProvided  } from 'plugin/nf-core-utils'
include { checkProfileProvided } from 'plugin/nf-core-utils'
include { completionEmail      } from 'plugin/nf-core-utils'
include { completionSummary    } from 'plugin/nf-core-utils'
include { dumpParametersToJSON } from 'plugin/nf-core-utils'
include { getWorkflowVersion   } from 'plugin/nf-core-utils'
include { paramsHelp           } from 'plugin/nf-schema'
include { paramsSummaryLog     } from 'plugin/nf-schema'
include { paramsSummaryMap     } from 'plugin/nf-schema'
include { samplesheetToList    } from 'plugin/nf-schema'
include { validateParameters   } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {
    take:
    version // boolean: Display version and exit
    validate_params // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir //  string: The output directory where the results will be saved
    input //  string: Path to input samplesheet
    help // boolean: Display help message and exit
    help_full // boolean: Show the full help message
    show_hidden // boolean: Show hidden parameters in the help message
    tools
    fasta
    kraken2_db

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    if (version) {
        log.info("${workflow.manifest.name} ${getWorkflowVersion()}")
        System.exit(0)
    }
    if (outdir) {
        dumpParametersToJSON(outdir, params)
    }
    if (workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1) {
        checkCondaChannels()
    }

    //
    // Validate parameters and generate parameter summary to stdout
    //

    def before_text = ""
    def extra_text = ""
    def after_text = ""
    before_text = """
-\033[2m----------------------------------------------------\033[0m-
                                        \033[0;32m,--.\033[0;30m/\033[0;32m,-.\033[0m
\033[0;34m        ___     __   __   __   ___     \033[0;32m/,-._.--~\'\033[0m
\033[0;34m  |\\ | |__  __ /  ` /  \\ |__) |__         \033[0;33m}  {\033[0m
\033[0;34m  | \\| |       \\__, \\__/ |  \\ |___     \033[0;32m\\`-._,-`-,\033[0m
                                        \033[0;32m`._,._,\'\033[0m
\033[0;35m  nf-core/seqinspector ${workflow.manifest.version}\033[0m
-\033[2m----------------------------------------------------\033[0m-
"""
    after_text = """${workflow.manifest.doi ? "\n* The pipeline\n" : ""}${workflow.manifest.doi.tokenize(",").collect { doi -> "    https://doi.org/${doi.trim().replace('https://doi.org/', '')}" }.join("\n")}${workflow.manifest.doi ? "\n" : ""}
* The nf-core framework
    https://doi.org/10.1038/s41587-020-0439-x

* Software dependencies
    https://github.com/nf-core/seqinspector/blob/master/CITATIONS.md
"""
    if (monochrome_logs) {
        before_text = before_text.replaceAll(/\033\[[0-9;]*m/, '')
    }

    def command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    if (help || help_full) {
        log.info(
            paramsHelp(
                [
                    beforeText: before_text,
                    afterText: after_text,
                    command: command,
                    showHidden: show_hidden,
                    fullHelp: help_full,
                ],
                (help instanceof String && help != "true") ? help : "",
            )
        )
        System.exit(0)
    }

    log.info(before_text)
    log.info(paramsSummaryLog(workflow, parameters_schema: "nextflow_schema.json"))
    log.info(after_text)

    if (validate_params) {
        validateParameters(parameters_schema: "nextflow_schema.json")
    }

    extra_text = """
\033[1;37mExtra informations\033[0m
\033[0;34m  Tools selected to be run  :\033[0;32m ${tools.join(",")} \033[0m
-\033[2m----------------------------------------------------\033[0m-
"""

    if (monochrome_logs) {
        extra_text = extra_text.replaceAll(/\033\[[0-9;]*m/, '')
    }

    log.info(extra_text)

    //
    // Check config provided to the pipeline
    //
    checkConfigProvided()
    checkProfileProvided(nextflow_cli_args, monochrome_logs)

    //
    // Custom validation for pipeline parameters
    //
    validateInputParameters()
    // Runs additional validation that is not done by $projectDir/nextflow_schema.json

    //
    // Create channel from input file provided through params input
    //
    nr_samples = channel.fromList(samplesheetToList(input, "${projectDir}/assets/schema_input.json"))
        .toList()
        .size()

    ch_samplesheet = channel.fromList(samplesheetToList(input, "${projectDir}/assets/schema_input.json"))
        .toList()
        .flatMap { item -> item.withIndex().collect { entry, idx -> entry + "${idx + 1}" } }
        .map { meta, fastq_1, fastq_2, idx ->
            def tags = meta.tags ? meta.tags.tokenize(":") : []
            def pad_positions = [nr_samples.length(), 2].max()
            def zero_padded_idx = idx.padLeft(pad_positions, "0")
            def new_meta = [id: "${meta.sample}_${zero_padded_idx}"]
            return [
                new_meta.id,
                meta + [id: new_meta.id, tags: tags, single_end: fastq_2 ? false : true],
                fastq_2 ? [fastq_1, fastq_2] : [fastq_1],
            ]
        }
        .groupTuple()
        .map { meta -> validateInputSamplesheet(meta) }
        .transpose()

    ch_samplesheet
        .map { meta, _fastqs ->
            [meta.tags]
        }
        .flatten()
        .unique()
        .map { tag -> [tag.toLowerCase(), tag] }
        .groupTuple()
        .map { _tag_lowercase, tags ->
            if (tags.size() != 1) {
                log.warn("Tag name collision: " + tags)
                log.warn("On a MacOS system these tags will be considered as one")
            }
        }

    if (!(fasta) && (("picard_collecthsmetrics" in tools) || ("picard_collectmultiplemetrics" in tools))) {
        log.warn("No fasta was provided, but picard was requested")
        log.warn("BWAMEM2, SAMTOOLS and PICARD processes, will be skipped")
    }

    if ('toulligqc' in tools && 'emulate_amd64' in workflow.profile.tokenize(",")) {
        error("ToulligQC is not compatible with the 'emulate_amd64' profile. Please remove ToulligQC from the list of tools if you wish to run seqinspector on this architecture.")
    }

    if (!(kraken2_db) && ("kraken2" in tools)) {
        error("No kraken2_db was provided, but Kraken2 was requested")
    }

    emit:
    samplesheet = ch_samplesheet
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {
    take:
    email // string: email address
    email_on_fail // string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir // path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    multiqc_report // string: Path to MultiQC report

    main:
    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def multiqc_reports = multiqc_report.toList()

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(
                summary_params,
                email,
                email_on_fail,
                plaintext_email,
                outdir,
                monochrome_logs,
                multiqc_reports.getVal(),
            )
        }

        completionSummary(monochrome_logs)
    }

    workflow.onError {
        log.error("Pipeline failed. Please refer to troubleshooting docs for common issues: https://nf-co.re/docs/running/troubleshooting")
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
//
// Check and validate pipeline parameters
//
def validateInputParameters() {
    genomeExistsError()
}

//
// Validate channels from input samplesheet
//
def validateInputSamplesheet(input) {
    def (metas, fastqs) = input[1..2]

    // Check that multiple runs of the same sample are of the same datatype i.e. single-end / paired-end
    def endedness_ok = metas.collect { meta -> meta.single_end }.unique().size == 1
    if (!endedness_ok) {
        error("Please check input samplesheet -> Multiple runs of a sample must be of the same datatype i.e. single-end or paired-end: ${metas[0].id}")
    }

    return [metas[0], fastqs]
}

//
// Exit pipeline if incorrect --genome key provided
//
def genomeExistsError() {
    if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
        def error_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" + "  Genome '${params.genome}' not found in any config files provided to the pipeline.\n" + "  Currently, the available genome keys are:\n" + "  ${params.genomes.keySet().join(", ")}\n" + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        error(error_string)
    }
}

//
// Generate methods description for MultiQC
//

def defineToolsList(input_bundle, input_tools, input_skip, sample_size) {

    // Any tools in skip_tools will override any selection made via tools or tools_bundle

    def bundle_list = input_bundle ? input_bundle.tokenize(',').sort().unique() : ['no_setup']
    def tools_list = input_tools ? input_tools.tokenize(',').sort().unique() : []
    def skip_list = input_skip ? input_skip.tokenize(',').sort().unique() : []

    // SEQTK_SAMPLE is run by default if params.sample_size > 0, and can therefore not be chose on it's own
    if (sample_size > 0) {
        tools_list << 'seqtk_sample'
    }

    // Current list actually used are default, minimal and promethion, we should probably always have a list `all`
    // The others are here as a showcase for what could be done

    // please update the docs/usage.md section about tools selection when adding new tools here!

    if ('all' in bundle_list) {
        tools_list << 'bbmap_clumpify'
        tools_list << 'checkqc'
        tools_list << 'fastqc'
        tools_list << 'fastqe'
        tools_list << 'fastqscreen'
        tools_list << 'fq_lint'
        tools_list << 'multiqcsav'
        tools_list << 'picard_collecthsmetrics'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'rundirparser'
        tools_list << 'seqkit_stats'
        tools_list << 'seqfu_stats'
        tools_list << 'sequali'
        tools_list << 'toulligqc'
    }
    if ('bam' in bundle_list) {
        tools_list << 'picard_collecthsmetrics'
        tools_list << 'picard_collectmultiplemetrics'
    }
    if ('fastq' in bundle_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'fq_lint'
        tools_list << 'seqkit_stats'
    }
    if ('default' in bundle_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'fq_lint'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'rundirparser'
        tools_list << 'seqfu_stats'
        tools_list << 'sequali'
    }
    if ('illumina' in bundle_list) {
        tools_list << 'checkqc'
        tools_list << 'multiqcsav'
        tools_list << 'rundirparser'
        tools_list << 'seqfu_stats'
    }
    if ('minimal' in bundle_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'seqfu_stats'
    }
    if ('ont' in bundle_list) {
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'seqkit_stats'
        tools_list << 'sequali'
        tools_list << 'toulligqc'
    }

    tools_list = tools_list.sort().unique() - skip_list

    return tools_list
}

//
// Generate report index for MultiQC
//
def reportIndexMultiqc(tags, global = true) {
    def relative_path = global ? ".." : "../.."

    def a_attrs = "target=\"_blank\" class=\"list-group-item list-group-item-action\""

    // Global report path
    def index_section = "    <a href=\"${relative_path}/global_report/multiqc_report.html\" ${a_attrs}>Global report</a>\n"

    // Group report paths
    tags.each { tag ->
        index_section += "    <a href=\"${relative_path}/group_reports/${tag}/multiqc_report.html\" ${a_attrs}>Group report: ${tag}</a>\n"
    }

    def yaml_file_text = "id: '${workflow.manifest.name.replace('/', '-')}-index'\n" as String
    yaml_file_text += "description: 'MultiQC reports collected from running the pipeline.'\n"
    yaml_file_text += "section_name: '${workflow.manifest.name} MultiQC Reports Index'\n"
    yaml_file_text += "section_href: 'https://github.com/${workflow.manifest.name}'\n"
    yaml_file_text += "plot_type: 'html'\n"
    yaml_file_text += "data: |\n"
    yaml_file_text += "  <h4>Reports</h4>\n"
    yaml_file_text += "  <p>Select a report to view (open in a new tab):</p>\n"
    yaml_file_text += "  <div class=\"list-group\">\n"
    yaml_file_text += "${index_section}"
    yaml_file_text += "  </div>\n"

    return yaml_file_text
}
