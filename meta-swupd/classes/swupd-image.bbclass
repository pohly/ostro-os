# Class for swupd integration -- generates input artefacts for consumption by
# swupd-server and calls swupd-server to process the inputs into update
# artefacts for consumption by swupd-client.
#
# Usage:
# * inherit this class in your core OS image. swupd-based OS's use bundles, the
#   primary one of which, os-core, is defined as the contents of this image.
# * Assign a list of names for bundles you wish to generate to the
#   SWUPD_BUNDLES variable i.e. SWUPD_BUNDLES = "feature_one feature_two"
# * Assign a list of packages for which their content should be included in
#   a bundle to a varflag of BUNDLE_CONTENTS which matches the bundle name
#   i.e. BUNDLE_CONTENTS[feature_one] = "package_one package_three package_six"
# * Ensure the OS_VERSION variable is assigned an integer value and increased
#   before each image build which should generate swupd update artefacts.
#
# See docs/Guide.md for more information.

DEPLOY_DIR_SWUPDBASE = "${DEPLOY_DIR}/swupd/${MACHINE}"
# Created for each bundle (including os-core) and the "full" directory,
# describing files and directories that swupd-server needs to include in the update
# mechanism (i.e. without SWUPD_FILE_BLACKLIST entries). Used by swupd-server.
SWUPD_ROOTFS_MANIFEST_SUFFIX = ".content.txt"
# Additional entries which need to be in images (for example, /etc/machine-id, but
# that are excluded from the update mechanism. Ignored by swupd-server,
# used by swupdimage.bbclass.
SWUPD_IMAGE_MANIFEST_SUFFIX = ".extra-content.txt"

# User configurable variables to disable all swupd processing or deltapack
# generation.
SWUPD_GENERATE ??= "1"
SWUPD_DELTAPACKS ??= "1"
# Create delta packs for N versions back — default 2
SWUPD_N_DELTAPACK ??= "2"

SWUPD_LOG_FN ??= "bbdebug 1"

# This version number *must* map to VERSION_ID in /etc/os-release and *must* be
# a non-negative integer that fits in an int.
OS_VERSION ??= "${DISTRO_VERSION}"

IMAGE_INSTALL_append = " swupd-client os-release"

# We need to preserve xattrs, which works with bsdtar out of the box.
# It also has saner file handling (less syscalls per file) than GNU tar.
# Last but not least, GNU tar 1.27.1 had weird problems extracting
# all requested entries with -T from an archive ("Not found in archive"
# errors for entries which were present and could be extraced or listed
# when using simpler file lists).
DEPENDS += "libarchive-native"

# The same is only supported by GNU tar >= 1.27, which is needed for
# extracting sstate. So to be sure this functionality works as
# expected use the tar-replacement-native.
DEPENDS += "tar-replacement-native"
EXTRANATIVEPATH += "tar-native"

inherit distro_features_check
REQUIRED_DISTRO_FEATURES = "systemd"

