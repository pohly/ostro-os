# Provides some extra logging into buildhistory of some of the inputs
# (buildhistory itself mostly concentrates on build output)
#
# Copyright (C) 2015 Intel Corporation
# Licensed under the MIT license

inherit buildhistory

# Variables to record in the "variables" file of each recipe.
#
# WARNING: changing this does not cause a rewrite of that file unless
# something causes do_populate_sysroot[_setscene] to be run again,
# like removing the tempdir and rebuilding (with or without sstate).
BUILDHISTORY_EXTRA_PKGVARS ?= "PACKAGECONFIG EXTRA_OEMAKE EXTRA_OECONF EXTRA_OECMAKE EXTRA_OESCONS EXTRA_QMAKEVARS_PRE EXTRA_QMAKEVARS_POST OE_FEATURES SUMMARY DESCRIPTION HOMEPAGE LICENSE"

BUILDHISTORY_PRESERVE += "sources metadata variables kconfig"

SSTATEPOSTINSTFUNCS_append = " buildhistory_extra_emit_pkghistory"
# We want to avoid influence the signatures of sstate tasks - first the function itself:
sstate_install[vardepsexclude] += "buildhistory_extra_emit_pkghistory"
# then the value added to SSTATEPOSTINSTFUNCS:
SSTATEPOSTINSTFUNCS[vardepvalueexclude] .= "| buildhistory_extra_emit_pkghistory"

python buildhistory_extra_emit_pkghistory() {
    bb.note('buildhistory_extra_emit_pkghistory %s' % d.getVar('BB_CURRENTTASK', True))
    if not d.getVar('BB_CURRENTTASK', True) in ['populate_sysroot', 'populate_sysroot_setscene']:
        return 0

    import codecs

    relpath = os.path.dirname(d.getVar('TOPDIR', True))
    pkghistdir = d.getVar('BUILDHISTORY_DIR_PACKAGE', True)
    if not os.path.exists(pkghistdir):
        bb.utils.mkdirhier(pkghistdir)

    # Record PV in the "latest" file. This duplicates work in
    # buildhistory_emit_pkghistory(), but we do not know whether
    # that will run (it gets skipped for recipes which never
    # reach the packaging state or when "package" is not in
    # BUILDHISTORY_FEATURES), so we write the file here
    # and let buildhistory_emit_pkghistory() overwrite it again
    # with more information later.
    infofile = os.path.join(pkghistdir, "latest")
    pe = d.getVar('PE', True) or "0"
    pv = d.getVar('PV', True)
    pr = d.getVar('PR', True)
    with codecs.open(infofile, "w", encoding='utf8') as f:
        if pe != "0":
            f.write(u"PE = %s\n" % pe)
        f.write(u"PV = %s\n" % pv)
        f.write(u"PR = %s\n" % pr)

    # List sources
    srcsfile = os.path.join(pkghistdir, "sources")
    with codecs.open(srcsfile, "w", encoding='utf8') as f:
        urls = (d.getVar('SRC_URI', True) or '').split()
        for url in urls:
            localpath = bb.fetch2.localpath(url, d)
            if os.path.isfile(localpath):
                sha256sum = bb.utils.sha256_file(localpath)
            else:
                sha256sum = 'N/A'
            if localpath.startswith(relpath):
                localpath = os.path.relpath(localpath, relpath)
            f.write('%s %s %s\n' % (url, localpath, sha256sum))

    # List metadata
    includes = d.getVar('BBINCLUDED', True).split()
    metafile = os.path.join(pkghistdir, "metadata")
    with codecs.open(metafile, "w", encoding='utf8') as f:
        for path in includes:
            if os.path.exists(path):
                sha256sum = bb.utils.sha256_file(path)
                if path.startswith(relpath):
                    path = os.path.relpath(path, relpath)
                f.write('%s %s\n' % (path, sha256sum))

    vars = (d.getVar('BUILDHISTORY_EXTRA_PKGVARS', True) or '').split()
    varsfile = os.path.join(pkghistdir, "variables")
    if vars:
        with codecs.open(varsfile, "w", encoding='utf8') as f:
            for var in vars:
                value = oe.utils.squashspaces(d.getVar(var, True) or '')
                if value:
                    f.write('%s = %s\n' % (var, value))
    elif os.path.exists(varsfile):
        os.unlink(varsfile)
}

python() {
    if bb.data.inherits_class('kernel', d):
        d.appendVarFlag('do_compile', 'prefuncs', ' buildhistory_extra_emit_kernelconfig')
        d.appendVarFlag('do_compile', 'vardepsexclude', ' buildhistory_extra_emit_kernelconfig')
}

python buildhistory_extra_emit_kernelconfig() {
    # Copy the final kernel config
    # Unlike the rest of buildhistory this will only get run when the kernel is actually built
    # (as opposed to being restored from the sstate cache); this is because do_shared_workdir
    # operates outside of sstate and that running is the only way you get the config other than
    # during the actual kernel build.
    import shutil
    pkghistdir = d.getVar('BUILDHISTORY_DIR_PACKAGE', True)
    if not os.path.exists(pkghistdir):
        bb.utils.mkdirhier(pkghistdir)
    shutil.copyfile(d.expand('${B}/.config'), os.path.join(pkghistdir, 'kconfig'))
}

buildhistory_get_image_installed_append() {
	# Create a file mapping installed packages to recipes
	printf "" > ${BUILDHISTORY_DIR_IMAGE}/installed-package-recipes.txt
	cat ${IMAGE_MANIFEST} | while read pkg pkgarch version
	do
		if [ -n "$pkg" ] ; then
			recipe=`oe-pkgdata-util -p ${PKGDATA_DIR} lookup-recipe $pkg`
			pkge=`oe-pkgdata-util -p ${PKGDATA_DIR} read-value PKGE $pkg`
			if [ "$pkge" != "" ] ; then
				pkge="$pkge-"
			fi
			pkgr=`oe-pkgdata-util -p ${PKGDATA_DIR} read-value PKGR $pkg`
			if [ "$pkgr" != "" ] ; then
				pkgr="-$pkgr"
			fi
			echo "$pkg $version $pkge$version$pkgr $recipe" >> ${BUILDHISTORY_DIR_IMAGE}/installed-package-recipes.txt
		fi
	done
}
