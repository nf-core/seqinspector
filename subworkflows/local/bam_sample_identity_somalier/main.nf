//
// Sample identity, relatedness and contamination of aligned BAM files with somalier
//

include { SOMALIERCONTAM_ATTRIBUTE } from '../../../modules/local/somaliercontam/attribute'
include { SOMALIERCONTAM_IDENTITY  } from '../../../modules/local/somaliercontam/identity'
include { SOMALIERCONTAM_REPORT    } from '../../../modules/local/somaliercontam/report'
include { SOMALIER_CONTAMINATION   } from '../../../modules/nf-core/somalier/contamination'
include { SOMALIER_EXTRACT         } from '../../../modules/nf-core/somalier/extract'
include { SOMALIER_RELATE          } from '../../../modules/nf-core/somalier/relate'

// A .somalier file starts with a version byte, the length of the sample name and the sample name.
// Stub files are empty.
def somalierSampleName(somalier) {
    return somalier.withInputStream { stream ->
        stream.read()
        def length = stream.read()
        return length > 0 ? new String(stream.readNBytes(length), 'UTF-8') : somalier.simpleName
    }
}

// Row of the sample table read by somalier_contam.py, the digests are staged as somalier/<name>
def sampleTableRow(meta, somalier, role) {
    return [meta.id, "somalier/${somalier.name}", meta.individual ?: '', role == 'cohort' ? (meta.batch ?: '') : '', role, '', ''].join('\t')
}