python () {
    ver = d.getVar('OS_VERSION', True) or 'invalid'
    try:
        int(ver)
    except ValueError:
        bb.fatal("Invalid value for OS_VERSION (%s), must be a non-negative integer value." % ver)

    havebundles = (d.getVar('SWUPD_BUNDLES', True) or '') != ''

    # Always set, value differs among virtual image recipes.
    pn = d.getVar('PN', True)
    # The PN value of the base image recipe. None in the base image recipe itself.
    pn_base = d.getVar('PN_BASE', True)
    # For bundle images, the corresponding bundle name. None in swupd images.
    bundle_name = d.getVar('BUNDLE_NAME', True)

    # bundle-<image>-mega archives its rootfs as ${IMAGE_ROOTFS}.tar.
    # Every other recipe then can copy (do_stage_swupd_inputs) or
    # extract relevant files (do_image/create_rootfs()) without sharing
    # the same pseudo database. Not sharing pseudo instances is faster
    # and the expensive reading of individual files via pseudo only
    # needs to be done once.
    if havebundles:
        mega_rootfs = d.getVar('IMAGE_ROOTFS', True)
        mega_rootfs = mega_rootfs.replace('/' + pn +'/', '/bundle-%s-mega/' % (pn_base or pn))
        d.setVar('MEGA_IMAGE_ROOTFS', mega_rootfs)
        d.setVar('MEGA_IMAGE_ARCHIVE', mega_rootfs + '.tar')

    # We need to use a custom manifest filename for stage_swupd_inputs so that
    # the generated sstate can be used to fetch inputs for multiple "releases"
    manfileprefix = d.getVar('SSTATE_MANFILEPREFIX', True)
    manfileprefix = manfileprefix + '-' + ver
    d.setVar('SSTATE_MANFILEPREFIX', manfileprefix)

    if pn_base is not None:
        # We want all virtual images from this recipe to deploy to the same
        # directory
        deploy_dir = d.getVar('DEPLOY_DIR_SWUPDBASE', True)
        deploy_dir = os.path.join(deploy_dir, pn_base)
        d.setVar('DEPLOY_DIR_SWUPD', deploy_dir)

        # Swupd images must depend on the mega image having been
        # built, as they will copy contents from there. For bundle
        # images that is irrelevant.
        if bundle_name is None:
            mega_name = (' bundle-%s-mega:do_image_complete' % pn_base)
            d.appendVarFlag('do_image', 'depends', mega_name)

        return

    deploy_dir = d.expand('${DEPLOY_DIR_SWUPDBASE}/${IMAGE_BASENAME}')
    d.setVar('DEPLOY_DIR_SWUPD', deploy_dir)
    # do_swupd_update requires the full swupd directory hierarchy
    varflags = '%s/image %s/empty %s/www %s' % (deploy_dir, deploy_dir, deploy_dir, deploy_dir)
    d.setVarFlag('do_swupd_update', 'dirs', varflags)

    # For the base image only, set the BUNDLE_NAME to os-core and generate the
    # virtual image for the mega image
    d.setVar('BUNDLE_NAME', 'os-core')

    bundles = (d.getVar('SWUPD_BUNDLES', True) or "").split()
    extended = (d.getVar('BBCLASSEXTEND', True) or "").split()

    # We need to prevent the user defining bundles where the name might clash
    # with naming in meta-swupd and swupd itself:
    #  * mega is the name of our super image, an implementation detail in
    #     meta-swupd
    #  * full is the name used by swupd for the super manifest (listing all
    #     files in all bundles of the OS)
    def check_reserved_name(name):
        reserved_bundles = ['mega', 'full']
        if name in reserved_bundles:
            bb.error('SWUPD_BUNDLES contains an item named "%s", this is a reserved name. Please rename that bundle.' % name)

    for bndl in bundles:
        check_reserved_name(bndl)

    # Generate virtual images for all bundles.
    for bndl in bundles:
        extended.append('swupdbundle:%s' % bndl)
        dep = ' bundle-%s-%s:do_image_complete' % (pn, bndl)
        # do_stage_swupd_inputs will try and utilise artefacts of the bundle
        # image build, so must depend on it having completed
        d.appendVarFlag('do_stage_swupd_inputs', 'depends', dep)

    if havebundles:
        extended.append('swupdbundle:mega')

    # Generate real image files from the os-core bundle plus
    # certain additional bundles. All of these images can share
    # the same swupd update stream, the only difference is the
    # number of pre-installed bundles.
    for imageext in (d.getVar('SWUPD_IMAGES', True) or '').split():
        extended.append('swupdimage:%s' % imageext)

    d.setVar('BBCLASSEXTEND', ' '.join(extended))

    # The base image should depend on the mega-image having been populated
    # to ensure that we're staging the same shared files from the sysroot as
    # the bundle images.
    if havebundles:
        mega_name = (' bundle-%s-mega:do_image_complete' % pn)
        d.appendVarFlag('do_image', 'depends', mega_name)
        d.appendVarFlag('do_stage_swupd_inputs', 'depends', mega_name)
}

# swupd-client expects a bundle subscription to exist for each
# installed bundle. This is simply an empty file named for the
# bundle in /usr/share/clear/bundles
def create_bundle_manifest(d, bundlename, dest=None):
    tgtpath = '/usr/share/clear/bundles'
    if dest:
        bundledir = dest + tgtpath
    else:
        bundledir = d.expand('${IMAGE_ROOTFS}%s' % tgtpath)
    bb.utils.mkdirhier(bundledir)
    open(os.path.join(bundledir, bundlename), 'w+b').close()

