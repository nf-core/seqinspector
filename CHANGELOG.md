# nf-core/seqinspector: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0dev - [date]

Initial release of nf-core/seqinspector, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- [#114](https://github.com/nf-core/seqinspector/pull/114/) Update CI
- [#75](https://github.com/nf-core/seqinspector/pull/75) Set up nft-utils
- [#68](https://github.com/nf-core/seqinspector/pull/68) Add tool selector
- [#20](https://github.com/nf-core/seqinspector/pull/20) Use tags to generate group reports
- [#13](https://github.com/nf-core/seqinspector/pull/13) Generate reports per run, per project and per lane.
- [#49](https://github.com/nf-core/seqinspector/pull/49) Merge with template 3.0.2.
- [#56](https://github.com/nf-core/seqinspector/pull/56) Added SeqFu stats module.
- [#50](https://github.com/nf-core/seqinspector/pull/50) Add an optional subsampling step.
- [#51](https://github.com/nf-core/seqinspector/pull/51) Add nf-test to CI.
- [#63](https://github.com/nf-core/seqinspector/pull/63) Contribution guidelines added about displaying results for new tools
- [#53](https://github.com/nf-core/seqinspector/pull/53) Add FastQ-Screen database multiplexing and limit scope of nf-test in CI.
- [#96](https://github.com/nf-core/seqinspector/pull/96) Added missing citations to citation tool
- [#103](https://github.com/nf-core/seqinspector/pull/103) Configure full-tests
- [#94](https://github.com/nf-core/seqinspector/issues/94) Test data validation
- [#86](https://github.com/nf-core/seqinspector/issues/86) Update lists of default steps in the pipeline
- [#84](https://github.com/nf-core/seqinspector/issues/84) Short summary of seqinspector in README.md
- [#110](https://github.com/nf-core/seqinspector/pull/110) Update input schema to accept either tar file or directory as rundir, and fastq messages and patterns.
- [#127](https://github.com/nf-core/seqinspector/pull/127) Added alignment tools - bwamem2 - index and mem
- [#128](https://github.com/nf-core/seqinspector/pull/128) Added Picard tools - Collect Multiple Mterics to collect QC metrics
- [#132](https://github.com/nf-core/seqinspector/pull/132) Added a bwamem2 index params for faster output
- [#135](https://github.com/nf-core/seqinspector/pull/135) Added index section to MultiQC reports to facilitate report navigation (#125)
- [#151](https://github.com/nf-core/seqinspector/pull/151) Added a prepare_genome subworkflow to handle bwamem2 indexing
- [#158](https://github.com/nf-core/seqinspector/pull/158) Moved picard_collectmultiplemetrics to the subworkflow QC_BAM
- [#159](https://github.com/nf-core/seqinspector/pull/159) Added a subworkflow QC_BAM including picard_collecthsmetrics for alignment QC of hybrid-selection data
- [#162](https://github.com/nf-core/seqinspector/pull/162) Add tests for prepare_genome subworkflow

### `Fixed`

- [#71](https://github.com/nf-core/seqinspector/pull/71) FASTQSCREEN does not fail when multiple reads are provided.
- [#99](https://github.com/nf-core/seqinspector/pull/99) Fix group reports for paired reads
- [#107](https://github.com/nf-core/seqinspector/pull/107) Put SeqFU-stats section reports together
- [#112](https://github.com/nf-core/seqinspector/pull/112) Making fastq_screen_references value to use parentDir
- [#121](https://github.com/nf-core/seqinspector/pull/121) Cleanup sample naming for MultiQC report (#105)
- [#94] (https://github.com/nf-core/seqinspector/issues/94) Go through and validate test data
- [#162](https://github.com/nf-core/seqinspector/pull/162) Fix bugs in qc_bam and prepare_genome subworkflows and add tests
- [#163](https://github.com/nf-core/seqinspector/pull/163) Run fastqscreen with subsampled data if available

### `Dependencies`

- [#116](https://github.com/nf-core/seqinspector/pull/116) Update MultiQC to 1.28

### `Deprecated`
