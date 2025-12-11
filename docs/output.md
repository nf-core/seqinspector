# nf-core/seqinspector: Output

## Introduction

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and can generate output files from the following steps:

- [Seqtk](#seqtk) - Subsample a specific number of reads per sample
- [FastQC](#fastqc) - Raw read QC
- [SeqFu Stats](#seqfu_stats) - Statistics for FASTA or FASTQ files
- [FastQ Screen](#fastqscreen) - Mapping against a set of references for basic contamination QC
- [BWA-MEM2_INDEX](#bwamem2_index) - Create BWA-MEM2 index of a chosen reference genome OR use pre-built index
- [BWA-MEM2_MEM](#bwamem2_mem) - Mapping reads against a chosen reference genome
- [Samtools index](#samtools-index) - Index BAM files with Samtools
- [Picard collect multiple metrics](#picard-collect-multiple-metrics) - Combine BAM and BAI outputs for Picard
- [Picard collecthsmetrics](#picard-collecthsmetrics) - Collect alignment QC metrics of hybrid-selection data
- [MultiQC](#multiqc) - Aggregate report describing results and QC from the whole pipeline
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### Seqtk

<details markdown="1">
<summary>Output files</summary>

- `seqtk/`
  - `*_fastq`: FastQ file after being subsampled to the sample_size value.

</details>

[Seqtk](https://github.com/lh3/seqtk) samples sequences by number.

### FastQC

<details markdown="1">
<summary>Output files</summary>

- `fastqc/`
  - `*_fastqc.html`: FastQC report containing quality metrics.
  - `*_fastqc.zip`: Zip archive containing the FastQC report, tab-delimited data file and plot images.

</details>

[FastQC](http://www.bioinformatics.babraham.ac.uk/projects/fastqc/) gives general quality metrics about your sequenced reads. It provides information about the quality score distribution across your reads, per base sequence content (%A/T/G/C), adapter contamination and overrepresented sequences. For further reading and documentation see the [FastQC help pages](http://www.bioinformatics.babraham.ac.uk/projects/fastqc/Help/).

### SeqFu Stats

<details markdown="1">
<summary>Output files</summary>

- `seqfu_stats/`
  - `*.tsv`: Tab-separated file containing quality metrics.
  - `*_mqc.txt`: File containing the same quality metrics as the TSV file, ready to be read by MultiQC.

</details>

[SeqFu](https://telatin.github.io/seqfu2/) is general-purpose program to manipulate and parse information from FASTA/FASTQ files, supporting gzipped input files. Includes functions to interleave and de-interleave FASTQ files, to rename sequences and to count and print statistics on sequence lengths. In this pipeline, the `seqfu stats` module is used to produce general quality metrics statistics.

### FastQ Screen

<details markdown="1">
<summary>Output files</summary>

- `fastqscreen/`
  - `*_screen.html`: Interactive graphical report.
  - `*_screen.png`: Static graphical report.
  - `*_screen.txt` : Text-based report.

</details>

[FastQ Screen](https://www.bioinformatics.babraham.ac.uk/projects/fastq_screen/) allows you to set up a standard set of references against which all of your samples can be mapped. Your references might contain the genomes of all of the organisms you work on, along with PhiX, vectors or other contaminants commonly seen in sequencing experiments.

To use FastQ Screen, this pipeline requires a `.csv` detailing:

- the working name of the reference
- the name of the aligner used to generate its index (which is also the aligner and index used by the tool)
- the file basename of the reference and its index (e.g. the reference `genoma.fa` and its index `genome.bt2` have the basename `genome`)
- the path to a dir where the reference and index files both reside.

See `assets/example_fastq_screen_references.csv` for example.

The `.csv` is provided as a pipeline parameter `fastq_screen_references` and is used to construct a `FastQ Screen` configuration file within the context of the process work directory in order to properly mount the references.

### BWAMEM2_INDEX

<details markdown="1">
<summary>Output files</summary>

Generates the full set of bwamem2 indexes:

- `bwamem2_index/`
  - `*.fa`
  - `*.fa.amb`
  - `*.fa.ann`
  - `*.fa.bwt`
  - `*.fa.pac`

### BWAMEM2_MEM

[BWA-mem2](https://github.com/bwa-mem2/bwa-mem2) is a tool next version of bwa-mem for mapping sequencies with low divergence against a reference genome with increased processing speed (~1.3-3.1x). Aligned reads are then potentially filtered and coordinate-sorted using [samtools](#samtools-index).

<details markdown="1">
<summary>Output files</summary>

- `bwamem2/`
  - `*.bam`: The original BAM file containing read alignments to the reference genome.
  - `*.bam.bai`: BAM index files

### Samtools index

<details markdown="1">
<summary>Output files</summary>

- `samtools_faidex`
  - `*.fa.fai`
  - `*.fa.fai`

### Picard collect multiple metrics

<details markdown="1">
<summary>Output files</summary>

- `picard_collectmultiplemetrics`
  - `*.CollectMultipleMetrics.alignment_summary_metrics`
  - `*.CollectMultipleMetrics.base_distribution_by_cycle_metrics`
  - `*.CollectMultipleMetrics.base_distribution_by_cycle.pdf`
  - `*.CollectMultipleMetrics.quality_by_cycle_metrics`
  - `*.CollectMultipleMetrics.quality_by_cycle.pdf`
  - `*.CollectMultipleMetrics.quality_distribution.pdf`
  - `*.CollectMultipleMetrics.read_length_histogram.pdf`

### Picard CollectHSmetrics

<details markdown="1">
<summary>Output files</summary>

- `picard_collecthsmetrics/`
  - `*.coverage_metrics`: Tab-separated file containing quality metrics for hybrid-selection data.

</details>

[Picard_collecthsmetrics](https://gatk.broadinstitute.org/hc/en-us/articles/360036856051-CollectHsMetrics-Picard) is a tool to collect metrics on the aligment SAM/BAM files that are specific for sequence datasets generated through hybrid-selection (mostly used to capture exon-specific sequences for targeted sequencing).

### MultiQC

nf-core/seqinspector will generate the following MultiQC reports:

- one global reports including all the samples listed in the samplesheet
- one group report per unique tag. These reports compile samples that share the same tag.

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `global_report`
    - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
    - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
    - `multiqc_plots/`: directory containing static images from the report in various formats.
  - `group_reports`
    - `tag1/`
      - `multiqc_report.html`
      - `multiqc_data/`
      - `multiqc_plots/`
    - `tag2/`
      - `multiqc_report.html`
      - `multiqc_data/`
      - `multiqc_plots/`
    - ...

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. Most of the pipeline QC results are visualised in the report and further statistics are available in the report data directory.

Results generated by MultiQC collate pipeline QC from supported tools e.g. FastQC. The pipeline has special steps which also allow the software versions to be reported in the MultiQC output for future traceability. For more information about how to use MultiQC reports, see <http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.
  - Parameters used by the pipeline run: `params.json`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
