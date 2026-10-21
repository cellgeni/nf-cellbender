# cellgeni/multiqc

## Summary

Runs [MultiQC](https://docs.seqera.io/multiqc) over a set of files and writes one HTML report.
The files can be outputs of tools MultiQC supports, or custom content: `*_mqc.json`, `*_mqc.yaml`,
`*_mqc.tsv` tables and plots, `*_mqc.png` images.

The outputs always have the same names, `multiqc_report.html` and `multiqc_data/`, even when the
config sets a report title (which would otherwise rename them). Pipelines can publish them without
knowing the config.

Container: `quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2`.

## Inputs

| Name | Type | Description |
|---|---|---|
| `multiqc_files` | files | Files for MultiQC to search, staged under `multiqc_input/`. Usually a collected channel. |
| `multiqc_config` | file | Optional MultiQC config YAML. Pass `[]` to use MultiQC's defaults. |

## Outputs

| Name | File(s) | Description |
|---|---|---|
| `report` | `multiqc_report.html` | The report. |
| `data` | `multiqc_data/` | Parsed data, plot data and logs behind the report. |
| `versions` | `versions.yml` | MultiQC version. |

## Configuration via `ext` variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `ext.args` | string | `""` | Extra MultiQC arguments, e.g. `"--title 'My run' --comment 'Batch 3'"`. `--force`, `--filename` and `--config` are set by the module. |

## Usage

```nextflow
include { MULTIQC } from 'cellgeni/multiqc'

MULTIQC(
    channel.fromPath('qc/*_mqc.*').collect(),
    file('assets/multiqc_config.yaml')   // or [] for defaults
)
```

## License

MIT
