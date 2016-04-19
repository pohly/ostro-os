SUMMARY = "Ostro image with swupd enabled."

# Image configuration changes cannot be done using the
# _pn-ostro-image-swupd notation, because then the configuration of
# this base image and the virtual images created from it would be
# different.
#
# Instead extend these variables.
OSTRO_IMAGE_SWUPD_EXTRA_FEATURES ?= ""
OSTRO_IMAGE_SWUPD_EXTRA_INSTALL ?= ""
OSTRO_IMAGE_EXTRA_FEATURES += "${OSTRO_IMAGE_SWUPD_EXTRA_FEATURES}"
OSTRO_IMAGE_EXTRA_INSTALL += "${OSTRO_IMAGE_SWUPD_EXTRA_INSTALL}"

# Enable swupd.
OSTRO_IMAGE_EXTRA_FEATURES += "swupd"

# Define os-core content and additional bundles. Which bundles are
# useful depends on the use cases. For Ostro OS example images, all we
# care about at the moment is
# a) to demonstrate that bundles can be added and removed
# b) build two different images (minimal and for on-target development)
#
# This can be achieved with just the os-core bundle (defined by the
# content of this image recipe here) and one additional bundle
# with the development tools and files.
#
# Keeping the number of bundles as low as possible is good for build
# performance, too.
SWUPD_BUNDLES ?= " \
    world-dev \
"

# os-core defined via additional image features maintained in ostro-image.bbclass.
OSTRO_IMAGE_EXTRA_FEATURES += "${OSTRO_IMAGE_FEATURES_REFERENCE}"
OSTRO_IMAGE_EXTRA_INSTALL += "${OSTRO_IMAGE_INSTALL_REFERENCE}"

# One additional bundle for on-target development.
# Must contain all of the Ostro OS components because
# otherwise they would not be available via swupd.
#
# Developers are able to tweak this bundle (for example, disabling the
# JDK because building Java is slow) by modifying the variable in
# their local.conf (BUNDLE_CONTENTS_WORLD_remove = "java-jdk") or
# overridding it entirely (BUNDLE_CONTENTS_WORLD = "iotivity").
#
# Features already added to the os-core are listed here again
# for the sake of simplicity. To remove them, both BUNDLE_CONTENTS_WORLD
# and OSTRO_IMAGE_EXTRA_FEATURES need to be modified.
#
# We re-use OSTRO_IMAGE_PKG_FEATURES here, so Ostro OS components only
# need to be listed once in ostro-image.bbclass. The variable expansion
# is done so that bitbake sees the FEATURE_PACKAGES_foobar variables
# and thus can add them to the vardeps of BUNDLE_CONTENTS_WORLD.
BUNDLE_CONTENTS_WORLD ?= " \
    ${@ ' '.join(['$' + chr(123) + 'FEATURE_PACKAGES_' + x + chr(125)  for x in d.getVar('OSTRO_IMAGE_PKG_FEATURES', True).split()])} \
    ${OSTRO_IMAGE_INSTALL_DEV} \
"

BUNDLE_CONTENTS[world] = " \
    ${BUNDLE_CONTENTS_WORLD} \
"

# When swupd bundles are enabled, choose explicitly which images
# are created. The base image will only have the core-os bundle.
#
# The additional images will be called <base image recipe>-<name in SWUPD_IMAGES>,
# for example ostro-image-swupd-dev in this case.
#
# Taking all this into account, we end up with the following images:
# ostro-image-swupd -
#    Base image plus login via getty and ssh, plus connectivity.
#    This is what developers are expected to start with when
#    building their first image.
# ostro-image-swupd-dev -
#    Image used for testing Ostro OS. Contains most of the software
#    pre-installed, including the corresponding development files
#    for on-target compilation.
# ostro-image-swupd-all -
#    Contains all defined bundles. Useful as meta target, but not
#    guaranteed to build images successfully, for example because
#    the content might get too large for machines with a fixed image
#    size.
SWUPD_IMAGES ?= " \
    dev \
    all \
"

# In practice the same as "all" at the moment, but conceptually different
# and thus defined separately.
SWUPD_IMAGES[dev] = " \
    ${SWUPD_BUNDLES} \
"
SWUPD_IMAGES[all] = " \
    ${SWUPD_BUNDLES} \
"

# Inherit the base class after changing relevant settings like
# the image features, because the class looks at them at the time
# when it gets inherited.
inherit ostro-image
