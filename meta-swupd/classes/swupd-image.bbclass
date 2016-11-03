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

# Created for each bundle (including os-core) and the "full" directory,
# describing files and directories that swupd-server needs to include in the update
# mechanism (i.e. without SWUPD_FILE_BLACKLIST entries). Used by swupd-server.
SWUPD_ROOTFS_MANIFEST_SUFFIX = ".content.txt"
# Additional entries which need to be in images (for example, /etc/machine-id, but
# that are excluded from the update mechanism. Ignored by swupd-server,
# used by swupdimage.bbclass.
SWUPD_IMAGE_MANIFEST_SUFFIX = ".extra-content.txt"

# Name of the base image. Always set, constant (unlike PN, which is
# different in the different virtual images).
SWUPD_IMAGE_PN = "${@ d.getVar('PN_BASE', True) or d.getVar('PN', True)}"

# Main directory in which swupd is invoked. The actual output which needs
# to be published will be in the "www" sub-directory.
DEPLOY_DIR_SWUPD = "${DEPLOY_DIR}/swupd/${MACHINE}/${SWUPD_IMAGE_PN}"

# The current format has to match the the source code of the
# swupd-client that is in the image. This recipe picks a suitable
# swupd-client via the client's RPROVIDES.
SWUPD_FORMAT ??= "3"
IMAGE_INSTALL_append = " swupd-client-format${SWUPD_FORMAT}"

# The information about where to find version information and actual
# content is needed in several places:
# - the swupd client in the image gets configured such that it uses that as default
# - swupd server needs information about the previous build
#
# The version URL determines what the client picks as the version that it updates to.
# The content URL must have all builds ever produced and is expected to also
# have the corresponding version information.
SWUPD_VERSION_URL ??= "http://download.example.com/updates/my-distro/milestone/${MACHINE}/${SWUPD_IMAGE_PN}"
SWUPD_CONTENT_URL ??= "http://download.example.com/updates/my-distro/builds/${MACHINE}/${SWUPD_IMAGE_PN}"

# An absolute path for a file containing the SSL certificate that is
# is to be used for verifying https connections to the version and content
# derver.
SWUPD_PINNED_PUBKEY ??= ""

# User configurable variables to disable all swupd processing or deltapack
# generation.
SWUPD_GENERATE ??= "1"
SWUPD_DELTAPACK_VERSIONS ??= ""

SWUPD_LOG_FN ??= "bbdebug 1"

# This version number *must* map to VERSION_ID in /etc/os-release and *must* be
# a non-negative integer that fits in an int.
OS_VERSION ??= "${DISTRO_VERSION}"

# We need to preserve xattrs which is only supported by GNU tar >= 1.27
# to be sure this functionality works as expected use the tar-replacement-native
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
    deploy_dir = d.getVar('DEPLOY_DIR_SWUPD', True)

    # Always set, value differs among virtual image recipes.
    pn = d.getVar('PN', True)
    # The PN value of the base image recipe. None in the base image recipe itself.
    pn_base = d.getVar('PN_BASE', True)
    # For bundle images, the corresponding bundle name. None in swupd images.
    bundle_name = d.getVar('BUNDLE_NAME', True)

    # We set the path to the rootfs folder of the mega image here so that
    # it's simple to refer to later.
    megarootfs = d.getVar('IMAGE_ROOTFS', True)
    if havebundles:
        megarootfs = megarootfs.replace('/' + pn +'/', '/bundle-%s-mega/' % (pn_base or pn))
        d.setVar('MEGA_IMAGE_ROOTFS', megarootfs)

    # do_stage_swupd_inputs in the main image recipe and do_image in the
    # swupd images will copy files from the mega bundle and thus those
    # recipes must use the same pseudo database.
    #
    # All other bundles can use their own pseudo instance, because the
    # main image recipe is only interested in file lists, not the actual
    # file attributes.
    #
    # Because real image building via SWUPD_IMAGES can happen also after
    # the initial "bitbake <core image>" invocation, we have to keep that
    # pseudo database around and cannot delete it.
    if pn_base is None or \
       bundle_name is None or \
       bundle_name == 'mega':
        pseudo_state = d.expand('${TMPDIR}/work-shared/%s/pseudo') % (pn_base or pn)
        d.setVar('PSEUDO_LOCALSTATEDIR', pseudo_state)

    if pn_base is not None:
        # Swupd images must depend on the mega image having been
        # built, as they will copy contents from there. For bundle
        # images that is irrelevant.
        if bundle_name is None:
            mega_name = (' bundle-%s-mega:do_image_complete' % pn_base)
            d.appendVarFlag('do_image', 'depends', mega_name)

        return

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

    # do_*swupd_* tasks need to re-run when ${DEPLOY_DIR_SWUPD}
    # got removed. We achieve that by creating the directory if needed
    # and adding a variable with the creation time stamp as value to
    # the do_stage_swupd_inputs vardeps. If that time stamp changes,
    # do_stage_swupd_inputs will be re-run.
    #
    # Uses a stamp file because this code runs several time during a build,
    # changing the value during a build causes hash mismatch errors, and the
    # directory ctime changes as content gets created in the directory.
    stampfile = os.path.join(deploy_dir, '.stamp')
    bb.utils.mkdirhier(deploy_dir)
    with open(stampfile, 'a+') as f:
        ctime = os.fstat(f.fileno()).st_ctime
    d.setVar('REDO_SWUPD', ctime)
    d.appendVarFlag('do_stage_swupd_inputs', 'vardeps', ' REDO_SWUPD')
    d.appendVarFlag('do_swupd_update', 'vardeps', ' REDO_SWUPD')
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

