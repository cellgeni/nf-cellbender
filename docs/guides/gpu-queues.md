---
title: GPU queues and costcodes
parent: Guides
nav_order: 4
---

# GPU queues and costcodes
{: .no_toc }

1. TOC
{:toc}

CellBender runs on a GPU. Choose the LSF queue with `--gpuqueue`:

| `--gpuqueue` | Costcode | Notes |
|---|---|---|
| `gpu` (default) | Not allowed | The shared farm22 GPU queue |
| `cub22-inference` | Required | Billed to the costcode |
| `tiger22-inference` | Required | Billed to the costcode |

```bash
nextflow run cellgeni/nf-cellbender -r main --samples samples.csv \
    --gpuqueue cub22-inference --costcode s1234
```

The costcode is passed to LSF as `-G <costcode>`. It is trimmed and lowercased, so `S1234` and
` s1234 ` both become `s1234`.

{: .warning }
A costcode is rejected on the `gpu` queue: it usually means `--gpuqueue` was forgotten and the jobs
would go to the wrong queue. A `cub` or `tiger` queue without a costcode is rejected as well.

## Resources

Each CellBender job asks for:

| Resource | Value | On retry |
|---|---|---|
| CPUs | 2 | Unchanged |
| Memory | 30 GB | 30 GB × attempt |
| GPU | 1, shared mode, 8,000 MB GPU memory | Unchanged |

These are set in
[`configs/cellbender_removebackground.config`](https://github.com/cellgeni/nf-cellbender/blob/main/configs/cellbender_removebackground.config).
To change them for one run, give your own config with `-c`:

```groovy
// my.config
process {
  withName: '.*CELLBENDER_REMOVEBACKGROUND_V0[23]' {
    memory = { 60.GB * task.attempt }
  }
}
```

```bash
nextflow run cellgeni/nf-cellbender -r main --samples samples.csv -c my.config
```

The other steps run on CPU queues: the iRODS download on `transfer` (at most 5 at a time), QC and
MultiQC on `normal`.
