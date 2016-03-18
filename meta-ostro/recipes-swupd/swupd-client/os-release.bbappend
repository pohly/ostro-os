# swupd-client checks VERSION_ID, which must match the OS_VERSION
# used for generating swupd bundles in the current build.
VERSION_ID = "${OS_VERSION}"

FILES_${PN}_append = " /usr/lib/os-release "

do_install_append() {
    install -d ${D}/usr/lib
    mv ${D}/etc/os-release ${D}/usr/lib
    ln -s ../usr/lib/os-release ${D}/etc/os-release
}
