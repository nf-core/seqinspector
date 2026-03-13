//
// Seqinspector Phylogenetic classification of reads, to check for contamination and adjacent issues
//

include { KRAKEN2_KRAKEN2 } from '../../../modules/nf-core/kraken2/kraken2'
include { KRONA_KTUPDATETAXONOMY } from '../../../modules/nf-core/krona/ktupdatetaxonomy'
include { KRONA_KTIMPORTTAXONOMY } from '../../../modules/nf-core/krona/ktimporttaxonomy'

workflow PHYLOGENETIC_QC {
    take:
    reads
    kraken2_db

    main:
    ch_reads = reads

    //
    // MODULE: Perform kraken2
    //
 KRAKEN2_KRAKEN2 (
        ch_reads,
        kraken2_db,  
        params.kraken2_save_reads,
        params.kraken2_save_readclassifications
    )

    //
    // MODULE: krona plot the kraken2 reports
    //
    KRONA_KTUPDATETAXONOMY()
    KRONA_KTIMPORTTAXONOMY (
        KRAKEN2_KRAKEN2.out.report,
        KRONA_KTUPDATETAXONOMY.out.db
    )

    emit:
    mqc             = KRAKEN2_KRAKEN2.out.report
    krona_plots     = KRONA_KTIMPORTTAXONOMY.out.html.collect()
}
