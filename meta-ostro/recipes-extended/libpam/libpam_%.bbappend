FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"

do_install_append_class-target () {
    # OE-core only prints the motd when logging in via tty (via the "login" PAM config),
    # but not when logging in via ssh. We want this to be enabled consistently, in
    # particular because development images add a warning to motd, so we enabled
    # motd in the shared "common-session" config file and disable motd in
    # the login-specific config file (see shadow_%.bbappend)
    f=${D}/${sysconfdir}/pam.d/common-session
    [ ! -f $f ] || grep -q pam_motd.so $f || echo >>$f "session optional pam_motd.so"
}
