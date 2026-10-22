---
title: Reruns and failures
parent: Guides
nav_order: 5
---

# Reruns and failures
{: .no_toc }

1. TOC
{:toc}

## Retries

Every task is retried up to 5 times after a failure. Memory grows with each attempt (for
CellBender 30 GB, 60 GB, 90 GB, …); CPUs stay the same.

By default the run stops if a CellBender task still fails after its last retry. With
`--ignore_failed`, that sample is dropped instead and the others carry on to the QC report:

```bash
nextflow run cellgeni/nf-cellbender -r main --samples samples.csv --ignore_failed
```

Only CellBender tasks are ignored this way. The failed sample is missing from `results/cellbender/`
and from the QC report, so check the run log for `NOTE: ... Error is ignored`.

{: .note }
Some failures never go away on retry, such as an iRODS permission error. Fix the cause and
resume instead of waiting for all retries; see [Troubleshooting](../troubleshooting.md).

## Continuing a run

Run the same command again with `-resume` from the same folder. Finished tasks are reused from
`nf-work/` and only the rest run:

```bash
nextflow run cellgeni/nf-cellbender -r main --samples samples.csv -resume
```

`-resume` only works while `nf-work/` still holds the earlier tasks. The pipeline keeps the work
folder after a run, so a finished run can be resumed too, for example with a changed parameter.
`nf-work/` can be large: delete it once the results are checked.

## A ready-made resume script

[`resume/RESUME-cellbender`](https://github.com/cellgeni/nf-cellbender/blob/main/resume/RESUME-cellbender)
loads Nextflow, checks that `samples.csv` exists and runs the published pipeline with `-resume`.
Copy it and `resume/samples.csv` into your run folder, edit the table and run the script.
