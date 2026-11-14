// IMPORT MODULES
include { IRODS_LOADCATALOG } from '../modules/cellgeni/irods/loadcatalog'
include { CELLBENDER_REMOVEBACKGROUND_V02 } from '../modules/cellgeni/cellbender/removebackground_v02'
include { CELLBENDER_REMOVEBACKGROUND_V03 } from '../modules/cellgeni/cellbender/removebackground_v03'
include { ADATA_CONVERT } from '../modules/cellgeni/adata/convert'

workflow CELLBENDER {
    take:
    samples   // channel: [ val(meta), path, cells, droplets, min_umi, exclude_features ] one per sample;
              // cells/droplets/min_umi are integers or null, exclude_features a list of feature types
    on_irods  // boolean: sample paths are iRODS collections, download them first
    version   // string: CellBender version to run, "0.2" or "0.3"
    to_h5ad   // boolean: convert each cellbender_filtered.h5 to cellbender_filtered.h5ad

    main:
    // STEP 0: Init channels
    raw       = channel.empty()
    outputdir = channel.empty()
    h5        = channel.empty()
    files     = channel.empty()
    h5ad      = channel.empty()

    // STEP 1: Download the data from iRODS, then put the per-sample values back next to each download
    if (on_irods) {
        IRODS_LOADCATALOG(samples.map { meta, path, _cells, _droplets, _min_umi, _exclude -> [meta, path] })
        raw     = IRODS_LOADCATALOG.out.catalog
        samples = raw.join(samples.map { meta, _path, cells, droplets, min_umi, exclude -> [meta, cells, droplets, min_umi, exclude] })
    }

    // STEP 2: Run CellBender with the module pinned to the requested version. Its files come out by
    // extension; joined per sample, so each sample is published as soon as it is done
    if (version == '0.2') {
        CELLBENDER_REMOVEBACKGROUND_V02(samples)
        outputdir = CELLBENDER_REMOVEBACKGROUND_V02.out.outputdir
        h5        = CELLBENDER_REMOVEBACKGROUND_V02.out.h5
        files     = h5
            .join(CELLBENDER_REMOVEBACKGROUND_V02.out.csv)
            .join(CELLBENDER_REMOVEBACKGROUND_V02.out.pdf)
            .join(CELLBENDER_REMOVEBACKGROUND_V02.out.log)
            .map { meta, h5_files, csv, pdf, log -> [meta, [h5_files, csv, pdf, log].flatten()] }
    }
    else {
        CELLBENDER_REMOVEBACKGROUND_V03(samples)
        outputdir = CELLBENDER_REMOVEBACKGROUND_V03.out.outputdir
        h5        = CELLBENDER_REMOVEBACKGROUND_V03.out.h5
        files     = h5
            .join(CELLBENDER_REMOVEBACKGROUND_V03.out.csv)
            .join(CELLBENDER_REMOVEBACKGROUND_V03.out.pdf)
            .join(CELLBENDER_REMOVEBACKGROUND_V03.out.html)
            .join(CELLBENDER_REMOVEBACKGROUND_V03.out.log)
            .map { meta, h5_files, csv, pdf, html, log -> [meta, [h5_files, csv, pdf, html, log].flatten()] }
    }

    // STEP 3: The cells as an AnnData store, for downstream analysis
    if (to_h5ad) {
        ADATA_CONVERT(h5.map { meta, h5_files -> [meta, [h5_files].flatten().find { file -> file.name == 'cellbender_filtered.h5' }] })
        h5ad = ADATA_CONVERT.out.converted
    }

    // Software versions go to the 'versions' topic, collected in main.nf

    emit:
    raw       = raw        // channel: [ val(meta), path(dir) ] iRODS downloads (empty without on_irods)
    outputdir = outputdir  // channel: [ val(meta), path(dir) ] CellBender output folder per sample
    files     = files      // channel: [ val(meta), [ path ] ] every CellBender output file per sample
    h5ad      = h5ad       // channel: [ val(meta), path(h5ad) ] cells as .h5ad (empty without to_h5ad)
}
