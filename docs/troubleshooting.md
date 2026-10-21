---
title: Troubleshooting
nav_order: 5
---

# Troubleshooting
{: .no_toc }

Find the error message you got, then the fix.

1. TOC
{:toc}

## Before the run starts

### `The following invalid input values have been detected`

A parameter or combination of parameters failed validation, and nothing was submitted. The text in
brackets after each line says what to change. For example:

| Message | Fix |
|---|---|
| `--gpuqueue (gpu-normal): Expected any of [gpu, cub22-inference, tiger22-inference]` | Use one of the listed queues |
| `Missing required parameter(s): costcode (...required for cub and tiger queues)` | Add `--costcode` |
| `--costcode (s1): Expected null (...only used with cub and tiger queues)` | Remove `--costcode`, or add `--gpuqueue cub22-inference` |
| `--estimator (mean): Expected null (...only available for CellBender 0.3)` | Remove it, or use `--version 0.3` |
| `--exclude_features (Peaks): Expected All (...)` | CellBender 0.2 only takes `All` |
| `Object does not have some of the required properties [droplets] (...)` | With CellBender 0.2, give `--cells` and `--droplets` together |
| `--samples (samples.csv): Validation of file failed: ... duplicate entries` | Make every `id` in the table unique |

The extra line `Value matches against schema from 'if' but does not match against schema from
'then'` is printed under every failed rule; ignore it. [Parameters](reference/parameters.md) lists
every rule.

### Only a short usage message is printed

`--samples` is missing. If you used `--sample_table`, it was renamed to `--samples`, and
`--output_dir` to `--outdir`.

### `WARN: The following invalid input values have been detected: * --foo: 1`

An unknown parameter is only a warning, and the run goes ahead without it. Check its spelling
and, after an upgrade, the [changelog](changelog.md) for renamed parameters.

### `nextflow run -preview` never finishes

Known Nextflow behaviour with workflow outputs: when validation passes, `-preview` waits forever for
outputs that are never produced. Use it only to check that parameters are rejected, or test with
`-stub` instead.

## Downloading from iRODS

### `CAT_NO_ACCESS_PERMISSION`

```
ERROR: getUtil: get error for multiplex-flex/README.md status = -818000 CAT_NO_ACCESS_PERMISSION
```

Your iRODS account can list the collection but not read its files. Retries will not help: stop the
run, get read access as described in [Data on iRODS](guides/irods.md#giving-the-pipeline-access),
then rerun with `-resume`.

### `CAT_INVALID_USER` from `ichmod`

The user was given without its zone. On `/archive` paths write `ab76#Sanger1` for a user, or
`cellgeni#archive` for the team group.

### `CAT_INVALID_AUTHENTICATION`

The account running the iRODS command is not logged in to iRODS. Run `iinit` and try again; for a
service account, use its iRODS password.

## While the run is going

### `Disk quota exceeded`

On `/lustre/scratch124`, files owned by your primary Unix group (for example `team278`) count
against that group's quota, which can be as small as 1 MB. Files created under a folder owned by the
`cellgeni` group normally inherit `cellgeni`, but a tool that writes in `/tmp` and then copies the
result into the work folder brings the primary group with it.

Check:

```bash
lfs quota -h -g team278 /lustre/scratch124
find nf-work -group team278 | head
```

Start the run from a folder in the `cellgeni` group. The MultiQC module already keeps its temporary
files inside the work folder for this reason; if another tool hits it, tell the developers which
one.

### CellBender keeps failing on one sample

Look at the task's `.command.log` in `nf-work/` (the run log prints the folder). Common causes:

- **`Error: Input directory does not contain expected structure`**: `path` is not one of the layouts
  in [Cell and droplet counts](guides/cell-calls.md#inputs-the-pipeline-recognises).
- **`ERROR: Mapper preset is not available for ... input type`**: CellBender 0.2, or 0.3 with
  `--mapper_preset`, on a bare `.h5` or `.mtx` input. Give `--cells` and `--droplets`.
- **Out of GPU or host memory**: memory grows with each retry. If it fails on every attempt, raise
  it with your own config (see [GPU queues](guides/gpu-queues.md#resources)).

To let the other samples finish while you look into it, rerun with `--ignore_failed -resume`.

## In the QC report

### The soup fraction is `NA`

The sample ran with CellBender 0.2, whose output does not store the soup fraction, and its input
matrix could not be read at QC time. See [QC report](reference/qc.md#summary-columns).

### A sample is missing from the report

Its CellBender task failed and was ignored (`--ignore_failed`), or its folder holds no
`cellbender.log`. The QC log in `nf-work/` names every skipped folder.
