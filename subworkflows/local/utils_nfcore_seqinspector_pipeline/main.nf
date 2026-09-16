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
    subsample_tools
    fasta
    kraken2_db
    riker_args

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
        false,
    )

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
    UTILS_NFCORE_PIPELINE(nextflow_cli_args)

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
        return
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

def toolReferencesMap() {
    return [
        'bbmap': ['name': 'BBMap', 'authors': 'Bushnell B. (2014).', 'authors_short': 'Bushnell 2014', 'description': 'BBMap: A Fast, Accurate, Splice-Aware Aligner.', 'url': 'https://bbmap.org/'],
        'bwamem2': ['name': 'BWAMEM2', 'authors': 'Vasimuddin Md., Misra S., Li H, & Aluru S. (2019).', 'authors_short': 'Vasimuddin et al. 2019', 'description': 'Efficient Architecture-Aware Acceleration of BWA-MEM for Multicore Systems.', 'doi': '10.1109/IPDPS.2019.00041'],
        'checkqc': ['name': 'checkQC', 'authors': 'Åslin et al., (2018).', 'authors_short': 'Åslin et al. 2018', 'description': 'CheckQC: Quick quality control of Illumina sequencing runs. Journal of Open Source Software, 3(22), 556.', 'doi': '10.21105/joss.00556'],
        'chelae': ['name': 'Chelae', 'authors': '', 'authors_short': '', 'description': 'A fast toolkit for trimming and filtering short-read FASTQ data.', 'url': 'https://github.com/fulcrumgenomics/chelae'],
        'fastp': ['name': 'Fastp', 'authors': 'Chen S., Zhou Y., Chen Y., & Gu J. (2018).', 'authors_short': 'Chen et al. 2018', 'description': 'fastp: an ultra-fast all-in-one FASTQ preprocessor. Bioinformatics, 34(17), i884-i890.', 'doi': '10.1093/bioinformatics/bty560'],
        'fastqc': ['name': 'FastQC', 'authors': '', 'authors_short': '', 'description': 'Quality control application for high throughput sequence data.', 'url': 'https://www.bioinformatics.babraham.ac.uk/projects/fastqc/'],
        'fastqe': ['name': 'FASTQE', 'authors': '', 'authors_short': '', 'description': 'FASTQ sequence quality visualisation with Emoji.', 'url': 'https://github.com/fastqe/fastqe'],
        'fastqscreen': ['name': 'FastQ Screen', 'authors': 'Wingett SW., & Andrews S. (2018).', 'authors_short': 'Wingett & Andrews 2018', 'description': 'FastQ Screen: A tool for multi-genome mapping and quality control. F1000Res. 2018 Aug 24 [revised 2018 Jan 1];7:1338.', 'doi': '10.12688/f1000research.15931.2'],
        'fq': ['name': 'FQ', 'authors': '', 'authors_short': '', 'description': 'A library to generate and validate FASTQ file pairs.', 'url': 'https://github.com/stjude-rust-labs/fq'],
        'kraken2': ['name': 'Kraken2', 'authors': 'Wood D.E., Lu J., & Langmead B. (2019).', 'authors_short': 'Wood et al. 2019', 'description': 'Improved metagenomic analysis with Kraken 2. Genome Biology, 20(1), 257.', 'doi': '10.1186/s13059-019-1891-0'],
        'krona': ['name': 'Krona', 'authors': 'Ondov BD, Bergman NH, & Phillippy AM. (2011).', 'authors_short': 'Ondov et al. 2011', 'description': 'Interactive metagenomic visualization in a Web browser. BMC Bioinformatics, 12, 385.', 'doi': '10.1186/1471-2105-12-385'],
        'multiqc': ['name': 'MultiQC', 'authors': 'Ewels P., Magnusson M., Lundin S., & Käller M. (2016).', 'authors_short': 'Ewels et al. 2016', 'description': 'MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics, 32(19), 3047–3048.', 'doi': '10.1093/bioinformatics/btw354'],
        'multiqcsav': ['name': 'MultiQC SAV', 'authors': '', 'authors_short': '', 'description': 'MultiQC plugin for Illumina Sequencing Analysis Viewer.', 'url': 'https://github.com/MultiQC/MultiQC_SAV/'],
        'picard': ['name': 'Picard', 'authors': '', 'authors_short': '', 'description': 'Command line tools for manipulating high-throughput sequencing (HTS) data.', 'url': 'https://broadinstitute.github.io/picard/'],
        'pigz': ['name': 'pigz', 'authors': 'Adler M.', 'authors_short': 'Adler 2005', 'description': 'Parallel implementation of gzip.', 'url': 'https://zlib.net/pigz/'],
        'python': ['name': 'Python', 'authors': '', 'authors_short': '', 'description': 'Programming language.', 'url': 'https://www.python.org/'],
        'pyyaml': ['name': 'PyYAML', 'authors': '', 'authors_short': '', 'description': 'YAML parser and emitter for Python.', 'url': 'https://pyyaml.org/'],
        'riker': ['name': 'Riker', 'authors': '', 'authors_short': '', 'description': 'Fast Rust CLI toolkit for sequencing QC metrics. Ports key QC metrics tools from Picard with cleaner output and better performance.', 'url': 'https://github.com/fulcrumgenomics/riker'],
        'rundirparser': ['name': 'Rundirparser', 'authors': '', 'authors_short': '', 'description': 'Parse Illumina run directory metadata for MultiQC.', 'url': 'https://github.com/nf-core/seqinspector'],
        'samtools': ['name': 'SAMTOOLS', 'authors': 'Danecek P., Bonfield JK., Liddle J., & al. (2021).', 'authors_short': 'Danecek et al. 2021', 'description': 'Twelve years of SAMtools and BCFtools.', 'doi': '10.1093/gigascience/giab008'],
        'seqfu': ['name': 'SeqFu', 'authors': 'Telatin A., Fariselli P., & Birolo G. (2021).', 'authors_short': 'Telatin et al. 2021', 'description': 'SeqFu: A Suite of Utilities for the Robust and Reproducible Manipulation of Sequence Files. Bioengineering, 8, 59.', 'doi': '10.3390/bioengineering8050059'],
        'seqkit': ['name': 'SeqKit', 'authors': 'Shen W., Sipos B., & Zhao L. (2024).', 'authors_short': 'Shen et al. 2024', 'description': 'SeqKit2: A Swiss Army Knife for Sequence and Alignment Processing. iMeta, e191.', 'doi': '10.1002/imt2.191'],
        'seqtk': ['name': 'Seqtk', 'authors': 'Li H.', 'authors_short': 'Li 2013', 'description': 'Toolkit for processing FASTA and FASTQ files.', 'url': 'https://github.com/lh3/seqtk'],
        'sequali': ['name': 'Sequali', 'authors': 'Vorderman R. (2025).', 'authors_short': 'Vorderman 2025', 'description': 'Sequali: efficient and comprehensive quality control of short- and long-read sequencing data. Bioinformatics Advances.', 'doi': '10.1093/bioadv/vbaf010'],
        'toulligqc': ['name': 'ToulligQC', 'authors': '', 'authors_short': '', 'description': 'Post sequencing QC tool for Oxford Nanopore sequencers.', 'url': 'https://github.com/GenomiqueENS/toulligQC'],
        'untar': ['name': 'untar', 'authors': '', 'authors_short': '', 'description': 'GNU tar archive utility.', 'url': 'https://www.gnu.org/software/tar/'],
    ]
}

