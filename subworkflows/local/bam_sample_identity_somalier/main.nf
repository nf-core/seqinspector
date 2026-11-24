//
// Sample identity and relatedness of aligned BAM files with somalier
//

include { SOMALIER_EXTRACT } from '../../../modules/nf-core/somalier/extract'
include { SOMALIER_RELATE  } from '../../../modules/nf-core/somalier/relate'

// A .somalier file starts with a version byte, the length of the sample name and the sample name.
// Stub files are empty.
def somalierSampleName(somalier) {
    return somalier.withInputStream { stream ->
        stream.read()
        def length = stream.read()
        return length > 0 ? new String(stream.readNBytes(length), 'UTF-8') : somalier.simpleName
    }
}

workflow BAM_SAMPLE_IDENTITY_SOMALIER {
    take:
    ch_bam_bai // channel: [mandatory] [ val(meta), path(bam), path(bai) ], meta: id, tags, individual, batch
    ch_fasta   // channel: [mandatory] [ val(meta), path(fasta) ]
    ch_fai     // channel: [mandatory] [ val(meta), path(fai) ]
    ch_sites   // channel: [mandatory] [ val(meta), path(vcf) ]

    main:
    SOMALIER_EXTRACT(ch_bam_bai, ch_fasta, ch_fai, ch_sites)

    // Sorted by sample id, a stable order keeps the task hash of SOMALIER_RELATE stable for -resume
    def ch_batches = SOMALIER_EXTRACT.out.extract
        .map { meta, somalier -> [meta.batch ?: 'cohort', meta, somalier] }
        .groupTuple()
        .map { batch, metas, somaliers ->
            def rows = [metas, somaliers].transpose().sort { row -> row[0].id }
            [batch, rows.collect { row -> row[0] }, rows.collect { row -> row[1] }]
        }

    // One line per individual with more than one sample in the batch, these samples are expected to be identical
    def ch_groups = ch_batches
        .flatMap { batch, metas, somaliers ->
            [metas, somaliers]
                .transpose()
                .findAll { meta, _somalier -> meta.individual }
                .groupBy { meta, _somalier -> meta.individual }
                .values()
                .findAll { members -> members.size() > 1 }
                .collect { members -> ["${batch}.groups.txt", members.collect { _meta, somalier -> somalierSampleName(somalier) }.join(',') + '\n'] }
        }
        .collectFile(sort: true)
        .map { groups -> [groups.name - '.groups.txt', groups] }

    def ch_relate = ch_batches
        .join(ch_groups, remainder: true)
        .filter { row -> row[1] != null }
        .combine(ch_sites)
        .multiMap { batch, metas, somaliers, groups, meta_sites, sites ->
            extract: [[id: batch, tags: metas.collect { meta -> meta.tags }.flatten().unique()], somaliers, []]
            groups: groups ?: []
            sites: [meta_sites, sites]
        }

    SOMALIER_RELATE(ch_relate.extract, ch_relate.groups, ch_relate.sites)

    emit:
    extract = SOMALIER_EXTRACT.out.extract // channel: [ val(meta), path(somalier) ]
}
