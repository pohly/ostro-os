require pkgconfig.inc

PR = "r7"

SRC_URI += "file://autofoo.patch \
            file://glibconfig-sysdefs.h \
            file://pkg-config-native.in \
            file://disable-legacy.patch \
            file://obsolete_automake_macros.patch \
           "

SRC_URI[md5sum] = "a3270bab3f4b69b7dc6dbdacbcae9745"
SRC_URI[sha256sum] = "3ba691ee2431f32ccb8efa131e59bf23e37f122dc66791309023ca6dcefcd10e"
