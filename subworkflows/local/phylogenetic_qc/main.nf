//
// Seqinspector Phylogenetic classification of reads, to check for contamination and adjacent issues
//

<<<<<<< HEAD
=======
include { UNTAR as UNTAR_KRAKEN2_DB } from '../../../modules/nf-core/untar'
>>>>>>> e99e066 (Changed paths in subworkflows)
include { KRAKEN2_KRAKEN2 } from '../../../modules/nf-core/kraken2/kraken2'
include { KRONA_KTUPDATETAXONOMY } from '../../../modules/nf-core/krona/ktupdatetaxonomy'
include { KRONA_KTIMPORTTAXONOMY } from '../../../modules/nf-core/krona/ktimporttaxonomy'

workflow PHYLOGENETIC_QC {
    take:
    reads
    kraken2_db

    main:
<<<<<<< HEAD
    ch_reads = reads
=======
    ch_reads    = reads
    ch_versions = Channel.empty()

    //
    // MODULE: Untar kraken2_db or read it as it is if not compressed
    //

    if (params.kraken2_db.endsWith('.gz')) {
        UNTAR_KRAKEN2_DB ( [ [:], params.kraken2_db ])
        ch_kraken2_db = UNTAR_KRAKEN2_DB.out.untar.map { it[1] }
        ch_versions      = ch_versions.mix(UNTAR_KRAKEN2_DB.out.versions)
    } else {
        ch_kraken2_db = Channel.fromPath(params.kraken2_db, checkIfExists: true)
        ch_kraken2_db = ch_kraken2_db.collect()
    }
>>>>>>> e99e066 (Changed paths in subworkflows)

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
