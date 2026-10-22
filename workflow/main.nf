// IMPORT MODULES
include { IRODS_LOADCATALOG } from '../modules/cellgeni/irods/loadcatalog'
include { CELLBENDER_REMOVEBACKGROUND_V02 } from '../modules/cellgeni/cellbender/removebackground_v02'
include { CELLBENDER_REMOVEBACKGROUND_V03 } from '../modules/cellgeni/cellbender/removebackground_v03'

workflow CELLBENDER {
    take:
    samples   // channel: [ val(meta), path ] one row of the sample table per sample
    on_irods  // boolean: sample paths are iRODS collections, download them first
    version   // string: CellBender version to run, "0.2" or "0.3"

    main:
    // STEP 0: Init channels
    raw        = channel.empty()
    outputdir  = channel.empty()
    versions   = channel.empty()

    // STEP 1: Download the data from iRODS
    if (on_irods) {
        IRODS_LOADCATALOG(samples)
        raw      = IRODS_LOADCATALOG.out.catalog
        samples  = raw
        versions = versions.mix(IRODS_LOADCATALOG.out.versions.first())
    }

    // STEP 2: Run CellBender with the module pinned to the requested version
    if (version == '0.2') {
        CELLBENDER_REMOVEBACKGROUND_V02(samples)
        outputdir = CELLBENDER_REMOVEBACKGROUND_V02.out.outputdir
        versions  = versions.mix(CELLBENDER_REMOVEBACKGROUND_V02.out.versions.first())
    }
    else {
        CELLBENDER_REMOVEBACKGROUND_V03(samples)
        outputdir = CELLBENDER_REMOVEBACKGROUND_V03.out.outputdir
        versions  = versions.mix(CELLBENDER_REMOVEBACKGROUND_V03.out.versions.first())
    }

    emit:
    raw       = raw        // channel: [ val(meta), path(dir) ] iRODS downloads (empty without on_irods)
    outputdir = outputdir  // channel: [ val(meta), path(dir) ] CellBender output folder per sample
    versions  = versions   // channel: [ path(versions.yml) ]
}
