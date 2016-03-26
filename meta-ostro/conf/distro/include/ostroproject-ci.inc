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

# Configure images in "development mode", but without the additional
# packages in the ostro-image itself. Instead, swupd images are enabled
# below.
require conf/distro/include/ostro-os-development.inc
OSTRO_DEVELOPMENT_EXTRA_FEATURES = ""
OSTRO_DEVELOPMENT_EXTRA_INSTALL = ""

# XXX Drop the VM hack after taking care also of the non UEFI devices
# (those using U-Boot: edison and beaglebone)
OSTRO_VM_IMAGE_TYPES = "dsk.xz dsk.zip dsk.vdi.zip dsk.bmap dsk.xz.sha256sum dsk.vdi.zip.sha256sum"

do_swupd_update_prepend () {
    # The CI testing setup only knows about testing "ostro-image".
    # Provide a symlink to the real image that we want to have
    # tested.
    if [ "${PN}" = "ostro-image" ]; then
        bbwarn "Setting up ostro-image CI testing compatibility links"
        for i in '${IMAGE_NAME}.dsk.xz' '${IMAGE_NAME}-disk-layout.json' 'ostro-image-beaglebone.tar.bz2' 'ostro-image-edison.toflash.tar.bz2'; do
            if echo $i | grep -q ${MACHINE}; then
                target=$(echo $i | sed -e 's/ostro-image-/ostro-image-qa-/')
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
OSTROPROJECT_CI_BUILD_TARGETS="ostro-image ostro-image-qa ostro-image-reference"
# Following targets would be executed with do_populate_sdk task
OSTROPROJECT_CI_SDK_TARGETS=""
# Following targets would be executed with do_populate_sdk_ext task.
# Uses the fully-populated image to ensure that the eSDK is as complete
# as possible.
OSTROPROJECT_CI_ESDK_TARGETS="ostro-image-all"
# Following targets would be executed with do_test_iot_export task.
# Must be "ostro-image", the task seems to expect that name.
OSTROPROJECT_CI_TEST_EXPORT_TARGETS="ostro-image"
# Execute automatic tests for following images with corresponding
# test suite and test files.
# Space separated list of tuples, each should in format:
# <image_name>,<testsuite_name>,<testfiles_name>,$MACHINE
OSTROPROJECT_CI_TEST_RUNS="${DISTRO}-image,iot-testsuite.tar.gz,iot-testfiles.${MACHINE}.tar.gz,${MACHINE}"

# ostro-image as build target above shall only produce bundles,
# but no images.
OSTRO_VM_IMAGE_TYPES_pn-ostro-image = ""
IMAGE_FSTYPES_pn-ostro-image = ""

# Enable swupd images and bundle creation.
OSTRO_IMAGE_EXTRA_FEATURES += "swupd"

#
# Dymamic section.
# Values are applied dynamically based on runtime config or builder host
# parameters.
# Present here as reference only.
#

# Explicit machine declaration by build job:
# MACHINE = "$TARGET_MACHINE"

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
