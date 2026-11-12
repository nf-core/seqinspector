//
// Seqinspector Phylogenetic classification of reads, to check for contamination and adjacent issues
//

include { KRAKEN2_KRAKEN2        } from '../../../modules/nf-core/kraken2/kraken2'
include { KRONA_KTIMPORTTAXONOMY } from '../../../modules/nf-core/krona/ktimporttaxonomy'
include { KRONA_KTUPDATETAXONOMY } from '../../../modules/nf-core/krona/ktupdatetaxonomy'

workflow FASTQ_QC_PHYLOGENETIC {
    take:
    reads
    kraken2_db
    kraken2_save_reads
    kraken2_save_readclassifications

    main:
    //
    // MODULE: Perform kraken2
    //
    KRAKEN2_KRAKEN2(reads, kraken2_db, kraken2_save_reads, kraken2_save_readclassifications)

    //
    // MODULE: krona plot the kraken2 reports
    //
    KRONA_KTUPDATETAXONOMY()
    KRONA_KTIMPORTTAXONOMY(
        KRAKEN2_KRAKEN2.out.report.map { meta, _process, _tool, reports -> [meta, reports] },
        KRONA_KTUPDATETAXONOMY.out.db,
    )
}
