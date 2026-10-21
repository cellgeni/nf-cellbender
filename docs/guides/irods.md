---
title: Data on iRODS
parent: Guides
nav_order: 3
---

# Data on iRODS
{: .no_toc }

1. TOC
{:toc}

## Downloading sample folders

With `--on_irods`, `path` in the samples table is an iRODS collection. The pipeline downloads
each collection on the `transfer` queue before running CellBender.

```
id,path
cellranger-count,/archive/cellgeni/tests/cellranger-count
starsolo,/archive/cellgeni/tests/starsolo
```

```bash
nextflow run cellgeni/nf-cellbender -r main --samples samples_irods.csv --on_irods
```

Large files CellBender does not need are skipped: BAM/CRAM and FASTQ files in any compression.
To choose the list yourself, give comma-separated extensions:

```bash
--on_irods --ignore_extensions "bam,bz2"
```

`--ignore_extensions` without `--on_irods` is rejected, because there would be nothing to skip.

## Reusing a download

The downloaded folders are published to `results/raw/<id>/`, and `results/index/raw.csv` lists
them in the samples table format. To rerun CellBender, for example with another version or other
options, pass that file instead of downloading again:

```bash
nextflow run cellgeni/nf-cellbender -r main --samples results/index/raw.csv --version 0.2
```

## Giving the pipeline access

The pipeline downloads with your own iRODS account, so you need read access to every collection
in the table. If you can list a collection with `ils` but downloads fail with
`CAT_NO_ACCESS_PERMISSION`, the collection is readable but its files are not.

Check who has access:

```bash
ils -A /archive/cellgeni/tests/multiplex-flex
```

```
/archive/cellgeni/tests/multiplex-flex:
        ACL - cellgeni-su#Sanger1:own
        Inheritance - Disabled
```

Only the owner (here `cellgeni-su`) or an iRODS admin can change this. Logged in as the owner,
grant read access to the whole `cellgeni` group and turn on inheritance so files added later get
the same access:

```bash
ichmod -r read cellgeni#archive /archive/cellgeni/tests
ichmod -r inherit /archive/cellgeni/tests
```

{: .note }
`/archive` is its own iRODS zone, `archive`. Users belong to the `Sanger1` zone, so a single user
is written `ab76#Sanger1`; a bare `ab76` fails with `CAT_INVALID_USER`. The `cellgeni` group is
in the `archive` zone, which is why it is `cellgeni#archive`.

Afterwards, `ils -A` lists `g:cellgeni#archive:read object` on the collection and its files.

### Service accounts

When you change permissions as a service account such as `cellgeni-su`, it needs its own iRODS
login. An error like this means the account is not logged in, and nothing was changed:

```
failed with error -826000 CAT_INVALID_AUTHENTICATION
```

Check that `ienv` shows `irods_user_name - cellgeni-su` and `irods_zone_name - Sanger1`, then run
`iinit` with the account's iRODS password (not its Unix password) and try again.