fakeroot do_rootfs_append () {
    import swupd.bundles

    bundle = d.getVar('BUNDLE_NAME', True)
    bundles = ['os-core']
    if bundle == 'mega':
        bundles.extend((d.getVar('SWUPD_BUNDLES', True) or '').split())
    else:
        bundles.append(bundle)
    # swupd-client expects a bundle subscription to exist for each
    # installed bundle. This is simply an empty file named for the
    # bundle in /usr/share/clear/bundles
    for bundle in bundles:
        swupd.bundles.create_bundle_manifest(d, bundle)
}
do_rootfs[depends] += "virtual/fakeroot-native:do_populate_sysroot"

do_image_append () {
    import swupd.rootfs

    swupd.rootfs.create_rootfs(d)
}

# Some files should not be included in swupd manifests and therefore never be
# updated on the target (i.e. certain per-device or machine-generated files in
# /etc when building for a statefule OS). Add the target paths to this list to
# prevent the specified files being copied to the swupd staging directory.
# i.e.
# SWUPD_FILE_BLACKLIST = "\
#     /etc/mtab \
#     /etc/machine-id \
#"
SWUPD_FILE_BLACKLIST ??= ""

# When set to a non-empty string, the "swupd/image" content for the
# current build gets archived in the sstate-cache. This is
# experimental and disabled by default. Using it to create deltas
# between builds also implies doing some extra work to preserve the
# SWUPD_SSTATE_MAP map file across builds.
SWUPD_SSTATE ??= ""

SWUPDIMAGEDIR = "${@ '${WORKDIR}/swupd-image' if '${SWUPD_SSTATE}' else '${DEPLOY_DIR_SWUPD}/image'}"
SWUPDMANIFESTDIR = "${WORKDIR}/swupd-manifests"
SWUPD_SSTATE_MAP = "${DEPLOY_DIR_SWUPD}/${PN}-map.inc"
fakeroot python do_stage_swupd_inputs () {
    import swupd.bundles

    if d.getVar('PN_BASE', True):
        bb.debug(2, 'Skipping update input staging for non-base image %s' % d.getVar('PN', True))
        return

    swupd.bundles.copy_core_contents(d)
    swupd.bundles.copy_bundle_contents(d)

    # Write information about all known OSV->sstate obj mappings
    mapfile = d.getVar('SWUPD_SSTATE_MAP', True)
    pn = d.getVar('PN', True)
    sstatepkg = d.getVar('SSTATE_PKGNAME', True) + '_stage_swupd_inputs.tgz'
    osv = d.getVar('OS_VERSION', True)
    verdict = {}
    versions = (d.getVar('OS_VERSION_SSTATE_MAP_%s' % pn, True) or '').split()
    for version in versions:
        ver, pkg = version.split('=')
        verdict[ver] = pkg
    verdict[osv] = sstatepkg

    with open(mapfile, 'w') as f:
        f.write('OS_VERSION_SSTATE_MAP_%s = "\\\n' % pn)
        for ver, pkg in verdict.items():
            f.write('    %s=%s \\\n' % (ver, pkg))
        f.write('    "\n')

    bb.debug(3, 'Writing mapfile to %s' % mapfile)
}
addtask stage_swupd_inputs after do_image before do_swupd_update
do_stage_swupd_inputs[dirs] = "${SWUPDIMAGEDIR} ${SWUPDMANIFESTDIR} ${DEPLOY_DIR_SWUPD}/maps/"
do_stage_swupd_inputs[depends] += "virtual/fakeroot-native:do_populate_sysroot"

SSTATETASKS += "${@ 'do_stage_swupd_inputs' if '${SWUPD_SSTATE}' else ''}"
do_stage_swupd_inputs[sstate-inputdirs] = "${SWUPDIMAGEDIR}/${OS_VERSION} ${SWUPDMANIFESTDIR}"
do_stage_swupd_inputs[sstate-outputdirs] = "${DEPLOY_DIR_SWUPD}/image/${OS_VERSION} ${DEPLOY_DIR_IMAGE}"

