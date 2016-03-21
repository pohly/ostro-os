# Our initial strategy to generate bundles for consumption by swupd is to
# generate images which contain the base image (os-core) plus the additional
# contents of the bundle, then prune out the core contents. By generating
# images in this manner we hope to accomodate packages which modify the rootfs
# outside of installing files, i.e.with postinsts.
#
# To that end this class, to be used via BBCLASSEXTEND, will generate virtual
# image recipes that add extra packages to the extended image.
#
# Only extensions matching entries in a SWUPD_BUNDLES variable are valid and
# the bundle contents should be listed in a varFlag matching the bundle's name
# on the BUNDLE_CONTENTS variable. i.e in foo-image.bb:
#
# Note: the bundle name 'mega' is reserved for use in a composed image which
# contains all bundle contents.
#
# SWUPD_BUNDLES = "foo bar"
# BUNDLE_CONTENTS[foo] = "foo foo-bar foobaz"
# BUNDLE_CONTENTS[bar] = "bar baz quux"
# BBCLASSEXTEND = "swupdbundle:foo"

python swupdbundle_virtclass_handler () {
    pn = e.data.getVar("PN", True)
    cls = e.data.getVar("BBEXTENDCURR", True)
    bundle = e.data.getVar("BBEXTENDVARIANT", True)

    if cls != 'swupdbundle':
        return

    if not bundle:
        bb.fatal('swupdbundle must be used with a parameter i.e. BBCLASSEXTEND="swupdbundle:foo"')

    # Rename the virtual recipe to create the desired image bundle variant.
    e.data.setVar("PN_BASE", pn)
    pn = 'bundle-' + pn + '-' + bundle
    e.data.setVar("PN", pn)
    e.data.setVar("BUNDLE_NAME", bundle)

    curr_install = (e.data.getVar('IMAGE_INSTALL', True) or "").split()

    def get_bundle_contents(bndl):
        contents = e.data.getVarFlag('BUNDLE_CONTENTS', bndl, True)
        if contents:
            return contents.split()
        else:
            bb.fatal('BUNDLE_CONTENTS[%s] is not set, this should list the packages to be included in the bundle.' % bndl)

    if bundle == 'mega':
        bundles = (e.data.getVar('SWUPD_BUNDLES', True) or "").split()
        for bndl in bundles:
            curr_install += get_bundle_contents(bndl)
    else:
        curr_install += get_bundle_contents(bundle)

    e.data.setVar('IMAGE_INSTALL', ' '.join(curr_install))
}

addhandler swupdbundle_virtclass_handler
swupdbundle_virtclass_handler[eventmask] = "bb.event.RecipePreFinalise"
