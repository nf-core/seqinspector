//
// Seqinspector Phylogenetic classification of reads, to check for contamination and adjacent issues
//

include { UNTAR as UNTAR_KRAKEN2_DB } from '../../modules/nf-core/untar/main.nf'
include { KRAKEN2_KRAKEN2 } from '../../modules/nf-core/kraken2/kraken2/main.nf'
include { KRONA_KTUPDATETAXONOMY } from '../../modules/nf-core/krona/ktupdatetaxonomy/main.nf'
include { KRONA_KTIMPORTTAXONOMY } from '../../modules/nf-core/krona/ktimporttaxonomy/main.nf'

workflow PHYLOGENETIC_QC{
    take:
    reads

    main:
    ch_reads = reads
    //
    // MODULE: Untar kraken2_db
    //
    UNTAR_KRAKEN2_DB ( [ [:], params.kraken2_db ])
    ch_kraken2_db = UNTAR_KRAKEN2_DB.out.untar.map { it[1] }

    //
    // MODULE: Perform kraken2
    //
    KRAKEN2_KRAKEN2 (
        ch_reads,
        ch_kraken2_db,
        params.kraken2_save_reads,
        params.kraken2_save_readclassifications
    )
    //KRAKEN2_KRAKEN2.out.report.map { meta, report -> [ report ] }.collect()

    //
    // MODULE: krona plot the kraken2 reports
    //
    KRONA_KTUPDATETAXONOMY()
    KRONA_KTIMPORTTAXONOMY (
        KRAKEN2_KRAKEN2.out.report,
        KRONA_KTUPDATETAXONOMY.out.db
    )

    emit:
    kraken2_report = KRAKEN2_KRAKEN2.out.report.map { meta, report -> [ report ] }.collect()
}
