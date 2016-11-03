require pseudo.inc

SRCREV = "d5a6b5e2d23288452b374a1ffe32b6b3e52c13fc"
PV = "1.8.1+git${SRCPV}"

DEFAULT_PREFERENCE = "-1"

SRC_URI = "git://git.yoctoproject.org/pseudo \
           file://0001-configure-Prune-PIE-flags.patch \
           file://fallback-passwd \
           file://fallback-group \
           file://moreretries.patch"

S = "${WORKDIR}/git"

