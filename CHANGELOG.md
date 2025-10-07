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
- [#110](https://github.com/nf-core/seqinspector/pull/110) Update input schema to accept either tar file or directory as rundir, and fastq messages and patterns.

### `Fixed`

- [#71](https://github.com/nf-core/seqinspector/pull/71) FASTQSCREEN does not fail when multiple reads are provided.
- [#99](https://github.com/nf-core/seqinspector/pull/99) Fix group reports for paired reads
- [#107](https://github.com/nf-core/seqinspector/pull/107) Put SeqFU-stats section reports together
- [#112](https://github.com/nf-core/seqinspector/pull/112) Making fastq_screen_references value to use parentDir
- [#120](https://github.com/nf-core/seqinspector/pull/120) Run FastqScreen with subsampled data if available 
### `Dependencies`

- [#116](https://github.com/nf-core/seqinspector/pull/116) Update MultiQC to 1.28

### `Deprecated`
