do_install_append () {
    # The base recipe sets GROUP=100="users" as shared group for all
    # users. In Ostro, each user gets its own group (more secure default
    # because it prevents accidental data sharing when setting something
    # group read/writeable).
    sed -i -e 's/^GROUP=/# GROUP=/' ${D}/${sysconfdir}/default/useradd

    # OE-core only prints the motd when logging in via tty (via the "login" PAM config),
    # but not when logging in via ssh. We want this to be enabled consistently, in
    # particular because development images add a warning to motd, so we enabled
    # motd in the shared "common-session" config file and disable motd in
    # the login-specific config file (see libpam_%.bbappend)
    f=${D}/${sysconfdir}/pam.d/login
    [ ! -f $f ] || sed -i -e 's;^\(session.*pam_motd.so.*\);# Ostro OS moved motd to common-session: \1;' $f
}
