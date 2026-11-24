#!/usr/bin/env python3
"""
somalier_contam.py - contamination-SOURCE attribution and sample identity on top of somalier >= 0.3.2.

Each step is a subcommand, so it can run as an independent Nextflow process. Attribution is shardable
over receivers and the report joins are vectorised, which scales to thousands of samples.

Subcommands
  restrict-sites   keep only sites inside (padded) panel targets
  identity         hom-hom discordance between samples, genotype (= individual) groups
  attribute        per receiver x candidate mixture LLRs (shardable over receivers)
  report           merge attribution, identity, somalier relate + contamination; per-sample calls and
                   (with --coverage) inferred vs annotated sex

Sample table (TSV, header), used by identity/attribute/report:
  sample      unique sample ID (pipeline ID)
  file        path to the sample's .somalier file
  individual  optional patient/individual ID
  batch       optional batch ID
  role        'cohort' (receiver + candidate) or 'background' (candidate only)
  input       optional original BAM/CRAM name (report only)
  sex         optional annotated sex: male/female (M/F accepted), empty = unknown (report only)
"""
import argparse
import bisect
import collections
import gzip
import re
import struct
import sys
from pathlib import Path

import numpy as np
import pandas as pd

__version__ = "1.1.0"

XY = {"X", "chrX", "NC_000023.10", "NC_000023.11", "Y", "chrY", "NC_000024.9", "NC_000024.10"}
Y_CONTIGS = {"Y", "chrY", "NC_000024.9", "NC_000024.10"}
AUTOSOME = re.compile(r"^(chr)?([1-9]|1[0-9]|2[0-2])$|^NC_0000(0[1-9]|1[0-9]|2[0-2])\.\d+$")
# alpha grid: fine below 5 % where it matters, coarser above
GRID = np.unique(np.r_[np.arange(0, 0.05, 0.0005), np.arange(0.05, 0.5 + 1e-9, 0.005)])

GZIP = {"method": "gzip", "mtime": 0}  # reproducible .gz bytes (stable checksums / snapshots)
PAIR_COLS = ["receiver", "candidate", "n_sites", "n_informative", "alpha_source", "alpha_unknown_same_sites",
             "llr_vs_unknown", "llr_vs_clean", "hom_discordance", "n_both_hom"]
SELF_COLS = ["sample", "n_hom_sites", "alpha_unknown_source", "llr_contam_vs_clean"]


def log(msg):
    print(f"[somalier_contam] {msg}", file=sys.stderr, flush=True)


def openx(path):
    return gzip.open(path, "rt") if str(path).endswith((".gz", ".bgz")) else open(path)


# ----------------------------------------------------------------------------- sites
def restrict_sites(sites, bed, pad, out):
    """Keep only sites inside (padded) panel targets. Writes a plain-text VCF somalier can read."""
    out = Path(out)
    iv = collections.defaultdict(list)
    with openx(bed) as fh:
        for line in fh:
            if not line.strip() or line.startswith(("#", "track", "browser")):
                continue
            c, s, e = line.split("\t")[:3]
            iv[c].append((max(0, int(s) - pad), int(e) + pad))
    merged = {}
    for c, lst in iv.items():
        lst.sort()
        m = []
        for s, e in lst:
            if m and s <= m[-1][1]:
                m[-1][1] = max(m[-1][1], e)
            else:
                m.append([s, e])
        merged[c] = ([x[0] for x in m], [x[1] for x in m])
    n_in = n_kept = 0
    tmp = out.with_suffix(".tmp")
    with openx(sites) as fh, open(tmp, "w") as o:
        for line in fh:
            if line.startswith("#"):
                o.write(line)
                continue
            n_in += 1
            c, p = line.split("\t", 2)[:2]
            if c in merged:
                st, en = merged[c]
                i = bisect.bisect_right(st, int(p) - 1) - 1
                if i >= 0 and int(p) - 1 < en[i]:
                    o.write(line)
                    n_kept += 1
    if n_kept == 0:
        sys.exit("no sites fall inside the panel BED - check contig naming (chr1 vs 1) and genome build")
    tmp.rename(out)
    log(f"panel restriction: kept {n_kept}/{n_in} sites")
    if n_kept < 300:
        log("WARNING: <300 sites in panel; consider `somalier find-sites --include panel.bed --snp-dist 2000`")
    return out


def read_sites_af(path):
    """Autosomal sites in somalier's storage order with AF of the stored B allele."""
    recs = []
    with openx(path) as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            t = line.rstrip("\n").split("\t")
            if t[0] in XY:
                continue
            af = next((float(kv[3:].split(",")[0]) for kv in t[7].split(";") if kv.startswith("AF=")), None)
            if af is None:
                sys.exit(f"sites file lacks INFO/AF (needed for contamination): {path}")
            if not t[3] < t[4]:  # somalier stores alleles alphabetically -> flip AF like stored_alt_af()
                af = 1.0 - af
            recs.append((t[0], int(t[1]), af))
    recs.sort(key=lambda r: (r[0], r[1]))
    return np.clip(np.array([r[2] for r in recs], dtype=float), 1e-3, 1 - 1e-3)


