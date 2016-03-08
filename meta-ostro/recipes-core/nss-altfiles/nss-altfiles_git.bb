LICENSE = "LGPL2.1"
LIC_FILES_CHKSUM = "file://COPYING;md5=fb1949d8d807e528c1673da700aff41f"

SRC_URI = "git://github.com/aperezdc/nss-altfiles.git;protocol=https"

# Modify these as desired
PV = "2.19.2+git${SRCPV}"
SRCREV = "8a7a5478be0b8047e8c88ed6e8efa1282d341f48"

S = "${WORKDIR}/git"

SECURITY_CFLAGS = "${SECURITY_NO_PIE_CFLAGS}"

# nss-altfiles build rules are defined in a custom Makefile.
# Additional compile flags can be set with a configure shell script.
# Compilation then must use normal make instead of oe_runmake, because
# the later causes (among others) CFLAGS and CPPFLAGS to be
# overridden, which would disable important parts of the build
# rules.
do_configure () {
        ./configure --datadir=${datadir}/defaults/etc --with-types=rpc,hosts,network,service,pwd,grp,spwd,sgrp 'CFLAGS=${CFLAGS}' 'CXXFLAGS=${CXXFLAGS}'
        # Reconfiguring with different options does not cause a rebuild. Must clean
        # explicitly to achieve that.
        make MAKEFLAGS= clean
}

# TODO: QA Issue: ELF binary '/fast/build/ostro/x86/tmp-glibc/work/i586-ostro-linux/nss-altfiles/2.19.2+gitAUTOINC+8a7a5478be-r0/packages-split/nss-altfiles/lib/libnss_altfiles.so.2' has relocations in .text [textrel]
do_compile () {
	make MAKEFLAGS=
}

do_install () {
	make MAKEFLAGS= install 'DESTDIR=${D}'
}
