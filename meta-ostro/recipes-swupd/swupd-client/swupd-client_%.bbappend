FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"

inherit systemd

SRC_URI_append = "file://0001-Disable-boot-file-heuristics.patch \
                  file://efi_combo_updater.c \
                  ${@ 'file://efi-combo-trigger.service' if ${OSTRO_USE_DSK_IMAGES} else ''} \
                 "

RDEPENDS_${PN}_class-target_append = "${@ ' gptfdisk' if ${OSTRO_USE_DSK_IMAGES} else '' }"

do_compile_append() {
    if [ "${OSTRO_USE_DSK_IMAGES}" = "True" ]; then
        ${CC} ${LDFLAGS} ${WORKDIR}/efi_combo_updater.c  -Os -o ${B}/efi_combo_updater `pkg-config --cflags --libs glib-2.0`
    fi
}

do_install_append () {
    if [ "${OSTRO_USE_DSK_IMAGES}" = "True" ]; then
        install -d ${D}/usr/bin
        install ${B}/efi_combo_updater ${D}/usr/bin/
    fi
}