# ----------------------------------------------------------------------------- somalier files
def read_somalier(path):
    b = Path(path).read_bytes()
    if b[0] != 2:
        sys.exit(f"{path}: .somalier format version {b[0]}, expected 2 (somalier >= 0.3)")
    n = b[1]
    name = b[2:2 + n].decode()
    o = 2 + n
    na, _nx, _ny = struct.unpack_from("<HHH", b, o)
    o += 6
    c = np.frombuffer(b, dtype="<u4", count=3 * na, offset=o).reshape(na, 3).astype(float)
    return name, c  # columns: A-allele, B-allele, other


def load_table(path):
    t = pd.read_csv(path, sep="\t", dtype=str).fillna("")
    for col in ("sample", "file"):
        if col not in t.columns:
            sys.exit(f"sample table {path} lacks column '{col}'")
    for col, default in (("individual", ""), ("batch", ""), ("role", "cohort"), ("input", ""), ("sex", "")):
        if col not in t.columns:
            t[col] = default
    t.loc[t.role == "", "role"] = "cohort"
    if t["sample"].duplicated().any():
        sys.exit(f"duplicate sample IDs in {path}: {sorted(t['sample'][t['sample'].duplicated()].unique())}")
    return t.reset_index(drop=True)


def load_counts(table, afB):
    names, counts = [], []
    for f in table.file:
        n, c = read_somalier(f)
        if len(c) != len(afB):
            sys.exit(f"{f}: {len(c)} sites but sites file has {len(afB)} autosomal sites "
                     "(was it extracted with a different sites file?)")
        names.append(n)
        counts.append(c)
    return names, np.stack(counts)


# ----------------------------------------------------------------------------- models
def snap0(x, tol=1e-9):
    """LLRs within floating-point noise of 0 (e.g. candidate genotypes identical to the receiver's at all
    informative sites) are set to exactly 0, so ties are exact and results do not depend on BLAS
    threading / summation order. Far below any decision threshold (--min-llr)."""
    return np.where(np.abs(x) < tol, 0.0, x)


def logsumexp0(x):
    m = x.max(0)
    return m + np.log(np.exp(x - m).sum(0))


def genotype_calls(C, min_depth, hom_max_af, het_min_af):
    ref, alt, oth = C[..., 0], C[..., 1], C[..., 2]
    dp = ref + alt
    ok = (dp >= min_depth) & (oth <= 0.1 * (dp + oth))
    af = np.divide(alt, dp, out=np.full_like(dp, np.nan), where=dp > 0)
    g = np.full(dp.shape, -1, dtype=np.int8)
    g[ok & (af <= hom_max_af)] = 0
    g[ok & (af >= 1 - hom_max_af)] = 2
    g[ok & (af >= het_min_af) & (af <= 1 - het_min_af)] = 1
    return g, alt, dp


def identity_matrix(G, rows=None):
    """Hom-hom discordance: among sites where both samples are homozygous-like, the fraction with
    opposite homozygotes. ~0 for the same person, even if either sample carries a few % contamination.
    rows: restrict to these receiver rows (returns len(rows) x N) so cohort x background stays tractable.
    Counts are accumulated in float32 (exact for integer counts < 2^24) and divided in float64."""
    H, A = (G == 0).astype(np.float32), (G == 2).astype(np.float32)
    if rows is None:
        rows = np.arange(len(G))
    X = H + A
    both = (X[rows] @ X.T).astype(float)
    opp = (H[rows] @ A.T + A[rows] @ H.T).astype(float)
    with np.errstate(invalid="ignore", divide="ignore"):
        return opp / both, both


def identity_groups(disc, nboth, max_disc, min_sites, rows=None):
    """Union-find over pairs with enough shared hom sites and low discordance. Group labels are
    numbered by first occurrence in sample order (independent of union order). With rows given, only
    pairs involving at least one of those rows are linked."""
    n = disc.shape[1]
    rows = np.arange(n) if rows is None else np.asarray(rows)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    with np.errstate(invalid="ignore"):
        ok = (nboth >= min_sites) & (disc <= max_disc)
    ri, cj = np.nonzero(ok)
    for i, j in sorted({(min(a, b), max(a, b)) for a, b in zip(rows[ri].tolist(), cj.tolist()) if a != b}):
        parent[find(i)] = find(j)
    roots = {}
    return [roots.setdefault(find(i), f"geno{len(roots) + 1}") for i in range(n)]


