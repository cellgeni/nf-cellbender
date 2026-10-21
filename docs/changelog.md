---
title: Changelog
nav_order: 7
---

# Changelog
{: .no_toc }

All notable changes to nf-cellbender. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Releases are tagged `YY-DDD`: the year
and the day of the year.

1. TOC
{:toc}

## [Unreleased]

### Changed

- The iRODS download module is now a registry module, `cellgeni/irods/loadcatalog`. It skips
  nothing when no extensions are given, matches extensions after a literal dot, no longer fails
  when every file in a collection is skipped, and calls `ils2paths.awk` through `awk -f`, so it
  works even when the executable bit is lost on install.

## [26-294] - 2026-10-21

### Breaking

- Nextflow 26.04 or later is required (was `>=25.04.4, <25.10.0`).
- `--sample_table` is renamed `--samples`, and `--output_dir` is renamed `--outdir`. The example
  tables are now `examples/samples*.csv`.
- Combinations that used to be silently ignored now fail validation:
  - `--costcode` with the `gpu` queue;
  - `--estimator`, `--force_empty_umi_prior` or `--mapper_preset` with CellBender 0.2;
  - `--exclude_features` other than `All` with 0.2, or `All` with 0.3;
  - only one of `--cells` / `--droplets` with 0.2;
  - `--ignore_extensions` without `--on_irods`.
- The QC report is a summary TSV, one PDF and a MultiQC HTML report, replacing `train.pdf`,
  `prob.pdf`, `soup.pdf` and the per-sample `.rds` files.
- Process names changed: `CELLBENDER_REMOVEBACKGROUND` is now
  `CELLBENDER:CELLBENDER_REMOVEBACKGROUND_V02` or `_V03`, and `QualityControl` is now
  `CELLBENDER_QC` plus `MULTIQC`. Custom configs that select processes by name need updating.

### Added

- `--gpuqueue` (`gpu`, `cub22-inference`, `tiger22-inference`; default `gpu`) and `--costcode`,
  which is required on `cub` and `tiger` queues, then trimmed, lowercased and passed to LSF as
  `-G`.
- Parameter and samples table validation with nf-schema 3.0.0. `--help`, `--help <param>` and
  `--helpFull` are generated from `nextflow_schema.json`, and running without `--samples` prints a
  short usage message.
- Separate CellBender 0.2 and 0.3 modules, each pinned to its container, published to the
  Nextflow registry as `cellgeni/cellbender/removebackground_v02` and `_v03`.
- A Python QC module, `cellgeni/cellbender/qc`, and a MultiQC module, `cellgeni/multiqc`, both
  published to the registry.
- `index/cellbender.csv` and `index/raw.csv` in the output, in the samples table format, and a
  `versions.yml` for the whole run.
- This documentation site.

### Changed

- Outputs are published through Nextflow workflow outputs instead of per-process `publishDir`.
- Per-process settings live in `configs/<process>.config`. The pipeline is split into `main.nf`
  and a `CELLBENDER` subworkflow in `workflow/main.nf`.
- On retry only memory grows; CPUs stay fixed.
- `--ignore_failed` now drops a sample only after its final attempt. It used to give up one
  attempt early.
- `--estimator` and `--ignore_extensions` default to unset. CellBender 0.3 still uses `mckp`, and
  the iRODS skip list is unchanged.
- The CellBender GPU request is 8,000 MB of GPU memory (was 6,000 MB).
- QC soup fraction statistics are computed over called cells for both CellBender versions.
- MultiQC keeps its temporary files in the work folder, which avoids "Disk quota exceeded" from
  files copied out of `/tmp` with the wrong group.

### Fixed

- `--ignore_failed` had no effect because the parameter was misspelt (`ingore_failed`).
- The QC now reads the 0.2 log's "Prior on counts in empty droplets".
- The manifest's home page and description no longer point to nf-irods-to-fastq.

### Removed

- `.nf-core.yml`: the pipeline no longer follows nf-core conventions.
- `bin/cellbender_qc.R`, replaced by the Python QC module.

## [25-274] - 2025-10-01

### Added

- An nf-core style CellBender module that recognises CellRanger count, multi, ARC and ATAC,
  STARsolo, `.h5` and `.mtx` inputs by their folder structure, including CellRanger folders
  without `outs/`.
- A mapper preset that estimates expected cells, total droplets and the low-count threshold from
  the mapper output (`preset.sh`, `count_cells.awk`, `sort_cells.awk`).
- `--starsolo_mapper` to choose the STARsolo matrix type, and `--force_empty_umi_prior`.
- Several `--exclude_features` types at once.
- `IRODS_LOADCATALOG`, which downloads whole iRODS collections with retries and restart files and
  skips unwanted extensions (`--ignore_extensions`).
- An nf-test suite with snapshots, `meta.yml` files for the modules, and an LSF script that runs
  the tests in parallel.
- New example tables and scripts, and an updated `resume/` script.

### Changed

- The estimator parameter and argument handling of the CellBender process.

## [25-056] - 2025-02-25

### Added

- `--exclude_features`, to exclude feature types from the analysis.
- `--min_umi`, to set the empty-droplet UMI threshold.
- Separate Dockerfiles for CellBender 0.2 and 0.3, with `gawk`.
- New example scripts and samples tables for CellRanger and STARsolo outputs.
- The project licence.

### Changed

- The samples table is a `.tsv` file, and input and output are carried in a single channel so
  samples cannot be mixed up.
- Execution reports go to `execution-reports/`, and the work folder is called `nf-work`.
- The help message, parameter handling and resources of the CellBender process were reworked.

### Removed

- Obsolete container parameters and example scripts.

## [23-314] - 2023-11-10

### Added

- CellBender 0.3.0 support, with QC parsing updated for the 0.3.0 output format.

## [23-190] - 2023-09-13

### Changed

- Clearer handling of the samples file, file permissions, and a re-enabled work folder cleanup.
- README and `RESUME-cellbender` updates, including the missing `-r` flag.

## [23-103] - 2023-04-13

### Added

- First release: CellBender on farm22 through Nextflow for a table of samples, with the R QC
  script, a Dockerfile, a resume script and example tables.

[Unreleased]: https://github.com/cellgeni/nf-cellbender/compare/26-294...dev
[26-294]: https://github.com/cellgeni/nf-cellbender/compare/25-274...26-294
[25-274]: https://github.com/cellgeni/nf-cellbender/compare/25-056...25-274
[25-056]: https://github.com/cellgeni/nf-cellbender/compare/23-314...25-056
[23-314]: https://github.com/cellgeni/nf-cellbender/compare/23-190...23-314
[23-190]: https://github.com/cellgeni/nf-cellbender/compare/23-103...23-190
[23-103]: https://github.com/cellgeni/nf-cellbender/releases/tag/23-103
