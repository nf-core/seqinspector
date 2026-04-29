//
// Subworkflow with functionality specific to the nf-core/seqinspector pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN   } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap        } from 'plugin/nf-schema'
include { samplesheetToList       } from 'plugin/nf-schema'
include { paramsHelp              } from 'plugin/nf-schema'
include { completionEmail         } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary       } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE   } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE } from '../../nf-core/utils_nextflow_pipeline'

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
    UTILS_NEXTFLOW_PIPELINE(
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1,
    )

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

    command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN(
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        before_text,
        after_text,
        command,
    )

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
    UTILS_NFCORE_PIPELINE(nextflow_cli_args)

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
    email //  string: email address
    email_on_fail //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    multiqc_report //  string: Path to MultiQC report

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
def toolCitationText() {
    def citation_text = [
        "Tools used in the workflow included:",
        "BWAMEM2 (Vasimuddin et al. 2019)",
        "FastQC (Andrews 2010),",
        "FastQ Screen (Wingett & Andrews 2018)",
        "MultiQC (Ewels et al. 2016),",
        "Picard Tool (Broad Institute 2019),",
        "SAMTOOLS (Danecek et al. 2021),",
        params.sample_size > 0 ? "Seqtk (Li 2021)," : "",
        "SeqFu (Telatin et al. 2021),",
        "Sequali (Vorderman 2025),",
        ".",
    ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    def reference_text = [
        "<li>Vasimuddin Md., Misra S., Li H, & Aluru S. (2019). Efficient Architecture-Aware Acceleration of BWA-MEM for Multicore Systems.</li>",
        "<li>Andrews S, (2010) FastQC, URL: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/.</li>",
        "<li>Wingett SW., & Andrews S. FastQ Screen: A tool for multi-genome mapping and quality control. F1000Res. 2018 Aug 24 [revised 2018 Jan 1];7:1338. doi: 10.12688/f1000research.15931.2. eCollection</li>",
        "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics, 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>",
        "<li>Broad Institute, (2019) Picard Tools, URL: https://broadinstitute.github.io/picard/.</li>",
        "<li>Danecek P., Bonfield JK., Liddle J., & al. (2021). Twelve years of SAMtools and BCFtools.</li>",
        params.sample_size > 0 ? "<li>Li, H. SeqTk. Available online: https://github.com/lh3/seqtk (accessed on 6 May 2021)</li>" : "",
        "<li>Telatin, A.; Fariselli, P.; Birolo, G. SeqFu: A Suite of Utilities for the Robust and Reproducible Manipulation of Sequence Files. Bioengineering 2021, 8, 59. https://doi.org/10.3390/bioengineering8050059</li>",
        "<li>Vorderman, R. Sequali: efficient and comprehensive quality control of short- and long-read sequencing data. Bioinformatics Advances, 2025. doi: 10.1093/bioadv/vbaf010</li>",
    ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    }
    else {
        meta["doi_text"] = ""
    }
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    meta["tool_bibliography"] = toolBibliographyText()

    def methods_text = mqc_methods_yaml.text

    def engine = new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}


def defineToolsList(input_bundle, input_tools, input_skip) {

    // SEQTK_SAMPLE is run by default if params.sample > 0, and can therefore not be chose on it's own
    // Any tools in skip_tools will override any selection made via tools or tools_bundle

    def bundle_list = input_bundle ? input_bundle.tokenize(',').sort().unique() : ['no_setup']
    def tools_list = input_tools ? input_tools.tokenize(',').sort().unique() : []
    def skip_list = input_skip ? input_skip.tokenize(',').sort().unique() : []

    // Current list actually used are default, minimal and promethion, we should probably always have a list `all`
    // The others are here as a showcase for what could be done

    // please update the docs/usage.md section about tools selection when adding new tools here!

    if ('all' in bundle_list) {
        tools_list << 'checkqc'
        tools_list << 'fastqc'
        tools_list << 'fastqe'
        tools_list << 'fastqscreen'
        tools_list << 'fq_lint'
        tools_list << 'multiqcsav'
        tools_list << 'picard_collecthsmetrics'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'rundirparser'
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
        tools_list << 'seqfu_stats'
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
