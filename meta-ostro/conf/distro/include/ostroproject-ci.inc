#
# https://ostroproject.org/jenkins CI configuration:
# This file applied via conf/auto.conf for every build
# happening in Ostro Project CI
#

#
# Static section
# Items that are always present in any CI build:
#

# Generate summary statistics
INHERIT += "buildstats-summary"

# Enable CVE and other secutiry checks
INHERIT += "isafw"

# Enable extended buildhistory:
INHERIT += "buildhistory"
BUILDHISTORY_COMMIT = "1"
INHERIT += "buildhistory-extra"

# Test data generation:
INHERIT += "test-iot"
TEST_EXPORT_DIR = "iottest"
TEST_TARGET = "simpleremote"

# SDK defaults:
SDKMACHINE ?= "x86_64"

# Generate source mirror tarballs:
BB_GENERATE_MIRROR_TARBALLS = "1"

# If (and only if) building in the CI, the BUILD_ID is guaranteed to
# be consistent across different builds and therefore it can and
# should be included in the os-release package.
#
# When doing the same outside of the CI, we'd end up with an
# os-release file that has BUILD_ID = ${DATETIME} for the first time
# that the os-release file was generated. It does not get re-generated
# (explicit vardepsexclude in os-release.bb) because that would cause
# constant rebuilds.
OS_RELEASE_FIELDS_append = " BUILD_ID"

# Configure images in "development mode", but without the additional
# packages in the ostro-image itself. Instead, swupd images are enabled
# below.
require conf/distro/include/ostro-os-development.inc
OSTRO_DEVELOPMENT_EXTRA_FEATURES = ""
OSTRO_DEVELOPMENT_EXTRA_INSTALL = ""

# XXX Drop the VM hack after taking care also of the non UEFI devices
# (those using U-Boot: edison and beaglebone)
OSTRO_VM_IMAGE_TYPES = "dsk.xz dsk.zip dsk.vdi.zip"

# Temporarily disable Edison "toflash" image format
# because depends on a .rootfs.manifest that is not gettting
# created for swupd images. Looks like we need to create that
# file after all, the security checks also want it.
IMAGE_FSTYPES_remove_pn-edison = "toflash"

do_swupd_update_prepend () {
    # The CI testing setup only knows about testing "ostro-image".
    # Provide a symlink to the real image that we want to have
    # tested.
    if [ "${PN}" = "ostro-image" ]; then
        bbwarn "Setting up ostro-image CI testing compatibility links"
        for i in '${IMAGE_NAME}.dsk.xz' '${IMAGE_NAME}-disk-layout.json' 'ostro-image-beaglebone.tar.bz2' 'ostro-image-edison.toflash.tar.bz2'; do
            if echo $i | grep -q ${MACHINE}; then
                target=$(echo $i | sed -e 's/ostro-image-/ostro-image-dev-/')
                bbwarn "symlink ${DEPLOY_DIR_IMAGE}/$i -> $target"
                mkdir -p "${DEPLOY_DIR_IMAGE}"
                ln -s "$target" "${DEPLOY_DIR_IMAGE}/$i"
            fi
        done
    fi
}

#
# Automated build targets
# Those targets should be space separated list of items,
# which must contain only alphanumeric symbols,'-' and '_'.
# Any other symbols would be skipped in parser.
#
# Following targets would be used to perform default build task.
OSTROPROJECT_CI_BUILD_TARGETS="ostro-image ostro-image-dev ostro-image-reference"
# Following targets would be executed with do_populate_sdk task
OSTROPROJECT_CI_SDK_TARGETS=""
# Following targets would be executed with do_populate_sdk_ext task.
# Uses the fully-populated image to ensure that the eSDK is as complete
# as possible.
OSTROPROJECT_CI_ESDK_TARGETS="ostro-image-all"
# Following targets would be executed with do_test_iot_export task.
# Must be "ostro-image", the task seems to expect that name.
OSTROPROJECT_CI_TEST_EXPORT_TARGETS="ostro-image"

# ostro-image as build target above shall only produce bundles,
# but no images.
OSTRO_VM_IMAGE_TYPES_pn-ostro-image = ""
IMAGE_FSTYPES_pn-ostro-image = ""

# Enable swupd images and bundle creation.
OSTRO_IMAGE_EXTRA_FEATURES += "swupd"

# In the CI system, the integer OS version used for swupd is derived
# from the Jenkins build number part of the BUILD_ID. The conversion
# to int and back to string acts as sanity check that we really get a
# number out of the BUILD_ID.
#
# We multiply it by ten, to ensure that the version space has some gap
# for minor updates. How to actually build minor updates with Jenkins
# still needs to be determined.
OS_VERSION = "${@ str(int('${BUILD_ID}'.split('-')[-1]) * 10) }"

#
# Dymamic section.
# Values are applied dynamically based on runtime config or builder host
# parameters.
# Present here as reference only.
#

# Explicit machine declaration by build job:
# MACHINE = "$TARGET_MACHINE"

# Build number shared by all jobs across the different machines:
# BUILD_ID = "<parent-build-timestamp (of Jenkins top job)>" + "-build-" + "<jenkins-top-job-build-number>"

# Shared download directory between builders:
# DL_DIR = "/srv/bb-cache/ostro-os/sources"

# Limit CPU utilization, based on amount of slots/CPU cores
# on builder hosts:
# BB_NUMBER_PARSE_THREADS = "X"
# BB_NUMBER_THREADS = "X"
# PARALLEL_MAKE = "-j X"

# Local optimizations on SSTATE directories, shared between builder hosts:
# SSTATE_MIRRORS ?= "file://.* http://$IP/bb-cache/ostro-os/sstate/PATH"
# SSTATE_DIR ?= "/var/tmp/sstate-$slot"

# Local directory, where builder puts local copy of buildhistory
# BUILDHISTORY_DIR ?="$WORKSPACE/buildhistory"

# PRserv host dynamically allocated by master:
# PRSERV_HOST = "$IP:$PORT"

# Enabled for master release builds:
# INHERIT += "archiver"
# ARCHIVER_MODE[src] = "original"
# ARCHIVER_MODE[diff] = "1"
# ARCHIVER_MODE[recipe] = "1"