SWUPDIMAGEDIR = "${DEPLOY_DIR_SWUPD}/image"
SWUPDMANIFESTDIR = "${WORKDIR}/swupd-manifests"

fakeroot python do_stage_swupd_inputs () {
    import swupd.bundles

    if d.getVar('PN_BASE', True):
        bb.debug(2, 'Skipping update input staging for non-base image %s' % d.getVar('PN', True))
        return

    swupd.bundles.copy_core_contents(d)
    swupd.bundles.copy_bundle_contents(d)
    swupd.bundles.copy_old_versions(d)
}
addtask stage_swupd_inputs after do_image before do_swupd_update
do_stage_swupd_inputs[dirs] = "${SWUPDIMAGEDIR} ${SWUPDMANIFESTDIR} ${DEPLOY_DIR_SWUPD}/maps/"
do_stage_swupd_inputs[depends] += "virtual/fakeroot-native:do_populate_sysroot"

# do_swupd_update uses its own pseudo database, for several reasons:
# - Performance is better when the pseudo instance is not shared
#   with the do_image tasks of other virtual swupd image recipes (those
#   tend to run in parallel, because they also depend on
#   do_image_complete).
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

    # do_stage_swupd_inputs creates image/${OS_VERSION} for us, but
    # only if there has been some change in the input data that causes
    # the tasks to be rerun. In production that is unlikely, but it
    # happens when experimenting with swupd update creation. In that case
    # we can safely re-use the most recent version.
    if ! [ -e ${DEPLOY_DIR_SWUPD}/image/${OS_VERSION} ]; then
        latest=$(find image/ -maxdepth 1 -name '[0123456789]*' -type d | sort -n | tail -1)
        if [ "$latest" ]; then
           ln -s $latest ${DEPLOY_DIR_SWUPD}/image/${OS_VERSION}
        else
           bbfatal '${DEPLOY_DIR_SWUPD}/image/${OS_VERSION} does not exist and no previous version was found either.'
           exit 1
        fi
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
        # TODO: locate information about latest version from online www update repo
        # and download the relevant files. That makes swupd_create_fullfiles
        # a lot faster because it allows reusing existing, unmodified files.
        # Saves a lot of space, too, because the new Manifest files then merely
        # point to the older version (no entry in ${DEPLOY_DIR_SWUPD}/www/${OS_VERSION}/files,
        # not even a link).
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
            # TODO: use bsdtar and auto-detect compression
            bbnote Unpacking $archive
            env $PSEUDO tar --xattrs --xattrs-include='*' -zxf $archive -C $dir
        fi
    done

    invoke_swupd () {
        echo $PSEUDO "$@"
        time env $PSEUDO "$@"
    }

    ${SWUPD_LOG_FN} "Generating update from $PREVREL to ${OS_VERSION}"
    # env $PSEUDO bsdtar -acf ${DEPLOY_DIR}/swupd-before-create-update.tar.gz -C ${DEPLOY_DIR} swupd
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

    # Generate delta-packs against previous versions chosen by our caller.
    # env $PSEUDO bsdtar -acf ${DEPLOY_DIR}/swupd-before-make-delta-pack.tar.gz -C ${DEPLOY_DIR} swupd
    for prevver in ${SWUPD_DELTAPACK_VERSIONS}; do
        for bndl in ${ALL_BUNDLES}; do
            bndlcnt=0
            ${SWUPD_LOG_FN} "Generating delta pack from $prevver to ${OS_VERSION} for $bndl"
            invoke_swupd ${STAGING_BINDIR_NATIVE}/swupd_make_pack --log-stdout -S ${DEPLOY_DIR_SWUPD} $prevver ${OS_VERSION} $bndl
        done
    done

    # Write version to www/version/format${SWUPD_FORMAT}/latest and image/latest.version
    bbdebug 2 "Writing latest file"
    mkdir -p ${DEPLOY_DIR_SWUPD}/www/version/format${SWUPD_FORMAT}
    echo ${OS_VERSION} > ${DEPLOY_DIR_SWUPD}/www/version/format${SWUPD_FORMAT}/latest
    echo ${OS_VERSION} > ${DEPLOY_DIR_SWUPD}/image/latest.version
    # env $PSEUDO bsdtar -acf ${DEPLOY_DIR}/swupd-done.tar.gz -C ${DEPLOY_DIR} swupd

    # Archive the files of the current build which will be needed in the future
    # for a <current version> -> <future version> delta computation. We exclude
    # the expanded "full" rootfs, because we already have "full.tar".
    (cd ${DEPLOY_DIR_SWUPD}; tar -zcf ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${OS_VERSION}-swupd.tar --exclude=full --exclude=Manifest.*.tar image/${OS_VERSION} www/${OS_VERSION}/Manifest.*)
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
IMAGE_INSTALL_append = " os-release"
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

