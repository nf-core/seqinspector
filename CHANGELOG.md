# nf-core/seqinspector: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0dev - [date]

Initial release of nf-core/seqinspector, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- [#13](https://github.com/nf-core/seqinspector/pull/13) Generate reports per run, per project and per lane
- [#20](https://github.com/nf-core/seqinspector/pull/20) Use tags to generate group reports
- [#50](https://github.com/nf-core/seqinspector/pull/50) Add an optional subsampling step
- [#51](https://github.com/nf-core/seqinspector/pull/51) Add nf-test to CI
- [#53](https://github.com/nf-core/seqinspector/pull/53) Add FastQ-Screen database multiplexing and limit scope of nf-test in CI
- [#56](https://github.com/nf-core/seqinspector/pull/56) Added SeqFu stats module
- [#63](https://github.com/nf-core/seqinspector/pull/63) Contribution guidelines added about displaying results for new tools
- [#68](https://github.com/nf-core/seqinspector/pull/68) Add tool selector
- [#75](https://github.com/nf-core/seqinspector/pull/75) Set up nft-utils
- [#96](https://github.com/nf-core/seqinspector/pull/96) Added missing citations to citation tool
- [#103](https://github.com/nf-core/seqinspector/pull/103) Configure full-tests
- [#108](https://github.com/nf-core/seqinspector/pull/108) Update lists of default steps in the pipeline
- [#108](https://github.com/nf-core/seqinspector/pull/108) Test data validation
- [#110](https://github.com/nf-core/seqinspector/pull/110) Update input schema to accept either tar file or directory as rundir, and fastq messages and patterns
- [#111](https://github.com/nf-core/seqinspector/pull/111) Short summary of seqinspector in README.md
- [#127](https://github.com/nf-core/seqinspector/pull/127) Added alignment tools - bwamem2 - index and mem
- [#128](https://github.com/nf-core/seqinspector/pull/128) Added Picard tools - Collect Multiple Mterics to collect QC metrics
- [#132](https://github.com/nf-core/seqinspector/pull/132) Added a bwamem2 index params for faster output
- [#135](https://github.com/nf-core/seqinspector/pull/135) Added index section to MultiQC reports to facilitate report navigation (#125)
- [#151](https://github.com/nf-core/seqinspector/pull/151) Added a prepare_genome subworkflow to handle bwamem2 indexing
- [#153](https://github.com/nf-core/seqinspector/pull/153) update README and usage.md
- [#156](https://github.com/nf-core/seqinspector/pull/156) Added relative sample_size and warning when a sample has less reads than desired sample_size
- [#159](https://github.com/nf-core/seqinspector/pull/159) Added a subworkflow QC_BAM including picard_collecthsmetrics for alignment QC of hybrid-selection data
- [#162](https://github.com/nf-core/seqinspector/pull/162) Add tests for prepare_genome subworkflow

### `Fixed`

- [#71](https://github.com/nf-core/seqinspector/pull/71) FASTQSCREEN does not fail when multiple reads are provided
- [#99](https://github.com/nf-core/seqinspector/pull/99) Fix group reports for paired reads
- [#107](https://github.com/nf-core/seqinspector/pull/107) Put SeqFU-stats section reports together
- [#108](https://github.com/nf-core/seqinspector/pull/108) Go through and validate test data
- [#112](https://github.com/nf-core/seqinspector/pull/112) Making fastq_screen_references value to use parentDir
- [#121](https://github.com/nf-core/seqinspector/pull/121) Cleanup sample naming for MultiQC report (#105)
- [#162](https://github.com/nf-core/seqinspector/pull/162) Fix bugs in qc_bam and prepare_genome subworkflows and add tests
- [#163](https://github.com/nf-core/seqinspector/pull/163) Run fastqscreen with subsampled data if available

### `Changed`

- [#49](https://github.com/nf-core/seqinspector/pull/49) Template update for nf-core/tools v3.0.2
- [#69](https://github.com/nf-core/seqinspector/pull/69) Template update for nf-core/tools v3.1.0
- [#74](https://github.com/nf-core/seqinspector/pull/74) Template update for nf-core/tools v3.2.0
- [#114](https://github.com/nf-core/seqinspector/pull/114) Update CI
- [#133](https://github.com/nf-core/seqinspector/pull/133) Template update for nf-core/tools v3.4.1
- [#144](https://github.com/nf-core/seqinspector/pull/144) Template update for nf-core/tools v3.5.1
- [#158](https://github.com/nf-core/seqinspector/pull/158) Moved picard_collectmultiplemetrics to the subworkflow QC_BAM
- [#164](https://github.com/nf-core/seqinspector/pull/164) Refactor local subworkflow and pipeline tests

### `Dependencies`

- [#116](https://github.com/nf-core/seqinspector/pull/116) Update MultiQC to 1.28

### `Deprecated`