def attribution(names, G, alt, dp, afB, args, receivers=None):
    """Mixture LLRs for each receiver against every other sample as candidate source.
    Identical model to the original script; pair rows are built as arrays (not dicts) for scale."""
    N = len(names)
    names_arr = np.asarray(names, dtype=object)
    eps = args.error_rate
    q = afB
    lpi = np.log(np.stack([(1 - q) ** 2, 2 * q * (1 - q), q ** 2]))  # 3 x S
    scale = np.minimum(1.0, args.max_eff_depth / np.maximum(dp, 1))  # temper over-confidence at TSO500 depth
    K, D = alt * scale, dp * scale
    a = GRID[:, None]
    pair_chunks, self_rows = [], []
    for r in (range(N) if receivers is None else receivers):
        idx = np.where((G[r] == 0) | (G[r] == 2))[0]
        if len(idx) == 0:
            self_rows.append({"sample": names[r], "n_hom_sites": 0})
            continue
        h = G[r, idx][None, :] / 2.0
        k, n = K[r, idx][None, :], D[r, idx][None, :]
        M = np.empty((3, len(GRID), len(idx)))
        for g in (0, 1, 2):
            p = ((1 - a) * h + a * (g / 2.0)) * (1 - 2 * eps) + eps
            M[g] = k * np.log(p) + (n - k) * np.log1p(-p)
        Mu = logsumexp0(M + lpi[:, idx][:, None, :])  # contaminant genotype marginalised (HWE)
        llu = Mu.sum(1)
        self_rows.append({"sample": names[r], "n_hom_sites": len(idx),
                          "alpha_unknown_source": GRID[llu.argmax()],
                          "llr_contam_vs_clean": float(snap0(llu.max() - llu[0]))})
        GC = G[:, idx].T  # S x N candidate genotypes at R's hom-like sites
        I = [(GC == g).astype(float) for g in (0, 1, 2)]
        LLs = M[0] @ I[0] + M[1] @ I[1] + M[2] @ I[2]  # grid x N
        LLu = Mu @ (I[0] + I[1] + I[2])
        iS, iU = LLs.argmax(0), LLu.argmax(0)
        cols = np.arange(N)
        lls, llu_c, ll0 = LLs[iS, cols], LLu[iU, cols], LLs[0]
        n_used = (GC >= 0).sum(0)
        n_inf = ((GC >= 0) & (GC != G[r, idx][:, None])).sum(0)
        c = cols[cols != r]
        pair_chunks.append(pd.DataFrame({
            "receiver": names[r], "candidate": names_arr[c],
            "n_sites": n_used[c].astype(int), "n_informative": n_inf[c].astype(int),
            "alpha_source": GRID[iS[c]], "alpha_unknown_same_sites": GRID[iU[c]],
            "llr_vs_unknown": snap0(lls[c] - llu_c[c]), "llr_vs_clean": snap0(lls[c] - ll0[c])}))
    pairs = pd.concat(pair_chunks, ignore_index=True) if pair_chunks else pd.DataFrame(columns=PAIR_COLS[:8])
    return pairs, pd.DataFrame(self_rows, columns=SELF_COLS)


# ----------------------------------------------------------------------------- report helpers
def heatmap(pairs, names, path):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return
    m = pairs.pivot(index="receiver", columns="candidate", values="llr_vs_unknown").reindex(index=names, columns=names)
    pos = m.values[np.isfinite(m.values) & (m.values > 0)]
    lim = max(20.0, float(pos.max())) if pos.size else 20.0  # negatives saturate; sources stand out
    sz = max(5, 0.25 * len(names))
    fig, ax = plt.subplots(figsize=(sz + 2, sz))
    im = ax.imshow(m.values, cmap="RdBu_r", vmin=-lim, vmax=lim)
    ax.set_xticks(range(len(names)), names, rotation=90, fontsize=6)
    ax.set_yticks(range(len(names)), names, fontsize=6)
    ax.set_xlabel("candidate source")
    ax.set_ylabel("receiver")
    fig.colorbar(im, label="LLR source vs unknown contaminant")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def read_somalier_tsvs(paths):
    """Concatenate somalier TSV outputs (header may start with '#')."""
    dfs = [pd.read_csv(p, sep="\t").rename(columns=lambda c: c.lstrip("#")) for p in paths if Path(p).stat().st_size]
    return pd.concat(dfs, ignore_index=True) if dfs else None


def pair_key(a, b):
    a, b = np.asarray(a, dtype=str), np.asarray(b, dtype=str)
    return np.where(a < b, np.char.add(np.char.add(a, "\t"), b), np.char.add(np.char.add(b, "\t"), a))


def normalise_sex(x):
    return {"m": "male", "male": "male", "f": "female", "female": "female"}.get(str(x).strip().lower(), "")


