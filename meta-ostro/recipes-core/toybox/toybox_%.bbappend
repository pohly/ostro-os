FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

PV = "0.7.0"
SRC_URI[md5sum] = "d86c78624b47625c2f0fc64eda599443"
SRC_URI[sha256sum] = "65428816f88ad3fe92b67df86dc05427c8078fe03843b8b9715fdfa6d29c0f97"

# Fixes usage as non-root when installed suid root.
SRC_URI += "file://main.c-fix-non-root-usage-when-installed-suid-root.patch"

# Fixes a race condition when compiling under load (https://github.com/landley/toybox/issues/24):
# "wait: pid .... is not a child of this shell"
SRC_URI += "file://Switch-to-for-make.sh-process-enumeration.patch"

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

# Sets the compiler for native tools.
# Necessary for building generated/instlist when Smack is enabled.
HOSTCC="${BUILD_CC} ${BUILD_CFLAGS} ${BUILD_CPPFLAGS} ${BUILD_LDFLAGS}"
export HOSTCC
