// IMPORT MODULES
include { IRODS_LOADCATALOG } from '../modules/cellgeni/irods/loadcatalog'
include { CELLBENDER_REMOVEBACKGROUND_V02 } from '../modules/cellgeni/cellbender/removebackground_v02'
include { CELLBENDER_REMOVEBACKGROUND_V03 } from '../modules/cellgeni/cellbender/removebackground_v03'

workflow CELLBENDER {
    take:
    samples   // channel: [ val(meta), path, cells, droplets, min_umi, exclude_features ] one per sample;
              // cells/droplets/min_umi are integers or null, exclude_features a list of feature types
    on_irods  // boolean: sample paths are iRODS collections, download them first
    version   // string: CellBender version to run, "0.2" or "0.3"

    main:
    // STEP 0: Init channels
    raw       = channel.empty()
    outputdir = channel.empty()

    // STEP 1: Download the data from iRODS, then put the per-sample values back next to each download
    if (on_irods) {
        IRODS_LOADCATALOG(samples.map { meta, path, _cells, _droplets, _min_umi, _exclude -> [meta, path] })
        raw     = IRODS_LOADCATALOG.out.catalog
        samples = raw.join(samples.map { meta, _path, cells, droplets, min_umi, exclude -> [meta, cells, droplets, min_umi, exclude] })
    }

    // STEP 2: Run CellBender with the module pinned to the requested version
    if (version == '0.2') {
        CELLBENDER_REMOVEBACKGROUND_V02(samples)
        outputdir = CELLBENDER_REMOVEBACKGROUND_V02.out.outputdir
    }
    else {
        CELLBENDER_REMOVEBACKGROUND_V03(samples)
        outputdir = CELLBENDER_REMOVEBACKGROUND_V03.out.outputdir
    }

    // Software versions go to the 'versions' topic, collected in main.nf

    emit:
    raw       = raw        // channel: [ val(meta), path(dir) ] iRODS downloads (empty without on_irods)
    outputdir = outputdir  // channel: [ val(meta), path(dir) ] CellBender output folder per sample
}
