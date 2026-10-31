//
// Subworkflow with functionality specific to the nf-core/seqinspector pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 */

include { checkCondaChannels } from 'plugin/nf-core-utils'
include { checkConfigProvided } from 'plugin/nf-core-utils'
include { checkProfileProvided } from 'plugin/nf-core-utils'
include { completionEmail } from 'plugin/nf-core-utils'
include { completionSummary } from 'plugin/nf-core-utils'
include { dumpParametersToJSON } from 'plugin/nf-core-utils'
include { getWorkflowVersion } from 'plugin/nf-core-utils'
include { paramsHelp } from 'plugin/nf-schema'
include { paramsSummaryLog } from 'plugin/nf-schema'
include { paramsSummaryMap } from 'plugin/nf-schema'
include { samplesheetToList } from 'plugin/nf-schema'
include { validateParameters } from 'plugin/nf-schema'

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
    subsample_tools
    fasta
    kraken2_db
    riker_args

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

    def subsampled_info = ""
    if ('seqtk' in tools && subsample_tools) {
        if (subsample_tools.intersect(tools).sort()) {
            subsampled_info = "\033[0;34m  Tools on subsampled data  :\033[0;32m ${subsample_tools.intersect(tools).sort().join(",")} \033[0m\n"
        }
    }

    extra_text = """\033[1;37mExtra information\033[0m
\033[0;34m  Tools selected to be run  :\033[0;32m ${tools.join(",")} \033[0m
${subsampled_info}-\033[2m----------------------------------------------------\033[0m-
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
    validateInputParameters(tools, riker_args)
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

    if (!(fasta) && (("picard_collecthsmetrics" in tools) || ("picard_collectmultiplemetrics" in tools) || ("riker" in tools))) {
        log.warn("No fasta was provided, but picard or riker was requested")
        log.warn("BWAMEM2, SAMTOOLS, PICARD and RIKER processes will be skipped")
    }

    if ('toulligqc' in tools && 'emulate_amd64' in workflow.profile.tokenize(",")) {
        error("ToulligQC is not compatible with the 'emulate_amd64' profile. Please remove ToulligQC from the list of tools if you wish to run seqinspector on this architecture.")
    }

    if (!(kraken2_db) && ("kraken2" in tools)) {
        error("No kraken2_db was provided, but Kraken2 was requested")
    }

    emit:
    samplesheet = ch_samplesheet
    versions = ch_versions
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
                multiqc_reports.isBound() ? multiqc_reports.getVal() : [],
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
def validateInputParameters(tools, riker_args) {
    genomeExistsError()
    rikerHybcapError(tools, riker_args)
    rikerRnaCheck(tools, riker_args)
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
// Exit pipeline if riker hybcap is requested without bait/target intervals
//
def rikerHybcapError(tools, riker_args) {
    if ('riker' in tools && riker_args?.contains('hybcap') && (!params.bait_intervals || !params.target_intervals)) {
        error("riker_args contains 'hybcap' but --bait_intervals and --target_intervals were not provided. Both are required for hybcap metrics.")
    }
}

//
// Validate riker RNA metrics configuration: the gene model and the `rna` tool must be requested together
//
def rikerRnaCheck(tools, riker_args) {
    if (!('riker' in tools)) {
        return null
    }
    def rna_requested = riker_args?.contains('rna')
    if (rna_requested && !params.rna_gene_model) {
        error("riker_args contains 'rna' but --rna_gene_model was not provided. A gene model is required for RNA metrics.")
    }
    if (params.rna_gene_model && !rna_requested) {
        log.warn("--rna_gene_model was provided but riker_args does not request 'rna'; no RNA metrics will be produced. Add 'rna' to --riker_args to enable them.")
    }
}

//
// Generate methods description for MultiQC
//

def subsampledMethodsText(subsample_tools, tool_list) {
    def subsampled = (subsample_tools ?: []).intersect(tool_list).sort()
    return ('seqtk' in tool_list && subsampled)
        ? "The following tools were run on subsampled reads (via Seqtk): ${subsampled.join(', ')}."
        : ""
}

def defineToolsList(input_bundle, input_tools, input_skip, sample_size) {

    // Any tools in skip_tools will override any selection made via tools or tools_bundle

    if (sample_size < 0) {
        error("params.sample_size must be >= 0, got: ${sample_size}")
    }

    def bundle_list = input_bundle ? input_bundle.tokenize(',').sort().unique() : ['no_setup']
    def tools_list = input_tools ? input_tools.tokenize(',').sort().unique() : []
    def skip_list = input_skip ? input_skip.tokenize(',').sort().unique() : []

    // SEQTK_SAMPLE is run by default if params.sample_size > 0, and can therefore not be chose on it's own
    if (sample_size > 0) {
        tools_list << 'seqtk'
    }

    // The bundles are separated by platform, input data type or other. Platform bundles will include
    // a platform specific rundir parser, whereas the input type bundles are platform independent.
    // "Other" bundles may only work with specific data types or platforms.
    // If there are tools that are interchangable in their function, only one tool is included
    // in the bundle.
    // Future bundle types might focus on QC tools that are relevant for specific applications like RNAseq, ATACseq, etc.

    // please update the docs/usage.md section about tools selection when adding new tools here!

    // bundles by platform, will require platform to be specified in the sample sheet in order to parse the run folder information
    if ('illumina' in bundle_list) {
        tools_list << 'checkqc'
        tools_list << 'multiqcsav'
        tools_list << 'rundirparser'
        tools_list << 'fq_lint'
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
    }

    if ('ont' in bundle_list) {
        tools_list << 'fastqc'
        tools_list << 'sequali'
        tools_list << 'toulligqc'
        tools_list << 'rundirparser'
    }

    // future extension: PacBio, Element

    // bundles by data type (fastq, bam, etc.)
    if ('fastq' in bundle_list) {
        tools_list << 'fq_lint'
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'seqfu_stats'
    }

    if ('bam' in bundle_list) {
        tools_list << 'fastqc'
        tools_list << 'sequali'
    }

    // other
    if ('default' in bundle_list) {
        tools_list << 'fq_lint'
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
        tools_list << 'rundirparser'
        tools_list << 'seqfu_stats'
        tools_list << 'sequali'
    }

    if ('minimal' in bundle_list) {
        // fastqscreen is not compatible with bam file input
        // TODO: chain fastqscreen with a tool that translates bam to fastq in such cases
        tools_list << 'fastqc'
        tools_list << 'fastqscreen'
    }

    tools_list = tools_list.sort().unique() - skip_list

    return tools_list
}

def defineSubsampleToolsList(subsample_tools, tools) {

    def subsample_list = subsample_tools ? subsample_tools.tokenize(',').sort().unique() : []

    // "null" means no tools run on subsampled data
    if ('null' in subsample_list) {
        return []
    }

    // "all" means all active tools run on subsampled data (excluding tools that can't use subsampled data)
    if ('all' in subsample_list) {
        def excluded = ['seqtk', 'checkqc', 'multiqcsav', 'rundirparser']
        return [tools - excluded].sort()
    }

    // Picard tools share the same alignment step, so subsampling one implies the other
    if ('picard_collecthsmetrics' in tools && 'picard_collectmultiplemetrics' in tools) {
        if ('picard_collecthsmetrics' in subsample_tools || 'picard_collectmultiplemetrics' in subsample_tools) {
            subsample_list += ['picard_collecthsmetrics', 'picard_collectmultiplemetrics']
        }
        def count = 'picard_collecthsmetrics' in subsample_tools ? 1 : 0
        count += 'picard_collectmultiplemetrics' in subsample_tools ? 1 : 0
        if (count == 1) {
            log.warn("Only one of picard_collecthsmetrics or picard_collectmultiplemetrics was selected via subsample_tools. They share the same alignment step, so both will run on subsampled data.")
        }
    }

    // Only keep tools that are both in subsample_tools AND in the active tools list
    subsample_list = subsample_list.intersect(tools)

    return subsample_list.unique().sort()
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

//
// Generate MultiQC warning section for subsampled tools
//
def subsamplingNoticeYaml(subsample_tools, ran_tools) {
    def active_subsampled = subsample_tools.intersect(ran_tools).sort()

    def yaml_file_text = "id: 'subsampling-notice'\n" as String
    yaml_file_text += "section_name: 'Subsampling notice'\n"
    yaml_file_text += "section_href: 'https://github.com/${workflow.manifest.name}'\n"
    yaml_file_text += "description: 'Notice about tools run on subsampled data.'\n"
    yaml_file_text += "plot_type: 'html'\n"
    yaml_file_text += "data: |\n"

    if (active_subsampled) {
        yaml_file_text += "  <div class=\"alert alert-warning\">\n"
        yaml_file_text += "    <p>The following tools were run on subsampled reads (via Seqtk) instead of the full dataset:</p>\n"
        yaml_file_text += "    <table class=\"table table-sm\">\n"
        yaml_file_text += "      <thead><tr><th>Tool</th></tr></thead>\n"
        yaml_file_text += "      <tbody>\n"
        active_subsampled.each { tool ->
            yaml_file_text += "        <tr><td><b>${tool}</b></td></tr>\n"
        }
        yaml_file_text += "      </tbody>\n"
        yaml_file_text += "    </table>\n"
        yaml_file_text += "    <p><small>Results may differ from a full-data analysis. Check <a href='https://nf-co.re/seqinspector/docs/usage/#subsampling-control'>nf-co.re/seqinspector/docs/usage/#subsampling-control</a> for more information.</small></p>\n"
        yaml_file_text += "  </div>\n"
    }
    else {
        yaml_file_text += "  <div class=\"alert alert-info\">\n"
        yaml_file_text += "    <h4>Subsampling Info</h4>\n"
        yaml_file_text += "    <p>No tools were run on subsampled data. All tools processed the full dataset.</p>\n"
        yaml_file_text += "  </div>\n"
    }

    return yaml_file_text
}
