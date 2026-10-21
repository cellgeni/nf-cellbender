---
title: Developers
nav_order: 6
---

# Developers
{: .no_toc }

1. TOC
{:toc}

## Repository layout

| Path | Contents |
|---|---|
| `main.nf` | Entry point: help text, parameter validation, loading the samples table, QC, MultiQC, and the `output {}` block that decides what is published where |
| `workflow/main.nf` | The `CELLBENDER` subworkflow: optional iRODS download, then the CellBender module for `--version` |
| `nextflow.config` | Default parameters, LSF executor, Singularity, nf-schema plugin, output folder |
| `configs/<process>.config` | Per-process settings: queue, resources, `ext` arguments |
| `nextflow_schema.json` | Parameter types, defaults, allowed values and cross-parameter rules; drives validation and `--help` |
| `assets/schema_samples.json` | Format of the `--samples` table |
| `assets/multiqc_config.yaml` | MultiQC report title, intro and section order |
| `modules/cellgeni/` | Modules in Nextflow registry layout (see below) |
| `examples/` | Example samples tables and a run script |
| `resume/` | A script for resuming a run of the published pipeline |
| `docker/` | Dockerfiles for the CellBender 0.2 and 0.3 images |
| `tests/` | nf-test config and the LSF script that runs the test suite |
| `docs/` | This site |

## Branches

`main` holds the released pipeline and `dev` the next release. The `nextflow-tower` branch has a
version of the pipeline for running from Nextflow Tower.

## Modules

| Module | Process | Container |
|---|---|---|
| `cellgeni/cellbender/removebackground_v02` | `CELLBENDER_REMOVEBACKGROUND_V02` | `quay.io/cellgeni/cellbender:0.2` |
| `cellgeni/cellbender/removebackground_v03` | `CELLBENDER_REMOVEBACKGROUND_V03` | `quay.io/cellgeni/cellbender:0.3` |
| `cellgeni/cellbender/qc` | `CELLBENDER_QC` | `quay.io/cellgeni/cellbender:0.3` |
| `cellgeni/multiqc` | `MULTIQC` | `quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2` |
| `cellgeni/irods/loadcatalog` | `IRODS_LOADCATALOG` | none: the host's icommands |

The `cellgeni/` module folders have `main.nf`, `meta.yml` (module schema v1), a `README.md` with its inputs,
outputs and `ext` variables, and `tests/`. They are published to the
[Nextflow module registry](https://registry.nextflow.io/); `.module-info` records the published
checksum. `main.nf` includes them by relative path.

To publish a new module version, bump `version` in its `meta.yml`, then:

```bash
nextflow module validate modules/cellgeni/multiqc
nextflow module publish modules/cellgeni/multiqc -dry-run
nextflow module publish modules/cellgeni/multiqc
```

## Process configuration

Each `withName` pattern in `configs/` starts with `.*`, so it still matches when a process is
called from a subworkflow (the CellBender processes run as
`CELLBENDER:CELLBENDER_REMOVEBACKGROUND_V0x`). `ext` variables carry the pipeline parameters into
the modules; for example `configs/cellbender_removebackground.config` builds the CellBender
arguments for each version.

## Parameters and validation

To add or change a parameter:

1. Add its default to `params {}` in `nextflow.config`. Use `null` for "not set", so the schema
   can tell whether the user gave it.
2. Describe it in `nextflow_schema.json`: type, description, `help_text`, allowed values. For
   options that only make sense with another option, add an `if`/`then` rule in the root `allOf`
   with an `errorMessage`; the existing rules show the pattern.
3. Regenerate the [parameter reference](reference/parameters.md):

   ```bash
   python3 docs/_scripts/schema_to_md.py
   ```

4. Check the rule with a run that should fail; validation errors stop the run before anything is
   submitted.

## Tests

The module tests use [nf-test](https://www.nf-test.com/) and run on the farm:

```bash
mkdir -p logs
N=29
bsub -J "test-cellbender[1-$N]" -env "all, N=$N" < tests/scripts/run_tests.bsub
```

`N` is the number of tests; each LSF array job runs one shard. Count the results with:

```bash
echo "PASSED: $(grep -l "PASSED" logs/*Output*.log | wc -l), FAILED: $(grep -l "FAILURE" logs/*Output*.log | wc -l), RUNNING $(grep -L "Your job looked like:" logs/*Output*.log | wc -l)"
echo "FAILED TEST LIST:"; grep -l "FAILURE" logs/*Output*.log
```

To run one module's tests directly:

```bash
module load cellgen/nextflow/26.04.6 cellgen/nf-test/0.9.5
nf-test test modules/cellgeni/multiqc/tests/main.nf.test --profile singularity
```

For a quick check of the whole pipeline without GPUs, run it with `-stub` and the local executor.

## Docker images

`docker/Dockerfile_v2` and `docker/Dockerfile_v3` build the CellBender 0.2.2 and 0.3.2 images on
`nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04`. The built images are on
[quay.io/cellgeni/cellbender](https://quay.io/repository/cellgeni/cellbender?tab=tags), and a
Singularity copy is cached in `/nfs/cellgeni/singularity/images/`.

## Releasing

Releases are tagged with the year and day of the year, `YY-DDD` (for example `26-294` for
2026-10-21):

1. Move the `[Unreleased]` entries in [`docs/changelog.md`](changelog.md) under a new heading with
   the tag and date.
2. Set `manifest.version` in `nextflow.config` to the same tag.
3. Merge to `main`, tag the merge commit, and create a GitHub release with the changelog entry.

## Documentation

The site is built by GitHub Pages from `docs/` on `main`, with the
[Just the Docs](https://just-the-docs.com/) theme. Each page needs front matter with `title`,
`nav_order` and, under a section, `parent`. To preview locally:

```bash
cd docs
singularity exec docker://jekyll/jekyll:4.2.2 sh -c \
    'gem install --user-install jekyll-remote-theme >/dev/null && jekyll serve --host 0.0.0.0'
```