def read_coverage(paths):
    """chrY and autosomal read counts from `samtools coverage` tables named <sample>[.coverage].txt."""
    rows = []
    for p in paths:
        cov = pd.read_csv(p, sep="\t", dtype={"#rname": str}).rename(columns=lambda c: c.lstrip("#"))
        auto = cov.rname.str.match(AUTOSOME)
        if not auto.any():  # non-standard contig names: everything except sex chromosomes and mitochondria
            auto = ~cov.rname.isin(XY | {"M", "MT", "chrM", "chrMT"})
        y = cov.rname.isin(Y_CONTIGS)
        name = Path(p).name
        rows.append({"sample": re.sub(r"(\.coverage)?\.txt$", "", name),
                     "sex_chrY_reads": cov.numreads[y].sum() if y.any() else np.nan,
                     "sex_autosomal_reads": cov.numreads[auto].sum()})
    return pd.DataFrame(rows, columns=["sample", "sex_chrY_reads", "sex_autosomal_reads"])


def sex_check(summ, args):
    """Infer sex from chrY reads (per million autosomal reads, MAPQ-filtered upstream) with X heterozygosity
    (somalier relate) as second signal, and compare with the annotated sex.

    chrY decides when it is clearly present or absent. In the grey zone (e.g. a female contaminated with male
    DNA) X heterozygosity can still call female. A single X (low X heterozygosity) is never used to call male:
    X loss of heterozygosity is common in tumours. Loss of Y is common in tumours of male patients, so an
    annotated male without chrY is reported as a possible loss of Y unless X heterozygosity shows two X.
    """
    with np.errstate(divide="ignore", invalid="ignore"):
        summ["sex_y_rpm"] = summ.sex_chrY_reads / summ.sex_autosomal_reads * 1e6
    n_x = summ.get("X_het", pd.Series(np.nan, index=summ.index)) + summ.get("X_hom_alt", np.nan)
    summ["sex_x_informative_sites"] = n_x
    with np.errstate(divide="ignore", invalid="ignore"):
        summ["sex_x_het_fraction"] = summ.get("X_het", np.nan) / n_x.where(n_x > 0)
    y = summ.sex_y_rpm
    xx = (n_x >= args.sex_min_x_sites) & (summ.sex_x_het_fraction >= args.sex_xx_min_het_fraction)
    y_call = np.select([y >= args.sex_male_min_y_rpm, y <= args.sex_female_max_y_rpm], ["male", "female"], "")
    summ["sex_inferred"] = np.where(y_call != "", y_call, np.where(xx, "female", "undetermined"))
    ann, inf = summ.sex_annotated, summ.sex_inferred
    summ["sex_check"] = np.select(
        [ann == "", inf == "undetermined", ann == inf, (ann == "male") & xx, ann == "male"],
        ["not_annotated", "undetermined", "ok", "SEX_MISMATCH", "SEX_MISMATCH(no_Y:swap_or_loss_of_Y?)"],
        "SEX_MISMATCH(Y_present:swap_or_male_contamination?)")
    return summ.drop(columns=[c for c in ("X_het", "X_hom_alt") if c in summ.columns])


def write_mqc(summ, prefix):
    """MultiQC custom-content tables (sample names = pipeline sample IDs)."""
    cols = ["sample", "call", "contamination_charr", "alpha_unknown_source", "best_source", "source_alpha",
            "source_llr_vs_unknown", "llr_margin", "somalier_anchored_mle_same_individual", "genotype_group",
            "sex_annotated", "sex_inferred", "sex_check", "sex_y_rpm", "sex_x_het_fraction"]
    cols = [c for c in cols if c in summ.columns]
    with open(f"{prefix}_summary_mqc.tsv", "w") as fh:
        fh.write("# id: 'somalier_contam_summary'\n# section_name: 'Contamination and source attribution'\n"
                 "# description: 'Per-sample contamination estimates (somalier CHARR and the mixture model), "
                 "best contamination source among cohort/background samples and the resulting call.'\n"
                 "# plot_type: 'table'\n")
        summ[cols].to_csv(fh, sep="\t", index=False, float_format="%.4g")
    gs = [c for c in ("contamination_charr", "alpha_unknown_source", "source_alpha") if c in summ.columns]
    with open(f"{prefix}_generalstats_mqc.tsv", "w") as fh:
        fh.write("# id: 'somalier_contam_generalstats'\n# plot_type: 'generalstats'\n")
        summ[["sample"] + gs].to_csv(fh, sep="\t", index=False, float_format="%.4g")


# ----------------------------------------------------------------------------- subcommands
def cmd_restrict_sites(args):
    restrict_sites(args.sites, args.bed, args.pad, args.output)


