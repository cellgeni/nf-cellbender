# cellgeni/adata/convert

## Summary

Converts a single-cell matrix to an AnnData `.h5ad` store with
[adata-cli](https://cellgeni.github.io/adata-cli/) (`adata convert`), streaming it from disk rather
than loading it into memory. It reads Cell Ranger `.h5` files, CellBender outputs (keeping their
latent variables), `.mtx` folders, loom, MuData and more; see
[Convert formats](https://cellgeni.github.io/adata-cli/guides/convert/).

The output format follows `ext.extension`: `h5ad` by default, or `zarr`, `loom`, `h5` (10x HDF5)
and the other formats `adata convert` writes.

Container: `quay.io/cellgeni/adata-cli:0.17.5`.

## Inputs

| Name | Type | Description |
|---|---|---|
| `meta` | map | Sample metadata, passed through. Must contain `id`, the default output name. |
| `input` | file | The matrix to convert, staged under `input/`. A tuple with `meta`: `[meta, file]`. |

## Outputs

| Name | File(s) | Description |
|---|---|---|
| `converted` | `<prefix>.<extension>` | Tuple of `meta` and the converted store. |
| `versions_adata` | | Tuple of the process name, `adata` and its version, also sent to the `versions` topic. |

## Configuration via `ext` variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `ext.prefix` | string | `meta.id` | Output file name without the extension. |
| `ext.extension` | string | `h5ad` | Output extension, which picks the format. |
| `ext.args` | string | `""` | Extra `adata convert` arguments, e.g. `--var-names gene_symbols --make-unique` or `--min-cell-probability 0.5`. |

Features are named by gene id by default, with the symbols in `var["gene_symbols"]`; scanpy's
readers name them by symbol (`--var-names gene_symbols`).

## Usage

```nextflow
include { ADATA_CONVERT } from 'cellgeni/adata/convert'

// CellBender's filtered output to cellbender_filtered.h5ad (ext.prefix = 'cellbender_filtered')
ADATA_CONVERT(channel.of([[id: 'sample1'], file('results/sample1/cellbender_filtered.h5')]))
```

## License

MIT
