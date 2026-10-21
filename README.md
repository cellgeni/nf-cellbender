# nf-cellbender

Runs [CellBender](https://cellbender.readthedocs.io/en/latest/) `remove-background` on Sanger's
farm22 for a table of samples, and builds one QC report across all of them. Inputs can be
CellRanger or STARsolo output folders, `.h5` files or `.mtx` folders, on Lustre or on iRODS.
CellBender 0.2 and 0.3 are both supported and run on the GPU queues.

**Documentation: <https://cellgeni.github.io/nf-cellbender/>**

## Quick start

```bash
module load cellgen/nextflow/26.04.6

nextflow run cellgeni/nf-cellbender -r main --samples samples.csv
```

`samples.csv` has an `id` and a `path` column, one row per sample:

```
id,path
sample1,/lustre/scratch124/.../sample1/cellranger
sample2,/lustre/scratch124/.../sample2/outs/raw_feature_bc_matrix.h5
```

Results are written to `results/`: CellBender output per sample in `results/cellbender/`, the QC
report in `results/qc_report/`. Run `nextflow run cellgeni/nf-cellbender -r main --help` for the
parameters.

## Documentation

| Page | |
|---|---|
| [Getting started](https://cellgeni.github.io/nf-cellbender/getting-started/) | First run, samples table, help and validation |
| [Guides](https://cellgeni.github.io/nf-cellbender/guides/) | CellBender 0.2 or 0.3, cell counts, iRODS, GPU queues, reruns |
| [Reference](https://cellgeni.github.io/nf-cellbender/reference/) | Parameters, samples table, outputs, QC report |
| [Troubleshooting](https://cellgeni.github.io/nf-cellbender/troubleshooting/) | Error messages and their fixes |
| [Developers](https://cellgeni.github.io/nf-cellbender/developers/) | Layout, modules, tests, releases |

The pages are also readable on GitHub in [`docs/`](docs/).

## Repository

| Path | Contents |
|---|---|
| `main.nf`, `workflow/` | The pipeline |
| `nextflow.config`, `configs/` | Global and per-process settings |
| `nextflow_schema.json`, `assets/` | Parameter and samples table schemas, MultiQC config |
| `modules/cellgeni/` | CellBender, QC and MultiQC modules, also published to the Nextflow registry |
| `examples/`, `resume/` | Example samples tables and run scripts |
| `docker/` | Dockerfiles for the CellBender images |
| `tests/` | nf-test configuration and the LSF test runner |
| `docs/` | Documentation site |

## Changes

See the [changelog](docs/changelog.md).

## Licence

[MIT](LICENSE)