def cmd_identity(args):
    t = load_table(args.samples)
    afB = read_sites_af(args.sites)
    names, C = load_counts(t, afB)
    G, _, _ = genotype_calls(C, args.min_depth, args.hom_max_af, args.het_min_af)
    n_called = (G >= 0).sum(1)
    cohort = np.where(t.role.values == "cohort")[0]
    if len(cohort) == 0:
        sys.exit("no cohort samples in sample table")
    if n_called[cohort].max() == 0:
        sys.exit("no sample has a single usable site - check that sites, FASTA and BAM contig naming "
                 "(chr1 vs 1) and genome build match")
    for i in cohort[n_called[cohort] == 0]:
        log(f"WARNING: sample {t['sample'][i]} has no usable sites (depth < {args.min_depth}?)")
    log(f"{len(afB)} autosomal sites; median usable per cohort sample: {int(np.median(n_called[cohort]))}")

    disc, nboth = identity_matrix(G, cohort)
    geno = identity_groups(disc, nboth, args.identity_max_disc, args.min_identity_sites, cohort)
    t["somalier_name"], t["genotype_group"], t["n_called_sites"] = names, geno, n_called
    t[["sample", "somalier_name", "role", "individual", "batch", "genotype_group", "n_called_sites"]].to_csv(
        f"{args.prefix}.genotype_groups.tsv", sep="\t", index=False)

    # pairs involving >= 1 cohort sample that are expected identical (individual) or genotype-identical
    rowpos = {int(r): k for k, r in enumerate(cohort)}
    cand = set()
    for key in ("genotype_group", "individual"):
        for _, members in t[t[key] != ""].groupby(key).groups.items():
            members = list(members)
            for x in range(len(members)):
                for y in range(x + 1, len(members)):
                    i, j = members[x], members[y]
                    if i in rowpos or j in rowpos:
                        cand.add((min(i, j), max(i, j)))
    recs = []
    S, I, B, R = t["sample"].values, t.individual.values, t.batch.values, t.role.values
    for i, j in sorted(cand):
        r, c = (i, j) if i in rowpos else (j, i)
        a, b = (i, j) if S[i] < S[j] else (j, i)
        recs.append({"sample_a": S[a], "sample_b": S[b], "individual_a": I[a], "individual_b": I[b],
                     "hom_discordance": disc[rowpos[r], c], "n_both_hom": int(nboth[rowpos[r], c]),
                     "same_genotype_group": geno[i] == geno[j], "role_a": R[a], "role_b": R[b],
                     "batch_a": B[a], "batch_b": B[b]})
    pd.DataFrame(recs, columns=["sample_a", "sample_b", "individual_a", "individual_b", "hom_discordance",
                                "n_both_hom", "same_genotype_group", "role_a", "role_b", "batch_a",
                                "batch_b"]).to_csv(f"{args.prefix}.identity_pairs.tsv", sep="\t", index=False)


def cmd_attribute(args):
    t = load_table(args.samples)
    afB = read_sites_af(args.sites)
    _, C = load_counts(t, afB)
    G, alt, dp = genotype_calls(C, args.min_depth, args.hom_max_af, args.het_min_af)
    cohort = np.where(t.role.values == "cohort")[0]
    k, n = (int(x) for x in args.shard.split("/"))
    if not 0 <= k < n:
        sys.exit(f"--shard must be k/n with 0 <= k < n, got {args.shard}")
    receivers = np.array_split(cohort, n)[k] if len(cohort) else cohort
    log(f"attribution: {len(receivers)} receivers (shard {k}/{n}) x {len(t) - 1} candidates")
    names = t["sample"].tolist()
    pairs, selfdf = attribution(names, G, alt, dp, afB, args, receivers=receivers)
    if len(receivers) and len(pairs):
        disc, nboth = identity_matrix(G, receivers)
        rpos = {int(r): x for x, r in enumerate(receivers)}
        ix = {s: x for x, s in enumerate(names)}
        ri = pairs.receiver.map(lambda s: rpos[ix[s]]).values
        ci = pairs.candidate.map(ix).values
        pairs["hom_discordance"] = disc[ri, ci]
        pairs["n_both_hom"] = nboth[ri, ci].astype(int)
    else:
        pairs = pd.DataFrame(columns=PAIR_COLS)
    pairs.to_csv(f"{args.prefix}.attribution_pairs.tsv.gz", sep="\t", index=False, compression=GZIP)
    selfdf.to_csv(f"{args.prefix}.attribution_self.tsv", sep="\t", index=False)