python swupd_fix_manifest_link() {
    """
    Ensure the manifest symlink points to the latest version of the manifest,
    not the most recently staged.
    """
    import glob

    sourcedir = d.getVar('SWUPDMANIFESTDIR', True)
    destdir = d.getVar('DEPLOY_DIR_IMAGE', True)
    links = []
    # Find symlinks in SWUPDMANIFESTDIR
    for f in os.listdir(sourcedir):
        if os.path.islink(os.path.join(sourcedir, f)):
            links.append(f)

    for link in links:
        target = None
        latest = None
        # Extract a pattern for glob:
        #   core-image-minimal-qemux86.manifest ->
        #       core-image-minimal-qemux86-20160602082427.rootfs.manifest
        components = link.split('.')
        prefix = components[0]
        suffix = components[1]
        pattern = prefix + '-*.' + suffix
        # Find files matching the pattern in DEPLOY_DIR_IMAGE
        for f in glob.glob(destdir+'/'+pattern):
            # Find the most recent file matching that pattern
            fname = os.path.basename(f)
            date = f.split('-')[-1].split('.')[0]
            if not latest or latest < date:
                target = f
        # Update the symlink
        lnk = os.path.join(destdir, link)
        os.remove(lnk)
        bb.debug(3, 'Updating link %s to %s' % (lnk, target))
        os.symlink(target, lnk)
}

python do_stage_swupd_inputs_setscene () {
    if d.getVar('PN_BASE', True):
        bb.debug(2, 'Skipping update input staging from sstate for non-base image %s' % d.getVar('PN', True))
        return

    sstate_setscene(d)
}
addtask do_stage_swupd_inputs_setscene
do_stage_swupd_inputs_setscene[dirs] = "${SWUPDIMAGEDIR} ${DEPLOY_DIR_SWUPD}/image/ ${SWUPDMANIFESTDIR} ${DEPLOY_DIR_IMAGE}"
do_stage_swupd_inputs_setscene[postfuncs] += "swupd_fix_manifest_link "

fakeroot python do_fetch_swupd_inputs () {
    import subprocess
    import swupd.path

    if d.getVar('PN_BASE', True):
        bb.debug(2, 'Skipping update input fetching for non-base image %s' % d.getVar('PN', True))
        return

    fetchlist = {}
    pn = d.getVar('PN', True)
    currv = d.getVar('OS_VERSION', True)
    maplist = (d.getVar('OS_VERSION_SSTATE_MAP_%s' % pn, True) or '').split()
    for map in maplist:
        osv, pkg = map.split('=')
        if osv == currv:
            continue
        fetchlist[osv] = pkg

    workdir = d.expand('${WORKDIR}/fetched-inputs')
    bb.utils.mkdirhier(workdir)

    deploydirswupd = d.getVar('DEPLOY_DIR_SWUPD', True)
    deploydirimage = d.getVar('DEPLOY_DIR_IMAGE', True)
    sstatedir = d.getVar('SSTATE_DIR', True)
    # For each identified input sstate object, try and ensure we have the
    # object file available
    for osv, pkg in fetchlist.items():
        # Don't try and fetch & unpack the sstate for a version directory
        # which already exists
        imgdst = os.path.join(deploydirswupd, 'image', osv)
        if os.path.exists(imgdst):
            continue

        sstatefetch = pkg
        sstatepkg = '%s/%s' % (sstatedir, pkg)

        bb.debug(1, 'Preparing sstate package %s' % sstatepkg)

        if not os.path.exists(sstatepkg):
            bb.debug(2, 'Fetching object %s from mirror' % sstatepkg)
            pstaging_fetch(sstatefetch, sstatepkg, d)

        if not os.path.isfile(sstatepkg):
            bb.debug(2, "Shared state package %s is not available" % sstatepkg)
            continue

        # We now have a copy of the sstate  for a do_stage_swupd_inputs
        # version let's "install" it. We have two directories:
        # $osv: should be extracted to ${DEPLOY_DIR_SWUPD}/image/$osv
        # swupd-manifests: should be extracted to ${DEPLOY_DIR_IMAGE}
        src = os.path.join(workdir, osv)
        bb.utils.mkdirhier(src)

        bb.debug(2, 'Unpacking sstate object %s in %s' % (sstatepkg, src))
        cmd = 'cd %s && tar -xvzf %s' % (src, sstatepkg)
        subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
        bb.utils.mkdirhier(imgdst)
        swupd.path.copyxattrtree('%s/%s/' % (src, osv), imgdst)
        swupd.path.copyxattrtree('%s/swupd-manifests/' % src, deploydirimage)
}
addtask fetch_swupd_inputs before do_swupd_update
do_fetch_swupd_inputs[dirs] = "${DEPLOY_DIR_SWUPD}/maps ${DEPLOY_DIR_SWUPD}/image"
do_fetch_swupd_inputs[depends] += "virtual/fakeroot-native:do_populate_sysroot"

