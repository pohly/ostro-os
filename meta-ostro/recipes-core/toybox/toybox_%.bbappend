FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI = "git://github.com/gfto/toybox.git;protocol=https"
PV = "0.7.0+git-${SRCREV}"
SRCREV = "9fcaca8434ece1afcc9982c18a86cf12ac9af508"
S ="${WORKDIR}/git"

DEPENDS_append_smack = " smack attr"
do_configure_append_smack () {
    # Enable smack in toybox.
    sed -e 's/# CONFIG_TOYBOX_SMACK is not set/CONFIG_TOYBOX_SMACK=y/' -i .config

    # Enable LSM support. Not immediately obvious where that is relevant
    # (some Smack support also works without it), but it is better to
    # set this consistently.
    sed -e 's/CONFIG_TOYBOX_LSM_NONE=y/# CONFIG_TOYBOX_LSM_NONE is not set/' -i .config
}

# Toybox sh is not enabled by default and too incomplete to execute
# the initramfs-framework scripts. Therefore dash is needed in
# addition to toybox when replacing busybox.
RDEPENDS_${PN} += "dash"

# "awk" is expected by initramfs-framework. Toybox does not have it at all.
# Depending on gawk leads to a dependency on an old gawk or a recent one
# under GPLv3. For now that's okay, but it would be better to not depend
# on awk in initramfs-framework.
RDEPENDS_${PN} += "gawk"

# toybox mount ignores mount options.
RDEPENDS_${PN} += "util-linux-mount"

# "tr" is apparently still incomplete, but good enough for
# initramfs-framework.
do_configure_append () {
    sed -e 's/# CONFIG_TR is not set/CONFIG_TR=y/' -i .config
}

# "mesg" is expected by the default .profile. Avoid confusing errors
# by providing a stub. mesg is used to control whether other users
# can write to a users terminal. Ostro OS isn't a multi-user, interactive
# OS, so that loss of functionality isn't important.
SRC_URI += "file://mesg"
do_install_append () {
    install -d ${D}/${bindir}
    install ${WORKDIR}/mesg ${D}/${bindir}
}

# grep produces no output. Fall back to sed from coreutils. This
# works only in Ostro because normally, pulling in coreutils would
# override all of Toybox. But in ostro-image.bbclass, Toybox gets a priority
# boost that prevents that.
#
# TODO: investigate sed failure. Can be done by symlinking to it,
# because the grep toy is still in the binary.
do_compile_append () {
    grep -v -w grep toybox.links >toybox.links_ && mv toybox.links_ toybox.links
}
RDEPENDS_${PN}_append = " grep"

# Sets the compiler for native tools.
# Necessary for building generated/instlist when Smack is enabled.
HOSTCC="${BUILD_CC} ${BUILD_CFLAGS} ${BUILD_CPPFLAGS} ${BUILD_LDFLAGS}"
export HOSTCC

# Fix for upstream 0.6.0 .bb: toybox_unstripped -> generated/unstripped/toybox
do_compile() {
    oe_runmake generated/unstripped/toybox && cp -a generated/unstripped/toybox toybox_unstripped

    # Create a list of links needed
    ${HOSTCC} -I . scripts/install.c -o generated/instlist
    ./generated/instlist long | sed -e 's#^#/#' > toybox.links
}

# grep produces no output. Fall back to sed from coreutils. This
# works only in Ostro because normally, pulling in coreutils would
# override all of Toybox. But in ostro-image.bbclass, Toybox gets a priority
# boost that prevents that.
#
# TODO: investigate sed failure. Can be done by symlinking to it,
# because the grep toy is still in the binary.
do_compile_append () {
    grep -v -w grep toybox.links >toybox.links_ && mv toybox.links_ toybox.links
}
RDEPENDS_${PN}_append = " grep"
