# nf-core/seqinspector: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.2](https://github.com/nf-core/seqinspector/releases/tag/1.1.2) - Carrie Bishop

### `Added`

### `Fixed`

### `Changed`
- [#271](https://github.com/nf-core/seqinspector/pull/271) Template update for nf-core/tools v4.1.0

- [#270](https://github.com/nf-core/seqinspector/pull/270) Back to dev

## [1.1.1](https://github.com/nf-core/seqinspector/releases/tag/1.1.1) - Cindy Mackenzie

### `Added`

- [#260](https://github.com/nf-core/seqinspector/pull/260) Add chelae/trim as an alternate trimming tool to fastp
- [#266](https://github.com/nf-core/seqinspector/pull/266) Add documentation on custom MultiQC sections

### `Fixed`

- [#264](https://github.com/nf-core/seqinspector/pull/264) Fix `--multiqc_title` modifying the output directory structure, breaking the report index section ([#261](https://github.com/nf-core/seqinspector/issues/261))
- [#269](https://github.com/nf-core/seqinspector/pull/269) Revert to old setup-apptainer version for GHA

### `Changed`

- [#259](https://github.com/nf-core/seqinspector/pull/259) Back to dev
- [#268](https://github.com/nf-core/seqinspector/pull/268) prepare pipeline update v1.1.1
- [#262](https://github.com/nf-core/seqinspector/pull/262) Template update for nf-core/tools v4.0.3

### `Dependencies`

| Dependency | Old version | New version |
| ---------- | ----------- | ----------- |
| chelae     |             | 0.1.0       |
| fastp      | 1.1.0       | 1.3.6       |

### `Removed`

## [1.1.0](https://github.com/nf-core/seqinspector/releases/tag/1.1.0) - Veronica Mars

### `Added`

- [#59](https://github.com/nf-core/seqinspector/pull/59) Seqkit Stats TSV output
- [#109](https://github.com/nf-core/seqinspector/pull/109) Adds ToulligQC module for long read QC
- [#134](https://github.com/nf-core/seqinspector/pull/134) Added sequali module
- [#202](https://github.com/nf-core/seqinspector/pull/202) Added support for fasta fai file as input (via params or igenomes) for the pipeline
- [#204](https://github.com/nf-core/seqinspector/pull/204) Added Fastp module
- [#206](https://github.com/nf-core/seqinspector/pull/206) Added FASTQE for more comprehensive QC of FASTQ files
- [#208](https://github.com/nf-core/seqinspector/pull/208) Add FASTQ linting for early validation with FQ/LINT
- [#209](https://github.com/nf-core/seqinspector/pull/209) Add MULTIQC SAV support
- [#210](https://github.com/nf-core/seqinspector/pull/210) Added kraken2 subworkflow
- [#212](https://github.com/nf-core/seqinspector/pull/212) Add CheckQC module
- [#218](https://github.com/nf-core/seqinspector/pull/218) kraken2 is run on subsampled data if available
- [#226](https://github.com/nf-core/seqinspector/pull/226) Add pipeline level stub tests
- [#228](https://github.com/nf-core/seqinspector/pull/228) Update all modules/subworkflows
- [#234](https://github.com/nf-core/seqinspector/pull/234) Add pipeline level PICARD tests
- [#236](https://github.com/nf-core/seqinspector/pull/236) Added bbmap/clumpify module for FASTQ deduplication and compression
- [#237](https://github.com/nf-core/seqinspector/pull/237) Add meta.yml for rundirparser module
- [#243](https://github.com/nf-core/seqinspector/pull/243) Add `--subsample_tools` parameter to control which tools run on subsampled data
- [#246](https://github.com/nf-core/seqinspector/pull/246) Added riker module for BAM-level QC metrics collection
- [#247](https://github.com/nf-core/seqinspector/pull/247) Add `AGENTS.md` file with nf-core agent instructions
- [#256](https://github.com/nf-core/seqinspector/pull/256) Improve docs
- [#258](https://github.com/nf-core/seqinspector/pull/258) Standardize output docs: descriptions above output files

### `Fixed`

- [#216](https://github.com/nf-core/seqinspector/pull/216) Fixed meta.id that resulted in all SEQFU_STATS processes with the same tag name
- [#224](https://github.com/nf-core/seqinspector/pull/224) Fix workflow output syntax for future Nextflow releases
- [#226](https://github.com/nf-core/seqinspector/pull/226) Fix parameter `tools_bundle` not accepting `null` for custom tool selection
- [#238](https://github.com/nf-core/seqinspector/pull/238) Fix Python/PyYAML tool name case mismatch in rundirparser module
- [#239](https://github.com/nf-core/seqinspector/pull/239) Fix tool bundles documentation to match code
- [#240](https://github.com/nf-core/seqinspector/pull/240) Fix FASTQE default tool marking in README
- [#243](https://github.com/nf-core/seqinspector/pull/243) Fix typos, broken link, missing `</details>` tag, and stray content in output documentation
- [#245](https://github.com/nf-core/seqinspector/pull/245) Fix repeated listing of CollectHsMetrics
- [#253](https://github.com/nf-core/seqinspector/pull/253) Fix CHANGELOG, missing Update in README and CITATIONS
- [#255](https://github.com/nf-core/seqinspector/pull/255) Fix rundirparser test snapshots to use full topic object instead of individual channels

### `Changed`

- [#191](https://github.com/nf-core/seqinspector/pull/191) Back to dev
- [#192](https://github.com/nf-core/seqinspector/pull/192) Refactor the tools selection logic
- [#205](https://github.com/nf-core/seqinspector/pull/205) Document how to add a tool to tool selection and how to use tool selection
- [#215](https://github.com/nf-core/seqinspector/pull/215) Update all modules
- [#216](https://github.com/nf-core/seqinspector/pull/216) Split out and simplify tests
- [#220](https://github.com/nf-core/seqinspector/pull/220) Workflow output for MultiQC
- [#221](https://github.com/nf-core/seqinspector/pull/221) Workflow output for checkQC, Fastp, fastqe, fastqscreen, picard_collecthsmetrics, picard_collectmultiplemetrics, rundirparser, seqfu
- [#222](https://github.com/nf-core/seqinspector/pull/222) Workflow output for fq/lint, kraken2, krona, toulligqc
- [#223](https://github.com/nf-core/seqinspector/pull/223) Workflow output for the rest of the pipeline
- [#225](https://github.com/nf-core/seqinspector/pull/225) Update subway map with nf-metro v1.0.0: add banner labels for file icons, folder icon for run directory, center ports, compact offsets, and reorder lines
- [#235](https://github.com/nf-core/seqinspector/pull/235) Update MultiQC and other dependencies
- [#237](https://github.com/nf-core/seqinspector/pull/237) Improved citation system to dynamically build tool citations based on selected tools
- [#244](https://github.com/nf-core/seqinspector/pull/244) Corrected the pipeline introduction tool list for fq lint
- [#249](https://github.com/nf-core/seqinspector/pull/249) Create meta.yml files for local subworkflows
- [#249](https://github.com/nf-core/seqinspector/pull/249) Update modules
- [#250](https://github.com/nf-core/seqinspector/pull/250) Prepare release 1.1.0
- [#252](https://github.com/nf-core/seqinspector/pull/252) Skip conda tests for CheckQC
- [#252](https://github.com/nf-core/seqinspector/pull/252) Skip latest-everything Nextflow version on main/master
- [#253](https://github.com/nf-core/seqinspector/pull/253) Update modules

### `Dependencies`

| Dependency | Old version | New version |
| ---------- | ----------- | ----------- |
| bbmap      |             | 39.18       |
| checkQC    |             | 4.1.0       |
| fastp      |             | 1.1.0       |
| fastqe     |             | 0.5.2       |
| fq/lint    |             | 0.12.0      |
| htslib     | 1.22.1      | 1.24        |
| kraken2    |             | 2.1.6       |
| krona      |             | 2.8.1       |
| multiqc    | 1.34        | 1.35        |
| multiqcsav |             | 0.2.0       |
| riker      |             | 0.4.0       |
| samtools   | 1.22.1      | 1.24        |
| seqkit     |             | 2.9.0       |
| toulligqc  |             | 2.8.4       |
| tar        |             | 1.34        |

### `Removed`

- [#192](https://github.com/nf-core/seqinspector/pull/192) Removed `bwamem2_index`, `bwamem2_mem`, `samtools_faidx` and `samtools_index` from the list of tools as they can be inferred from downstream tools
- [#192](https://github.com/nf-core/seqinspector/pull/192) Removed `run_picard_collecthsmetrics` param as `picard_collecthsmetrics` is now part of the list of tools
- [#192](https://github.com/nf-core/seqinspector/pull/192) Removed `seqtk_sample` from the list of tools as it can be inferred from `params.sample_size`
- [#213](https://github.com/nf-core/seqinspector/pull/213) Removed `sort_bam` params as we always need sorted BAM files for the QC_BAM subworkflow

## [1.0.1](https://github.com/nf-core/seqinspector/releases/tag/1.0.1) - Penelope Ruth "Penny" Gadget

### `Added`

### `Fixed`

- [#182](https://github.com/nf-core/seqinspector/pull/182) Keep modules diff to a minimum
- [#183](https://github.com/nf-core/seqinspector/pull/183) Fix tag collision warning message that was actually printed for every tag
- [#185](https://github.com/nf-core/seqinspector/pull/185) No failure when no fasta file is provided
- [#189](https://github.com/nf-core/seqinspector/pull/189), [#190](https://github.com/nf-core/seqinspector/pull/190) Fix GHA from [#186](https://github.com/nf-core/seqinspector/pull/186)

### `Changed`

- [#180](https://github.com/nf-core/seqinspector/pull/180) Add Zenodo record
- [#181](https://github.com/nf-core/seqinspector/pull/181) Back to dev
- [#184](https://github.com/nf-core/seqinspector/pull/184) Display the tag name as ID in the MULTIQC_PER_TAG task
- [#186](https://github.com/nf-core/seqinspector/pull/186) Remove hook_url from the pipeline configuration, cf[tools#4051](https://github.com/nf-core/tools/pull/4051)
- [#187](https://github.com/nf-core/seqinspector/pull/187) Prepare release 1.0.1

### `Dependencies`

### `Deprecated`

## [1.0.0](https://github.com/nf-core/seqinspector/releases/tag/1.0.0) - Inspector Gadget

Initial release of nf-core/seqinspector, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- [#2](https://github.com/nf-core/seqinspector/pull/2) Input workflow and schema definition
- [#13](https://github.com/nf-core/seqinspector/pull/13) Generate reports per run, per project and per lane
- [#20](https://github.com/nf-core/seqinspector/pull/20) Use tags to generate group reports
- [#50](https://github.com/nf-core/seqinspector/pull/50) Add an optional subsampling step
- [#51](https://github.com/nf-core/seqinspector/pull/51) Add nf-test to CI
- [#53](https://github.com/nf-core/seqinspector/pull/53), [#64](https://github.com/nf-core/seqinspector/pull/64) Add FastQ-Screen database multiplexing and limit scope of nf-test in CI
- [#56](https://github.com/nf-core/seqinspector/pull/56) Added SeqFu stats module
- [#63](https://github.com/nf-core/seqinspector/pull/63) Contribution guidelines added about displaying results for new tools
- [#68](https://github.com/nf-core/seqinspector/pull/68) Add tool selector
- [#75](https://github.com/nf-core/seqinspector/pull/75) Set up nft-utils
- [#96](https://github.com/nf-core/seqinspector/pull/96) Added missing citations to citation tool
- [#100](https://github.com/nf-core/seqinspector/pull/100) Added official logos
- [#103](https://github.com/nf-core/seqinspector/pull/103) Configure full-tests
- [#106](https://github.com/nf-core/seqinspector/pull/106) Parse rundir metadata
- [#108](https://github.com/nf-core/seqinspector/pull/108) Test data validation (#94)
- [#108](https://github.com/nf-core/seqinspector/pull/108) Update lists of default steps in the pipeline (#86)
- [#110](https://github.com/nf-core/seqinspector/pull/110) Update input schema to accept either tar file or directory as rundir, and fastq messages and patterns
- [#111](https://github.com/nf-core/seqinspector/pull/111) Short summary of seqinspector in README.md (#84)
- [#127](https://github.com/nf-core/seqinspector/pull/127) Added alignment tools - bwamem2 - index and mem
- [#128](https://github.com/nf-core/seqinspector/pull/128) Added Picard tools - Collect Multiple Mterics to collect QC metrics
- [#132](https://github.com/nf-core/seqinspector/pull/132) Added a bwamem2 index params for faster output
- [#135](https://github.com/nf-core/seqinspector/pull/135) Added index section to MultiQC reports to facilitate report navigation (#125)
- [#148](https://github.com/nf-core/seqinspector/pull/148) Add Tubemap
- [#151](https://github.com/nf-core/seqinspector/pull/151) Added a prepare_genome subworkflow to handle bwamem2 indexing
- [#156](https://github.com/nf-core/seqinspector/pull/156) Added relative sample_size and warning when a sample has less reads than desired sample_size
- [#159](https://github.com/nf-core/seqinspector/pull/159) Added a subworkflow QC_BAM including picard_collecthsmetrics for alignment QC of hybrid-selection data
- [#162](https://github.com/nf-core/seqinspector/pull/162) Add tests for prepare_genome subworkflow
- [#168](https://github.com/nf-core/seqinspector/pull/168) Add contributors list
- [#168](https://github.com/nf-core/seqinspector/pull/168) Add logo to the pipeline logo
- [#174](https://github.com/nf-core/seqinspector/pull/174) Add nf-core-utils 0.4.0
- [#180](https://github.com/nf-core/seqinspector/pull/180) Add Zenodo record

### `Fixed`

- [#71](https://github.com/nf-core/seqinspector/pull/71) FASTQSCREEN does not fail when multiple reads are provided
- [#77](https://github.com/nf-core/seqinspector/pull/77) Use a params for fastqscreen csv file, and not the hardcoded example one
- [#99](https://github.com/nf-core/seqinspector/pull/99) Fix group reports for paired reads
- [#107](https://github.com/nf-core/seqinspector/pull/107) Put SeqFU-stats section reports together
- [#108](https://github.com/nf-core/seqinspector/pull/108) Go through and validate test data (#94)
- [#112](https://github.com/nf-core/seqinspector/pull/112) Making fastq_screen_references value to use parentDir
- [#121](https://github.com/nf-core/seqinspector/pull/121) Cleanup sample naming for MultiQC report (#105)
- [#150](https://github.com/nf-core/seqinspector/pull/150) Fix pipeline linting issues
- [#162](https://github.com/nf-core/seqinspector/pull/162) Fix bugs in qc_bam and prepare_genome subworkflows and add tests
- [#163](https://github.com/nf-core/seqinspector/pull/163) Run fastqscreen with subsampled data if available
- [#167](https://github.com/nf-core/seqinspector/pull/167) RunDirParser is now skipped if no Run Directory information is available
- [#169](https://github.com/nf-core/seqinspector/pull/169) Rescue missing versions from PREPARE_GENOME subworkflow
- [#171](https://github.com/nf-core/seqinspector/pull/171) Rescue number of tasks in the pipeline level tests
- [#172](https://github.com/nf-core/seqinspector/pull/172) More complete conda environment for rundir parser
- [#173](https://github.com/nf-core/seqinspector/pull/173) Fix warning message for tag name collision
- [#174](https://github.com/nf-core/seqinspector/pull/174) Fix null message when no rundir information is available
- [#175](https://github.com/nf-core/seqinspector/pull/175) Fix conda setup in CI
- [#178](https://github.com/nf-core/seqinspector/pull/178) Fix nextflow schema
- [#178](https://github.com/nf-core/seqinspector/pull/178) Fix links in documentation

### `Changed`

- [#15](https://github.com/nf-core/seqinspector/pull/15) Template update for nf-core/tools v2.14.1
- [#26](https://github.com/nf-core/seqinspector/pull/26), [#49](https://github.com/nf-core/seqinspector/pull/49) Template update for nf-core/tools v3.0.2
- [#69](https://github.com/nf-core/seqinspector/pull/69) Template update for nf-core/tools v3.1.0
- [#72](https://github.com/nf-core/seqinspector/pull/72) Template update for nf-core/tools v3.1.2dev0
- [#74](https://github.com/nf-core/seqinspector/pull/74) Template update for nf-core/tools v3.2.0
- [#114](https://github.com/nf-core/seqinspector/pull/114) Update CI
- [#133](https://github.com/nf-core/seqinspector/pull/133) Template update for nf-core/tools v3.4.1
- [#144](https://github.com/nf-core/seqinspector/pull/144) Template update for nf-core/tools v3.5.1
- [#145](https://github.com/nf-core/seqinspector/pull/145) Remove outdated comments
- [#148](https://github.com/nf-core/seqinspector/pull/148), [#152](https://github.com/nf-core/seqinspector/pull/152), [#153](https://github.com/nf-core/seqinspector/pull/153) Update documentation
- [#158](https://github.com/nf-core/seqinspector/pull/158) Moved picard_collectmultiplemetrics to the subworkflow QC_BAM
- [#164](https://github.com/nf-core/seqinspector/pull/164) Refactor local subworkflow and pipeline tests
- [#168](https://github.com/nf-core/seqinspector/pull/168) Adhere to strict syntax
- [#169](https://github.com/nf-core/seqinspector/pull/169) Prepare release 1.0.0
- [#173](https://github.com/nf-core/seqinspector/pull/173) Improve documentation
- [#174](https://github.com/nf-core/seqinspector/pull/174) Refactor tests
- [#174](https://github.com/nf-core/seqinspector/pull/174) More strict syntax
- [#174](https://github.com/nf-core/seqinspector/pull/174) No params included in workflows
- [#175](https://github.com/nf-core/seqinspector/pull/175) Update all modules and migrate the whole pipeline to using topic versions
- [#176](https://github.com/nf-core/seqinspector/pull/176) No modules binaries
- [#177](https://github.com/nf-core/seqinspector/pull/177) Remove non used modules
- [#177](https://github.com/nf-core/seqinspector/pull/177) Move PREPARE_GENOME to the root main.nf script
- [#179](https://github.com/nf-core/seqinspector/pull/179) Set minimal Nextflow version to 24.10.2

### `Dependencies`

- [#116](https://github.com/nf-core/seqinspector/pull/116) Update MultiQC to 1.28
- [#174](https://github.com/nf-core/seqinspector/pull/174) Update nf-schema to 2.6.1

### `Deprecated`