SWUPD_FORMAT ??= "3"
# do_swupd_update uses its own pseudo database, for several reasons:
# - Performance is better when the pseudo instance is not shared
#   with other tasks that run in parallel (for example, meta-isafw's do_analyse_image).
# - Wiping out the deploy/swupd directory and re-executing do_stage_swupd_inputs/do_swupd_update
#   really starts from a clean slate.
# - The log.do_swupd_update will show commands that can be invoked directly, without
#   having to enter a devshell (slightly more convenient).
do_swupd_update () {
    if [ -z "${BUNDLE_NAME}" ] || [ ! -z "${PN_BASE}" ] ; then
        bbdebug 1 'We only generate swupd updates for the base image, skipping ${PN}:do_swupd_update'
        exit
    fi

    if [ ! "${SWUPD_GENERATE}" -eq 1 ]; then
        bbnote 'Update generation disabled, skipping.'
        exit
    fi

    export SWUPD_CERTS_DIR="${STAGING_ETCDIR_NATIVE}/swupd-certs"
    export LEAF_KEY="leaf.key.pem"
    export LEAF_CERT="leaf.cert.pem"
    export CA_CHAIN_CERT="ca-chain.cert.pem"
    export PASSPHRASE="${SWUPD_CERTS_DIR}/passphrase"

    export XZ_DEFAULTS="--threads 0"

    ${SWUPD_LOG_FN} "New OS_VERSION is ${OS_VERSION}"
    # If the swupd directory already exists don't trample over it, but let
    # the user know we're not doing any update generation.
    if [ -e ${DEPLOY_DIR_SWUPD}/www/${OS_VERSION} ]; then
        bbwarn 'swupd image directory exists for OS_VERSION=${OS_VERSION}, not generating updates.'
        bbwarn 'Ensure OS_VERSION is incremented if you want to generate updates.'
        exit
    fi

    # Generate swupd-server configuration
    bbdebug 2 "Writing ${DEPLOY_DIR_SWUPD}/server.ini"
    if [ -e "${DEPLOY_DIR_SWUPD}/server.ini" ]; then
       rm ${DEPLOY_DIR_SWUPD}/server.ini
    fi
    cat << END > ${DEPLOY_DIR_SWUPD}/server.ini
[Server]
imagebase=${DEPLOY_DIR_SWUPD}/image/
outputdir=${DEPLOY_DIR_SWUPD}/www/
emptydir=${DEPLOY_DIR_SWUPD}/empty/
END

    if [ -e ${DEPLOY_DIR_SWUPD}/image/latest.version ]; then
        PREVREL=`cat ${DEPLOY_DIR_SWUPD}/image/latest.version`
    else
        bbdebug 2 "Stubbing out empty latest.version file"
        touch ${DEPLOY_DIR_SWUPD}/image/latest.version
        PREVREL="0"
    fi

    GROUPS_INI="${DEPLOY_DIR_SWUPD}/groups.ini"
    bbdebug 2 "Writing ${GROUPS_INI}"
    if [ -e "${DEPLOY_DIR_SWUPD}/groups.ini" ]; then
       rm ${DEPLOY_DIR_SWUPD}/groups.ini
    fi
    touch ${GROUPS_INI}
    ALL_BUNDLES="os-core ${SWUPD_BUNDLES} ${SWUPD_EMPTY_BUNDLES}"
    for bndl in ${ALL_BUNDLES}; do
        echo "[$bndl]" >> ${GROUPS_INI}
        echo "group=$bndl" >> ${GROUPS_INI}
        echo "" >> ${GROUPS_INI}
    done

    # Activate pseudo for all following commands explicitly.
    PSEUDO="${FAKEROOTENV} PSEUDO_LOCALSTATEDIR=${DEPLOY_DIR_SWUPD}/pseudo ${FAKEROOTCMD}"

    # Unpack the input rootfs dir(s) for use with the swupd tools. Might have happened
    # already in a previous run of this task.
    for archive in ${DEPLOY_DIR_SWUPD}/image/*/*.tar; do
        dir=$(echo $archive | sed -e 's/.tar$//')
        if [ -e $archive ] && ! [ -d $dir ]; then
            mkdir -p $dir
            bbnote Unpacking $archive
            env $PSEUDO bsdtar -xf $archive -C $dir
        fi
    done

    invoke_swupd () {
        echo $PSEUDO "$@"
        time env $PSEUDO "$@"
    }

    ${SWUPD_LOG_FN} "Generating update from $PREVREL to ${OS_VERSION}"
    env $PSEUDO bsdtar -acf ${DEPLOY_DIR}/swupd-before-create-update.tar.gz -C ${DEPLOY_DIR} swupd
    return 0
    invoke_swupd ${STAGING_BINDIR_NATIVE}/swupd_create_update --log-stdout -S ${DEPLOY_DIR_SWUPD} --osversion ${OS_VERSION} --format ${SWUPD_FORMAT}

    ${SWUPD_LOG_FN} "Generating fullfiles for ${OS_VERSION}"
    # env $PSEUDO bsdtar -acf ${DEPLOY_DIR}/swupd-before-make-fullfiles.tar.gz -C ${DEPLOY_DIR} swupd
    invoke_swupd ${STAGING_BINDIR_NATIVE}/swupd_make_fullfiles --log-stdout -S ${DEPLOY_DIR_SWUPD} ${OS_VERSION}

    ${SWUPD_LOG_FN} "Generating zero packs, this can take some time."
    # env $PSEUDO bsdtar -acf ${DEPLOY_DIR}/swupd-before-make-zero-pack.tar.gz -C ${DEPLOY_DIR} swupd
    for bndl in ${ALL_BUNDLES}; do
        ${SWUPD_LOG_FN} "Generating zero pack for $bndl"
        invoke_swupd ${STAGING_BINDIR_NATIVE}/swupd_make_pack --log-stdout -S ${DEPLOY_DIR_SWUPD} 0 ${OS_VERSION} $bndl
    done

    # Generate delta-packs going back SWUPD_N_DELTAPACK versions
    # env $PSEUDO bsdtar -acf ${DEPLOY_DIR}/swupd-before-make-delta-pack.tar.gz -C ${DEPLOY_DIR} swupd
    if [ ${SWUPD_DELTAPACKS} -eq 1 -a ${SWUPD_N_DELTAPACK} -gt 0 -a $PREVREL -gt 0 ]; then
        for bndl in ${ALL_BUNDLES}; do
            bndlcnt=0
            # Build list of previous versions and pick the last n ones to build
            # deltas against. Ignore the latest one, which is the one we build
            # right now.
            ls -d -1 ${DEPLOY_DIR_SWUPD}/image/*/$bndl | sed -e 's;${DEPLOY_DIR_SWUPD}/image/\([^/]*\)/.*;\1;' | grep -e '^[0-9]*$' | sort -n | head -n -1 | tail -n ${SWUPD_N_DELTAPACK} | while read prevver; do
                ${SWUPD_LOG_FN} "Generating delta pack from $prevver to ${OS_VERSION} for $bndl"
                invoke_swupd ${STAGING_BINDIR_NATIVE}/swupd_make_pack --log-stdout -S ${DEPLOY_DIR_SWUPD} $prevver ${OS_VERSION} $bndl
            done
        done
    fi

    # Write version to www/version/format${SWUPD_FORMAT}/latest and image/latest.version
    bbdebug 2 "Writing latest file"
    mkdir -p ${DEPLOY_DIR_SWUPD}/www/version/format${SWUPD_FORMAT}
    echo ${OS_VERSION} > ${DEPLOY_DIR_SWUPD}/www/version/format${SWUPD_FORMAT}/latest
    echo ${OS_VERSION} > ${DEPLOY_DIR_SWUPD}/image/latest.version
    # bsdtar -acf ${DEPLOY_DIR}/swupd-done.tar.gz -C ${DEPLOY_DIR} swupd
}

