import os
import bb
import oe.path
from swupd.utils import manifest_to_file_list
from swupd.path import copyxattrfiles


def create_rootfs(d):
    """
    create/replace rootfs with equivalent files from mega image rootfs

    Create or replace the do_image rootfs output with the corresponding
    subset from the mega rootfs. Done even if there is no actual image
    getting produced, because there may be QA tests defined for
    do_image which depend on seeing the actual rootfs that would be
    used for images.

    d -- the bitbake data store
    """
    bndl = d.getVar('BUNDLE_NAME', True)
    pn = d.getVar('PN', True)
    pn_base = d.getVar('PN_BASE', True)
    imageext = d.getVar('IMAGE_BUNDLE_NAME', True) or ''
    if bndl and bndl != 'os-core':
        bb.debug(2, "Skipping swupd_create_rootfs() in bundle image %s for bundle %s." % (pn, bndl))
        return

    havebundles = (d.getVar('SWUPD_BUNDLES', True) or '') != ''
    if not havebundles:
        bb.debug(2, 'Skipping swupd_create_rootfs(), original rootfs can be used as no additional bundles are defined')
        return

    # Sanity checking was already done in swupdimage.bbclass.
    # Here we can simply use the settings.
    imagebundles = d.getVarFlag('SWUPD_IMAGES', imageext, True).split() if imageext else []
    rootfs = d.getVar('IMAGE_ROOTFS', True)
    rootfs_contents = []
    if not pn_base: # the base image
        import subprocess

        # For the base image only we need to remove all of the files that were
        # installed during the base do_rootfs and replace them with the
        # equivalent files from the mega image.
        #
        # The virtual image recipes will already have an empty rootfs.
        outfile = d.expand('${WORKDIR}/orig-rootfs-manifest.txt')
        rootfs = d.getVar('IMAGE_ROOTFS', True)
        # Generate a manifest of the current file contents
        # TODO: use the same common utility method
        manifest_cmd = 'cd %s && find . ! -path . > %s' % (rootfs, outfile)
        subprocess.call(manifest_cmd, shell=True, stderr=subprocess.STDOUT)
        # Remove the current rootfs contents
        oe.path.remove('%s/*' % rootfs)
        for entry in manifest_to_file_list(outfile):
            rootfs_contents.append(entry[2:])
        # clean up
        os.unlink(outfile)
    else: # non-base image, i.e. swupdimage
        manifest = d.expand("${DEPLOY_DIR_SWUPD}/image/${OS_VERSION}/os-core${SWUPD_ROOTFS_MANIFEST_SUFFIX}")
        rootfs_contents.extend(manifest_to_file_list(manifest))

    bb.debug(3, 'rootfs_contents has %s entries' % (len(rootfs_contents)))
    for bundle in imagebundles:
        manifest = d.expand("${DEPLOY_DIR_SWUPD}/image/${OS_VERSION}/%s${SWUPD_ROOTFS_MANIFEST_SUFFIX}") % bundle
        rootfs_contents.extend(manifest_to_file_list(manifest))

    mega_rootfs = d.getVar('MEGA_IMAGE_ROOTFS', True)
    bb.debug(2, 'Re-copying rootfs contents from mega image %s to %s' % (mega_rootfs, rootfs))
    copyxattrfiles(d, rootfs_contents, mega_rootfs, rootfs)

    deploy_dir = d.getVar('IMGDEPLOYDIR', True)
    link_name = d.getVar('IMAGE_LINK_NAME', True)
    # Create .rootfs.manifest for bundle images as the union of all
    # contained bundles. Otherwise the image wouldn't have that file,
    # which breaks certain image types ("toflash" in the Edison BSP)
    # and utility classes (like isafw.bbclass).
    if imageext:
        packages = set()
        manifest = d.getVar('IMAGE_MANIFEST', True)
        for bundle in imagebundles:
            bundlemanifest = manifest.replace(pn, 'bundle-%s-%s' % (pn_base, bundle))
            if not os.path.exists(bundlemanifest):
                bundlemanifest = deploy_dir + '/' + link_name + '.manifest'
                bundlemanifest = bundlemanifest.replace(pn, 'bundle-%s-%s' % (pn_base, bundle))
            with open(bundlemanifest) as f:
                 packages.update(f.readlines())
        with open(manifest, 'w') as f:
            f.writelines(sorted(packages))
        # Also write a manifest symlink
        if os.path.exists(manifest):
            manifest_link = deploy_dir + '/' + link_name + '.manifest'
            if os.path.lexists(manifest_link):
                if d.getVar('RM_OLD_IMAGE', True) == "1" and \
                        os.path.exists(os.path.realpath(manifest_link)):
                    os.remove(os.path.realpath(manifest_link))
                os.remove(manifest_link)
            bb.debug(3, 'Linking composed rootfs manifest from %s to %s' % (manifest, manifest_link))
            os.symlink(os.path.basename(manifest), manifest_link)