def hash_swupd_pinned_pubkey(d):
    pubkey = d.getVar('SWUPD_PINNED_PUBKEY', True)
    if pubkey:
        import hashlib
        bb.parse.mark_dependency(d, pubkey)
        with open(pubkey, 'rb') as f:
            hash = hashlib.sha256()
            hash.update(f.read())
            return hash.hexdigest()
    else:
        return ''

SWUPD_PINNED_PUBKEY_HASH := "${@ hash_swupd_pinned_pubkey(d)}"

# The swupd client must be configured on a per-image basis.
# Different images might need different settings.
configure_swupd_client () {
    # Write default values to the configuration hierarchy (since 3.4.0)
    install -d ${IMAGE_ROOTFS}/usr/share/defaults/swupd
    echo "${SWUPD_VERSION_URL}" >> ${IMAGE_ROOTFS}/usr/share/defaults/swupd/versionurl
    echo "${SWUPD_CONTENT_URL}" >> ${IMAGE_ROOTFS}/usr/share/defaults/swupd/contenturl
    echo "${SWUPD_FORMAT}" >> ${IMAGE_ROOTFS}/usr/share/defaults/swupd/format
    # Changing content of the pubkey also changes the hash and thus ensures
    # that this method and thus do_rootfs run again.
    #
    # TODO: does not actually work. Recipe gets reparsed when the file
    # changes ("bitbake -e ostro-image-swupd | SWUPD_PINNED_PUBKEY_HASH" changes)
    # but the task  does not get re-executed. Forcing that leads to:
    #
    # ERROR: ostro-image-swupd-1.0-r0 do_rootfs: Taskhash mismatch 8762bf20b997ac29dd6793fd11e609c3 versus cb40afac8ca291e31022d5ffd9a9bbac for /work/ostro-os/meta-ostro/recipes-image/images/ostro-image-swupd.bb.do_rootfs
    # ERROR: Taskhash mismatch 8762bf20b997ac29dd6793fd11e609c3 versus cb40afac8ca291e31022d5ffd9a9bbac for /work/ostro-os/meta-ostro/recipes-image/images/ostro-image-swupd.bb.do_rootfs
    #
    # $ bitbake-diffsigs tmp-glibc/stamps/qemux86-ostro-linux/ostro-image-swupd/1.0-r0.do_rootfs.sigdata.c8a9371831f58ce4f8b49a73211f66aa tmp-glibc/stamps/qemux86-ostro-linux/ostro-image-swupd/1.0-r0.do_rootfs.sigdata.cb40afac8ca291e31022d5ffd9a9bbac 
    # basehash changed from 02de100ee7baa348e224f21844fdaa06 to e3bb23a069673a09afee4994522991d3
    # Variable SWUPD_PINNED_PUBKEY_HASH value changed from 'b9ffbe0963f3f7ab3f3c1af5cd8471c121cb601eb4294ad4b211f1e206746a0a' to '8d172423eb0162feb8c7fb2f2d7da28a6effdf3e95184114c62e6b0efdeae89a'
    # Taint (by forced/invalidated task) changed from None to 2c8e3b43-5e70-4c96-bf6e-741f0b344731
    #
    # There's no sigdata for 8762b. c8a93 is from before changing the file.
    if [ "${SWUPD_PINNED_PUBKEY_HASH}" ]; then
        install -d ${IMAGE_ROOTFS}${datadir}/clear/update-ca
        install -m 0644 '${SWUPD_PINNED_PUBKEY}' ${IMAGE_ROOTFS}${datadir}/clear/update-ca/
        echo "${datadir}/clear/update-ca/$(basename '${SWUPD_PINNED_PUBKEY}')" > ${IMAGE_ROOTFS}/usr/share/defaults/swupd/pinnedpubkey
    fi
    chown -R root:root ${IMAGE_ROOTFS}/usr/share/defaults/swupd
    chmod 0644 ${IMAGE_ROOTFS}/usr/share/defaults/swupd/*
}
ROOTFS_POSTPROCESS_COMMAND_append = " configure_swupd_client;"