SWUPDDEPENDS = "\
    virtual/fakeroot-native:do_populate_sysroot \
    rsync-native:do_populate_sysroot \
    bsdiff-native:do_populate_sysroot \
    swupd-server-native:do_populate_sysroot \
"
addtask swupd_update after do_image_complete before do_build
do_swupd_update[depends] = "${SWUPDDEPENDS}"

# pseudo does not handle xattrs correctly for hardlinks:
# https://bugzilla.yoctoproject.org/show_bug.cgi?id=9317
#
# This started to become a problem when copying rootfs
# content around for swupd bundle creation. As a workaround,
# we avoid having hardlinks in the rootfs and replace them
# with symlinks.
python swupd_replace_hardlinks () {
    import os
    import stat

    # Collect all inodes and which entries share them.
    inodes = {}
    for root, dirs, files in os.walk(d.getVar('IMAGE_ROOTFS', True)):
        for file in files:
            path = os.path.join(root, file)
            s = os.lstat(path)
            if stat.S_ISREG(s.st_mode):
                inodes.setdefault(s.st_ino, []).append(path)

    for inode, paths in inodes.items():
        if len(paths) > 1:
            paths.sort()
            bb.debug(3, 'Removing hardlinks: %s' % ' = '.join(paths))
            # Arbitrarily pick the first entry as symlink target.
            target = paths.pop(0)
            for path in paths:
                reltarget = os.path.relpath(target, os.path.dirname(path))
                os.unlink(path)
                os.symlink(reltarget, path)
}
ROOTFS_POSTPROCESS_COMMAND += "swupd_replace_hardlinks; "