def cmd_report(args):
    t = load_table(args.samples)
    gg = pd.read_csv(args.groups, sep="\t", dtype=str).fillna("")
    grp = dict(zip(gg["sample"], gg.genotype_group))
    sname2sample = dict(zip(gg.somalier_name, gg["sample"]))
    ind = dict(zip(t["sample"], t.individual))
    cohort = t[t.role == "cohort"]

    def to_sample(s):
        return s.map(lambda x: sname2sample.get(x, x))

    # ---- attribution pairs + identity/somalier annotations
    pairs = pd.concat([pd.read_csv(p, sep="\t", dtype={"receiver": str, "candidate": str})
                       for p in args.attribution_pairs], ignore_index=True)
    selfdf = pd.concat([pd.read_csv(p, sep="\t", dtype={"sample": str}) for p in args.attribution_self],
                       ignore_index=True)
    pairs["same_genotype_group"] = pairs.receiver.map(grp).values == pairs.candidate.map(grp).values
    pairs["candidate_individual"] = pairs.candidate.map(ind)
    pairs["candidate_role"] = pairs.candidate.map(dict(zip(t["sample"], t.role)))

    rel_p = read_somalier_tsvs(args.relate_pairs)
    rel_cols = ["relatedness", "concordance", "ibs0", "n"]
    if rel_p is not None and len(rel_p):
        rel_p["sample_a"], rel_p["sample_b"] = to_sample(rel_p.sample_a.astype(str)), to_sample(rel_p.sample_b.astype(str))
        rel_p["key"] = pair_key(rel_p.sample_a, rel_p.sample_b)
        rp = rel_p.drop_duplicates("key").set_index("key")[rel_cols].add_prefix("somalier_")
    else:
        rp = pd.DataFrame(columns=[f"somalier_{c}" for c in rel_cols])
    pairs["key"] = pair_key(pairs.receiver, pairs.candidate) if len(pairs) else []
    pairs = pairs.join(rp, on="key").drop(columns="key")

    con_p = read_somalier_tsvs(args.contam_pairs)
    if con_p is not None and len(con_p):
        cp = con_p.rename(columns={"sample_name": "receiver", "anchor_sample": "candidate",
                                   "contamination_mle": "somalier_anchored_mle"})
        cp["receiver"], cp["candidate"] = to_sample(cp.receiver.astype(str)), to_sample(cp.candidate.astype(str))
        cp = cp.drop_duplicates(["receiver", "candidate"])[["receiver", "candidate", "somalier_anchored_mle"]]
    else:
        cp = pd.DataFrame(columns=["receiver", "candidate", "somalier_anchored_mle"])
    pairs = pairs.merge(cp, how="left", on=["receiver", "candidate"])
    pairs = pairs.sort_values(["receiver", "llr_vs_unknown"], ascending=[True, False], kind="mergesort")
    out_pairs = pairs.groupby("receiver", sort=False).head(args.top_candidates) if args.top_candidates > 0 else pairs
    out_pairs.to_csv(f"{args.prefix}.attribution.pairs.tsv.gz", sep="\t", index=False, float_format="%.4g",
                     compression=GZIP)

    # ---- per-sample summary (vectorised version of the original per-sample loop)
    summ = pd.DataFrame({"sample": cohort["sample"].values, "bam": cohort.input.values,
                         "individual": cohort.individual.values, "genotype_group": cohort["sample"].map(grp).values,
                         "batch": cohort.batch.values,
                         "somalier_name": cohort["sample"].map(dict(zip(gg["sample"], gg.somalier_name))).values})
    sub = pairs[~pairs.same_genotype_group].assign(g=lambda d: d.candidate.map(grp))
    bb = sub.drop_duplicates(["receiver", "g"])  # already sorted by llr within receiver
    bb = bb.assign(rank=bb.groupby("receiver").cumcount())
    b1 = bb[bb["rank"] == 0].set_index("receiver")
    b2 = bb[bb["rank"] == 1].set_index("receiver").llr_vs_unknown
    best = pd.DataFrame({"best_source": b1.candidate, "best_source_individual": b1.candidate_individual,
                         "source_alpha": b1.alpha_source, "source_llr_vs_unknown": b1.llr_vs_unknown,
                         "source_n_informative": b1.n_informative, "second_best_llr": b2.reindex(b1.index)})
    best["llr_margin"] = best.source_llr_vs_unknown - best.second_best_llr
    summ = summ.merge(best, left_on="sample", right_index=True, how="left")
    same = cp[cp.receiver.map(grp).values == cp.candidate.map(grp).values]
    summ["somalier_anchored_mle_same_individual"] = summ["sample"].map(
        pd.to_numeric(same.somalier_anchored_mle, errors="coerce").groupby(same.receiver).median())
    summ = summ.merge(selfdf, on="sample", how="left")
    rel_s = read_somalier_tsvs(args.relate_samples)
    keep = ["sample_id", "depth_mean", "gt_depth_mean", "n_het", "n_unknown", "p_middling_ab", "contamination_charr"]
    if args.coverage:
        keep += ["X_het", "X_hom_alt"]
    if rel_s is not None and len(rel_s):
        rel_s["sample_id"] = to_sample(rel_s.sample_id.astype(str))
        summ = summ.merge(rel_s[[c for c in keep if c in rel_s.columns]].drop_duplicates("sample_id")
                          .rename(columns={"sample_id": "sample"}), on="sample", how="left")

    def call(x):
        est = np.nanmax([x.get("contamination_charr", np.nan), x.get("alpha_unknown_source", np.nan)])
        llr, marg = x.get("source_llr_vs_unknown", np.nan), x.get("llr_margin", np.nan)
        if llr >= args.min_llr and (np.isnan(marg) or marg >= args.min_margin):
            c = "source_identified"
        elif llr >= args.min_llr:
            c = "source_ambiguous"
        elif est >= args.contam_threshold:
            c = "contaminated_source_not_in_cohort"
        else:
            c = "clean"
        if x.get("n_hom_sites", 0) < 50:
            c += ";low_sites"
        return c

    with np.errstate(all="ignore"):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)  # nanmax of all-NaN, as in the original
            summ["call"] = summ.apply(call, axis=1) if len(summ) else []

    # ---- inferred vs annotated sex
    if args.coverage:
        summ["sex_annotated"] = summ["sample"].map(dict(zip(cohort["sample"], cohort.sex.map(normalise_sex))))
        summ = sex_check(summ.merge(read_coverage(args.coverage), on="sample", how="left"), args)
    lead = ["sample", "individual", "genotype_group", "call", "contamination_charr", "alpha_unknown_source",
            "p_middling_ab", "best_source", "best_source_individual", "source_alpha", "source_llr_vs_unknown",
            "llr_margin", "source_n_informative", "somalier_anchored_mle_same_individual", "n_hom_sites",
            "sex_annotated", "sex_inferred", "sex_check", "sex_y_rpm", "sex_x_het_fraction", "sex_x_informative_sites",
            "sex_chrY_reads", "sex_autosomal_reads"]
    summ = summ[[c for c in lead if c in summ.columns] + [c for c in summ.columns if c not in lead]]
    summ.to_csv(f"{args.prefix}.summary.samples.tsv", sep="\t", index=False, float_format="%.4g")
    write_mqc(summ, args.prefix)

    # ---- longitudinal / identity tables (unordered pairs, global across batches + background)
    idp = pd.read_csv(args.identity_pairs, sep="\t", dtype={"sample_a": str, "sample_b": str,
                                                            "individual_a": str, "individual_b": str}).fillna(
        {"individual_a": "", "individual_b": ""})
    idp["same_genotype_group"] = idp.same_genotype_group.astype(str).str.lower() == "true"
    idp["key"] = pair_key(idp.sample_a, idp.sample_b) if len(idp) else []
    idp = idp.join(rp[["somalier_relatedness", "somalier_concordance"]], on="key")
    expected_same = (idp.individual_a != "") & (idp.individual_a == idp.individual_b)
    known_diff = (idp.individual_a != "") & (idp.individual_b != "") & (idp.individual_a != idp.individual_b)
    long_ = idp[expected_same | idp.same_genotype_group].copy()
    long_["flag"] = np.where(expected_same[long_.index] & ~long_.same_genotype_group,
                             "IDENTITY_MISMATCH(swap/heavy contamination?)", "ok")
    cols = ["sample_a", "sample_b", "individual_a", "individual_b", "hom_discordance", "n_both_hom",
            "somalier_relatedness", "somalier_concordance", "flag", "role_a", "role_b", "batch_a", "batch_b"]
    long_[cols].to_csv(f"{args.prefix}.longitudinal.pairs.tsv", sep="\t", index=False, float_format="%.4g")

    flags = collections.OrderedDict()

    def add(a, b, flag, disc, rel, conc):
        rec = flags.setdefault((a, b), {"sample_a": a, "sample_b": b, "flags": [], "hom_discordance": disc,
                                        "somalier_relatedness": rel, "somalier_concordance": conc})
        rec["flags"].append(flag)

    for x, kd in zip(idp.itertuples(index=False), known_diff):
        if x.individual_a and x.individual_a == x.individual_b and not x.same_genotype_group:
            add(x.sample_a, x.sample_b, "expected_same_but_discordant", x.hom_discordance,
                x.somalier_relatedness, x.somalier_concordance)
        if x.same_genotype_group and kd:
            add(x.sample_a, x.sample_b, "unexpected_identity(swap/duplicate)", x.hom_discordance,
                x.somalier_relatedness, x.somalier_concordance)
    if rel_p is not None and len(rel_p):
        hi = rel_p[(rel_p.relatedness > args.relatedness_threshold)
                   & (rel_p.sample_a.map(grp).values != rel_p.sample_b.map(grp).values)]
        disc_lookup = pairs.set_index(["receiver", "candidate"]).hom_discordance if len(pairs) else pd.Series(dtype=float)
        for x in hi.itertuples(index=False):
            a, b = sorted((x.sample_a, x.sample_b))
            add(a, b, "elevated_relatedness(contamination/family)", disc_lookup.get((a, b), np.nan),
                x.relatedness, x.concordance)
    fl = pd.DataFrame([dict(v, flags=";".join(v["flags"])) for v in flags.values()],
                      columns=["sample_a", "sample_b", "flags", "hom_discordance", "somalier_relatedness",
                               "somalier_concordance"])
    fl.sort_values(["sample_a", "sample_b"]).to_csv(f"{args.prefix}.relatedness_flags.tsv", sep="\t",
                                                    index=False, float_format="%.4g")

    # ---- heatmaps per batch (skipped for batches too large to be readable)
    for batch, sub_t in cohort.groupby(cohort.batch.replace("", "cohort")):
        names = sub_t["sample"].tolist()
        if len(names) > args.max_heatmap_samples:
            log(f"skipping heatmap for batch {batch}: {len(names)} > --max-heatmap-samples {args.max_heatmap_samples}")
            continue
        hp = pairs[pairs.receiver.isin(names) & pairs.candidate.isin(names)]
        if len(hp):
            heatmap(hp, names, f"{args.prefix}.{batch}.attribution_llr.png")

    with pd.option_context("display.width", 200, "display.max_columns", 20, "display.max_rows", 200):
        print(summ[[c for c in ["sample", "call", "contamination_charr", "alpha_unknown_source", "best_source",
                                "source_alpha", "source_llr_vs_unknown", "llr_margin", "sex_check"]
                      if c in summ.columns]]
              .head(200).to_string(index=False))


