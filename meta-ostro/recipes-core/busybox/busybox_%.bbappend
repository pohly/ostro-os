do_configure_append () {
    sed -i -e 's/^\(CONFIG_\(KLOGD\|SYSLOGD\)\)=y/# \1 is not set/' ${S}/.config
}

SYSTEMD_PACKAGES_remove = "${PN}-syslog"
ALTERNATIVE_${PN}-syslog_remove = "syslog-conf"