workflow BAM_SAMPLE_IDENTITY_SOMALIER {
    take:
    ch_bam_bai // channel: [mandatory] [ val(meta), path(bam), path(bai) ], meta: id, tags, individual, batch
    ch_fasta   // channel: [mandatory] [ val(meta), path(fasta) ]
    ch_fai     // channel: [mandatory] [ val(meta), path(fai) ]
    ch_sites   // channel: [mandatory] [ val(meta), path(vcf) ]
    ch_background // channel: [optional] [ val(meta), path(somalier) ], digests of samples that are only candidate sources, meta: id, individual
    run_contamination // boolean: estimate contamination and attribute it to a source sample
    attribution_chunk_size // integer: number of samples per SOMALIERCONTAM_ATTRIBUTE task

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

    def ch_summary = channel.empty()

    if (run_contamination) {
        def table_header = "sample\tfile\tindividual\tbatch\trole\tinput\tsex"

        def ch_all = SOMALIER_EXTRACT.out.extract
            .map { meta, somalier -> [meta, somalier, 'cohort'] }
            .mix(ch_background.map { meta, somalier -> [meta, somalier, 'background'] })

        def ch_all_table = ch_all
            .map { meta, somalier, role -> sampleTableRow(meta, somalier, role) }
            .collectFile(name: 'samples.tsv', seed: table_header + '\n', newLine: true, sort: true)

        //
        // Samples with the same genotypes, across all batches and the background
        //
        SOMALIERCONTAM_IDENTITY(
            ch_all
                .map { _meta, somalier, _role -> somalier }
                .collect(sort: { a, b -> a.name <=> b.name })
                .map { somaliers -> [somaliers] }
                .combine(ch_all_table)
                .map { somaliers, table -> [[id: 'identity'], somaliers, table] },
            ch_sites,
        )

        //
        // somalier contamination needs a clean sample of the same individual as anchor
        //
        def ch_genotype_groups = SOMALIERCONTAM_IDENTITY.out.groups
            .flatMap { _meta, groups -> groups.splitCsv(header: true, sep: '\t').collect { row -> [row.sample, row.genotype_group] } }
            .join(ch_all.map { meta, somalier, _role -> [meta.id, somalier] })
            .map { _id, group, somalier -> [group, somalier] }
            .groupTuple()
            .filter { _group, somaliers -> somaliers.size() > 1 }
            .map { group, somaliers -> [[id: group], somaliers.sort { somalier -> somalier.name }] }

        SOMALIER_CONTAMINATION(ch_genotype_groups, ch_sites)

        //
        // Source attribution per batch, split into chunks of receiver samples.
        // Candidate sources are the other samples of the batch and the background.
        //
        def ch_attribution = ch_batches
            .combine(ch_background.toSortedList { a, b -> a[0].id <=> b[0].id }.map { background -> [background] })
            .flatMap { batch, metas, somaliers, background ->
                def rows = [metas, somaliers].transpose().collect { meta, somalier -> [meta, somalier, 'cohort'] } + background.collect { meta, somalier -> [meta, somalier, 'background'] }
                def table = ([table_header] + rows.collect { meta, somalier, role -> sampleTableRow(meta, somalier, role) }).join('\n') + '\n'
                def n_shards = Math.max(1, Math.ceil(metas.size() / attribution_chunk_size) as int)
                (0..<n_shards).collect { shard ->
                    [[id: "${batch}.shard${shard}", batch: batch, shard_index: shard, n_shards: n_shards], rows.collect { _meta, somalier, _role -> somalier }, table]
                }
            }
            .multiMap { meta, somaliers, table ->
                digests: [meta.batch, meta, somaliers]
                table: ["${meta.batch}.samples.tsv", table]
            }

        def ch_attribution_tables = ch_attribution.table
            .unique()
            .collectFile()
            .map { table -> [table.name - '.samples.tsv', table] }

        SOMALIERCONTAM_ATTRIBUTE(
            ch_attribution.digests.combine(ch_attribution_tables, by: 0).map { _batch, meta, somaliers, table -> [meta, somaliers, table] },
            ch_sites,
        )

        //
        // One report for all batches
        //
        def ch_tags = SOMALIER_EXTRACT.out.extract.map { meta, _somalier -> meta.tags }.collect().map { tags -> [tags.flatten().unique().sort()] }

        SOMALIERCONTAM_REPORT(
            ch_all_table
                .combine(SOMALIERCONTAM_IDENTITY.out.groups.map { _meta, groups -> groups })
                .combine(SOMALIERCONTAM_IDENTITY.out.pairs.map { _meta, pairs -> pairs })
                .combine(ch_tags)
                .map { table, groups, pairs, tags -> [[id: 'somalier_contamination', tags: tags], table, groups, pairs] },
            SOMALIERCONTAM_ATTRIBUTE.out.pairs
                .map { _meta, pairs -> pairs }
                .collect(sort: true)
                .map { pairs -> [pairs] }
                .combine(SOMALIERCONTAM_ATTRIBUTE.out.self.map { _meta, self -> self }.collect(sort: true).map { self -> [self] })
                .map { pairs, self -> [[id: 'attribution'], pairs, self] },
            SOMALIER_RELATE.out.samples_tsv
                .map { _meta, _process, _tool, tsv -> tsv }
                .collect(sort: true)
                .map { tsv -> [tsv] }
                .combine(SOMALIER_RELATE.out.pairs_tsv.map { _meta, _process, _tool, tsv -> tsv }.collect(sort: true).map { tsv -> [tsv] })
                .map { samples, pairs -> [[id: 'relate'], samples, pairs] },
            SOMALIER_CONTAMINATION.out.pairs_tsv
                .map { _meta, tsv -> tsv }
                .collect(sort: true)
                .ifEmpty([])
                .map { pairs -> [[id: 'contamination'], pairs] },
            [[id: 'coverage'], []],
        )

        ch_summary = SOMALIERCONTAM_REPORT.out.summary.mix(
            SOMALIERCONTAM_REPORT.out.attribution_pairs,
            SOMALIERCONTAM_REPORT.out.longitudinal,
            SOMALIERCONTAM_REPORT.out.flags,
            SOMALIERCONTAM_REPORT.out.heatmap,
        )
    }

    emit:
    extract       = SOMALIER_EXTRACT.out.extract // channel: [ val(meta), path(somalier) ]
    contamination = ch_summary                   // channel: [ val(meta), path(file) ]
}