def toolReferencesText(type, tools) {
    def references = []
    def map = toolReferencesMap()

    tools.each { tool ->
        if (tool in map) {
            def entry = map[tool]
            if (type == 'citation') {
                references << "${entry.name} (${entry.doi ? "<a href='https://doi.org/${entry.doi}'>${entry.authors_short}</a>" : "<a href='${entry.url}'>${entry.url}</a>"})"
            }
            else {
                def link = entry.doi ? "doi: <a href='https://doi.org/${entry.doi}'>${entry.doi}</a>" : "url: <a href='${entry.url}'>${entry.url}</a>"
                references << "${entry.authors ?: entry.name + ':'} ${entry.description} ${link}".trim()
            }
        }
    }

    return references.sort()
}

def methodsDescriptionText(mqc_methods_yaml, tool_list, subsample_tools = []) {
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
            temp_doi_ref += "( <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    }
    else {
        meta["doi_text"] = ""
    }
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references - dynamically built from tools list
    meta["tool_citations"] = 'Tools used in the workflow included: ' + toolReferencesText('citation', tool_list).join(', ') + '.'
    meta["tool_bibliography"] = toolReferencesText('bibliography', tool_list).collect { bibliography -> "<li>${bibliography}</li>" }.join('\n    ')

    // Subsampled tools info
    meta["subsampled_text"] = ('seqtk' in tool_list && subsample_tools) && subsample_tools.intersect(tool_list).sort()
        ? "The following tools were run on subsampled reads (via Seqtk): ${subsample_tools.intersect(tool_list).sort().join(', ')}."
        : ""

    def methods_text = mqc_methods_yaml.text

    def engine = new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
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

    // Current list actually used are default, minimal and promethion, we should probably always have a list `all`
    // The others are here as a showcase for what could be done

    // please update the docs/usage.md section about tools selection when adding new tools here!

    if ('all' in bundle_list) {
        tools_list << 'bbmap_clumpify'
        tools_list << 'checkqc'
        tools_list << 'chelae'
        tools_list << 'fastqc'
        tools_list << 'fastp'
        tools_list << 'fastqe'
        tools_list << 'fastqscreen'
        tools_list << 'fq_lint'
        tools_list << 'kraken2'
        tools_list << 'multiqcsav'
        tools_list << 'picard_collecthsmetrics'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'riker'
        tools_list << 'rundirparser'
        tools_list << 'seqkit_stats'
        tools_list << 'seqfu_stats'
        tools_list << 'sequali'
        tools_list << 'toulligqc'
    }
    if ('bam' in bundle_list) {
        tools_list << 'picard_collecthsmetrics'
        tools_list << 'picard_collectmultiplemetrics'
        tools_list << 'riker'
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
