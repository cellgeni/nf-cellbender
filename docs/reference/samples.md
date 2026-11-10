---
title: Samples table
parent: Reference
nav_order: 2
---

# Samples table
{: .no_toc }

1. TOC
{:toc}

## Format

A comma-separated `.csv` file passed with `--samples`, with a header row and these columns:

| Column | Required | Rules |
|---|---|---|
| `id` | Yes | Sample name, used for the output folder. Unique across the table, no spaces. |
| `group` | No | Dataset the sample belongs to. Letters, digits, `.`, `_` and `-`, starting with a letter or digit; not `index` or `versions.yml`. See [Groups](#groups). |
| `path` | Yes | No spaces. A CellRanger or STARsolo output folder, a `.h5` file or a `.mtx` folder; with `--on_irods`, an iRODS collection. |

```
id,path
cellranger-count,/lustre/scratch124/.../cellranger-count
cellranger-count-h5,/lustre/scratch124/.../outs/raw_feature_bc_matrix.h5
```

The table is checked against
[`assets/schema_samples.json`](https://github.com/cellgeni/nf-cellbender/blob/main/assets/schema_samples.json)
before the run starts. A duplicate `id` or a missing column stops it with, for example:

```
* --samples (samples.csv): Validation of file failed:
	-> Entry 2: Detected duplicate entries: [id:s1]
```

The folder layouts the pipeline recognises are listed in
[Cell and droplet counts](../guides/cell-calls.md#inputs-the-pipeline-recognises).

## Groups

Without a `group` column all samples are checked in one QC report, and the outputs go to
`results/cellbender/` and `results/qc_report/`. With it, the samples of each group get their own
QC report, and everything of a group goes to `results/<group>/` (see
[Outputs](outputs.md#layout)):

```
id,group,path
cellranger-count,gex,/lustre/scratch124/.../cellranger-count
starsolo,gex,/lustre/scratch124/.../starsolo
cellranger-arc,multiome,/lustre/scratch124/.../cellranger-arc
```

Once the column is there, every sample needs a group. A sample without one stops the run before
anything is submitted:

```
--samples (samples.csv): no group for starsolo. Give every sample a group, or leave the group column out.
```

Sample `id`s stay unique across the whole table, not only within a group.

## Example tables

| File | Contents |
|---|---|
| [`examples/samples.csv`](https://github.com/cellgeni/nf-cellbender/blob/main/examples/samples.csv) | Local CellRanger and STARsolo folders, `.h5` files and `.mtx` folders |
| [`examples/samples_irods.csv`](https://github.com/cellgeni/nf-cellbender/blob/main/examples/samples_irods.csv) | iRODS collections, for `--on_irods` |
| [`examples/samples_preset.csv`](https://github.com/cellgeni/nf-cellbender/blob/main/examples/samples_preset.csv) | Whole mapper folders only, for the mapper preset |
| [`examples/samples_exclude_features.csv`](https://github.com/cellgeni/nf-cellbender/blob/main/examples/samples_exclude_features.csv) | A mix of library types (ARC, CRISPR, multiplexed, Flex) on iRODS, for trying `--exclude_features` |
| [`examples/samples_groups.csv`](https://github.com/cellgeni/nf-cellbender/blob/main/examples/samples_groups.csv) | Local folders split into three groups, one QC report each |

[`examples/run_cellbender.sh`](https://github.com/cellgeni/nf-cellbender/blob/main/examples/run_cellbender.sh)
is a complete run script using one of them.

## Index files

Each run writes the same format back out, so its outputs can be the input of the next run:

| File | Lists |
|---|---|
| `results/index/cellbender.csv` | The CellBender output folder of each sample |
| `results/index/raw.csv` | The folders downloaded from iRODS (empty without `--on_irods`) |

```
"id","path"
"sample_a","/lustre/scratch124/.../results/cellbender/sample_a"
```

Values are quoted; the pipeline reads quoted and unquoted tables alike. With a `group` column in
the samples table, the index files have it too (`"id","group","path"`), so the groups carry over to
the next run. `index/raw.csv` is the useful one to feed back: it reruns CellBender without
downloading again (see [Data on iRODS](../guides/irods.md#reusing-a-download)).
