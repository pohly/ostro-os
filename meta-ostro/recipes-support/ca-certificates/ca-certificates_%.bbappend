FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append = "\
    file://update-ca-certificates-support-Toybox.patch \
    file://update-ca-certificates.service \
    file://update-ca-certificates.sh \
"

SYSTEMD_SERVICE_${PN} = "update-ca-certificates.service"
inherit systemd

do_install_append_class-target () {
    # Replace original update-ca-certificates with a shell script
    # that simply triggers the new systemd service.
    install -d ${D}/${libdir}/ca-certificates
    mv ${D}/${sbindir}/update-ca-certificates ${D}/${libdir}/ca-certificates
    install ${WORKDIR}/update-ca-certificates.sh ${D}/${sbindir}/update-ca-certificates
    install -d ${D}/${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/update-ca-certificates.service ${D}/${systemd_system_unitdir}/update-ca-certificates.service
}
