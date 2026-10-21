# cellgeni/irods/loadcatalog

## Summary

Downloads a whole iRODS collection into `${meta.id}/`, keeping the collection's folder layout.
Files whose extension is in `ext.ignore_extensions` are skipped, so large files a downstream
tool does not need (BAM, CRAM, FASTQ) are never transferred.

The module:

1. lists the collection recursively with `ils -r` and turns the listing into full paths
   (`ils2paths.awk`);
2. drops files ending in one of the ignored extensions;
3. downloads each remaining file with `iget` into the same relative path under `${meta.id}/`.

It has no container: it runs the icommands installed on the host, with the user's iRODS login.
Run `iinit` before starting the pipeline.

## Inputs

| Name | Type | Description |
|---|---|---|
| `meta.id` | string | Sample name, used as the output folder name. |
| `catalog` | string | iRODS collection to download, e.g. `/archive/cellgeni/tests/cellranger-count`. A trailing `/` is ignored. |

## Outputs

| Name | File(s) | Description |
|---|---|---|
| `catalog` | `${meta.id}/` | The downloaded collection. |
| `versions` | `versions.yml` | iRODS version record. |

## Configuration via `ext` variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `ext.ignore_extensions` | string | `""` (download everything) | Comma-separated extensions to skip, e.g. `"bam,cram,fastq.gz"`. |
| `ext.args` | string | `"-f -v -K -X restartfile.txt --retries 5"` | Arguments for `iget`: overwrite, verbose, verify checksums, restart file, retries. |

```groovy
withName: ".*IRODS_LOADCATALOG" {
    ext.ignore_extensions = "bam,cram,fastq,fq,fastq.gz,fq.gz"
    queue                 = 'transfer'
    maxForks              = 5
    cpus                  = 1
    memory                = { 2.GB * task.attempt }
}
```

`ils2paths.awk` is called with `awk -f` from the module folder, so the module works without
`nextflow.enable.moduleBinaries` and even if the script lost its executable bit on install.

## Usage

```nextflow
include { IRODS_LOADCATALOG } from 'cellgeni/irods/loadcatalog'

IRODS_LOADCATALOG(
    channel.of([[id: 'sample1'], '/archive/cellgeni/tests/cellranger-count'])
)
```

## License

MIT