# ----------------------------------------------------------------------------- CLI
def add_geno_args(p):
    p.add_argument("--sites", required=True, help="sites VCF used for extract (INFO/AF required)")
    p.add_argument("--samples", required=True, help="sample table TSV (see module docstring)")
    p.add_argument("--min-depth", type=int, default=20, help="min site depth [20]")
    p.add_argument("--hom-max-af", type=float, default=0.15, help="minor-allele fraction tolerated for hom-like calls [0.15]")
    p.add_argument("--het-min-af", type=float, default=0.25, help="het call window [x, 1-x] for candidate genotypes [0.25]")
    p.add_argument("--prefix", default="somalier_contam", help="output prefix")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sp = ap.add_subparsers(dest="cmd", required=True)

    p = sp.add_parser("restrict-sites", help="restrict a sites VCF to padded panel targets")
    p.add_argument("--sites", required=True)
    p.add_argument("--bed", required=True)
    p.add_argument("--pad", type=int, default=100, help="pad BED intervals by this many bp [100]")
    p.add_argument("--output", required=True, help="output VCF (plain text)")
    p.set_defaults(func=cmd_restrict_sites)

    p = sp.add_parser("identity", help="hom-hom discordance and genotype groups")
    add_geno_args(p)
    p.add_argument("--identity-max-disc", type=float, default=0.05, help="hom-hom discordance <= this = same individual [0.05]")
    p.add_argument("--min-identity-sites", type=int, default=20, help="min shared hom sites for identity calls [20]")
    p.set_defaults(func=cmd_identity)

    p = sp.add_parser("attribute", help="contamination source attribution LLRs")
    add_geno_args(p)
    p.add_argument("--error-rate", type=float, default=0.002, help="per-read error rate in the mixture likelihood [0.002]")
    p.add_argument("--max-eff-depth", type=float, default=300, help="cap effective depth per site [300]")
    p.add_argument("--shard", default="0/1", help="process receiver shard k of n (0-based, 'k/n') [0/1]")
    p.set_defaults(func=cmd_attribute)

    p = sp.add_parser("report", help="merge everything into per-sample calls and pair tables")
    p.add_argument("--samples", required=True)
    p.add_argument("--groups", required=True, help="identity genotype_groups.tsv")
    p.add_argument("--identity-pairs", required=True, help="identity identity_pairs.tsv")
    p.add_argument("--attribution-pairs", nargs="+", required=True)
    p.add_argument("--attribution-self", nargs="+", required=True)
    p.add_argument("--relate-samples", nargs="*", default=[])
    p.add_argument("--relate-pairs", nargs="*", default=[])
    p.add_argument("--contam-pairs", nargs="*", default=[])
    p.add_argument("--contam-threshold", type=float, default=0.01)
    p.add_argument("--min-llr", type=float, default=10)
    p.add_argument("--min-margin", type=float, default=5)
    p.add_argument("--relatedness-threshold", type=float, default=0.2, help="flag pairs from different genotype groups "
                   "with somalier relatedness above this as elevated_relatedness [0.2]")
    p.add_argument("--top-candidates", type=int, default=0, help="keep only the top N candidates per receiver in "
                   "attribution.pairs.tsv.gz (0 = all) [0]")
    p.add_argument("--max-heatmap-samples", type=int, default=200)
    p.add_argument("--coverage", nargs="*", default=[], help="`samtools coverage` tables (MAPQ-filtered, one per "
                   "sample, named <sample>[.coverage].txt); enables the sex check")
    p.add_argument("--sex-female-max-y-rpm", type=float, default=50, help="chrY reads per million autosomal reads at "
                   "or below which a sample is female [50]")
    p.add_argument("--sex-male-min-y-rpm", type=float, default=200, help="chrY reads per million autosomal reads at "
                   "or above which a sample is male [200]")
    p.add_argument("--sex-min-x-sites", type=int, default=5, help="min X sites with a non-reference genotype to use "
                   "X heterozygosity [5]")
    p.add_argument("--sex-xx-min-het-fraction", type=float, default=0.2, help="X het / (het + hom-alt) at or above "
                   "which a sample has two X chromosomes [0.2]")
    p.add_argument("--prefix", default="somalier_contam")
    p.set_defaults(func=cmd_report)

    args = ap.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