# swupd-client checks VERSION_ID, which must match the OS_VERSION
# used for generating swupd bundles in the current build.
#
# We patch this during image creation and exclude OS_VERSION from the
# dependencies because doing it during the compilation of os-release.bb
# would trigger a rebuild even if all that changed is the OS_VERSION.
# It would also affect builds of images where swupd is not active. Both
# is undesirable.
#
# If triggering a rebuild on each OS_VERSION change is desired,
# then this can be achieved by influencing the os-release package
# by setting in local.conf:
# VERSION_ID = "${OS_VERSION}"

swupd_patch_os_release () {
    sed -i -e 's/^VERSION_ID *=.*/VERSION_ID="${OS_VERSION}"/' ${IMAGE_ROOTFS}/usr/lib/os-release
}
swupd_patch_os_release[vardepsexclude] = "OS_VERSION"
ROOTFS_POSTPROCESS_COMMAND += "swupd_patch_os_release; "

# Check whether the constructed image contains any dangling symlinks, these
# are likely to indicate deeper issues.
# NOTE: you'll almost certainly want to override these for your distro.
# /run, /var/volatile and /dev only get mounted at runtime.
# Enable this check by adding it to IMAGE_QA_COMMANDS
# IMAGE_QA_COMMANDS += " \
#     swupd_check_dangling_symlinks \
# "
SWUPD_IMAGE_SYMLINK_WHITELIST ??= " \
    /run/lock \
    /var/volatile/tmp \
    /var/volatile/log \
    /dev/null \
    /proc/mounts \
    /run/resolv.conf \
"

python swupd_check_dangling_symlinks() {
    from oe.utils import ImageQAFailed

    rootfs = d.getVar("IMAGE_ROOTFS", True)

    def resolve_links(target, root):
        if not target.startswith('/'):
            target = os.path.normpath(os.path.join(root, target))
        else:
            # Absolute links are in fact relative to the rootfs.
            # Can't use os.path.join() here, it skips the
            # components before absolute paths.
            target = os.path.normpath(rootfs + target)
        if os.path.islink(target):
            root = os.path.dirname(target)
            target = os.readlink(target)
            target = resolve_links(target, root)
        return target

    # Check for dangling symlinks. One common reason for them
    # in swupd images is update-alternatives where the alternative
    # that gets chosen in the mega image then is not installed
    # in a sub-image.
    #
    # Some allowed cases are whitelisted.
    whitelist = d.getVar('SWUPD_IMAGE_SYMLINK_WHITELIST', True).split()
    message = ''
    for root, dirs, files in os.walk(rootfs):
        for entry in files + dirs:
            path = os.path.join(root, entry)
            if os.path.islink(path):
                target = os.readlink(path)
                final_target = resolve_links(target, root)
                if not os.path.exists(final_target) and not final_target[len(rootfs):] in whitelist:
                    message = message + 'Dangling symlink: %s -> %s -> %s does not resolve to a valid filesystem entry.\n' % (path, target, final_target)

    if message != '':
        message = message + '\nIf these symlinks not pointing to a valid destination is not an issue \
i.e. the link is to a file which only exists at runtime, such as files in /proc, add them to \
SWUPD_IMAGE_SYMLINK_WHITELIST to resolve this error.'
        raise ImageQAFailed(message, swupd_check_dangling_symlinks)
}
