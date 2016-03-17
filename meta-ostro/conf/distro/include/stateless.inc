INHERIT += "stateless"

# Package QA check which greps for known bad paths which should
# not be used anymore, like files which used to be in /etc and
# got moved elsewhere.
STATELESS_DEPRECATED_PATHS = ""
ERROR_QA += "stateless"

# If set to True, a recipe gets configured with
# sysconfdir=${datadir}/defaults. If set to a path, that
# path is used instead. In both cases, /etc typically gets
# ignored and the component no longer can be configured by
# the device admin.
STATELESS_RELOCATE = "False"

# A space-separated list of recipes which may contain files in /etc.
STATELESS_PN_WHITELIST = ""

# A space-separated list of shell patterns. Anything matching a
# pattern is allowed in /etc (for now - eventually this must
# become empty). Changing this influences the QA check in do_package
# and do_rootfs.
STATELESS_ETC_WHITELIST = "${STATELESS_ETC_DIR_WHITELIST}"

# A subset of STATELESS_ETC_WHITELIST which also influences do_install
# and determines which directories to keep.
STATELESS_ETC_DIR_WHITELIST = ""

# A space-separated list of entries in /etc which need to be moved
# away. Default is to move into ${datadir}/doc/${PN}/etc. The actual
# new name can also be given with old-name=new-name, as in
# "pam.d=${datadir}/pam.d".
STATELESS_MV = ""

# A space-separated list of entries in /etc which can be removed
# entirely.
STATELESS_RM = ""

# Same as the previous ones, except that they get applied to the rootfs.
STATELESS_RM_ROOTFS = ""
STATELESS_MV_ROOTFS = ""

# This entry here allows everything in /etc.
# It's useful while working on stateless configuration
# because it removes the need to update STATELESS_ETC_WHITELIST
# more selectively, which triggers a repackaging and thus
# slows down development cycles.
#
# TODO: comment out in final patch set.
STATELESS_ETC_WHITELIST += "*"

############################################################################

# Only used in initramfs, can be ignored.
STATELESS_PN_WHITELIST += "initramfs-framework-ima"

# Not actually installed.
STATELESS_PN_WHITELIST += "shadow-sysroot"

# Not used?
STATELESS_PN_WHITELIST += "initscripts"

# TODO later
STATELESS_ETC_WHITELIST += " \
    rsyncd.conf \
    iptables/* \
    *wpa[-_]supplicant* \
    securetty \
"

# TODO: for each of these we need a working alternative
STATELESS_MV_pn-base-files = " \
    issue.net \
    host.conf \
    hostname \
    profile \
    issue \
    shells \
    filesystems \
    motd \
    mtab \
    skel \
    default \
    nsswitch.conf=${datadir}/defaults/etc/nsswitch.conf \
    smack=${datadir}/defaults/etc/smack \
"

# Ostro OS boots without /etc/fstab. This only works
# when mounting the root filesystem already rw in the
# initramfs, because without an entry for the rootfs
# in /etc/fstab, systemd won't remount a read-only
# rootfs as rw and booting (currently) fails.
#
# This skips fsck. This may or may not be desirable (see
# "[Ostro-dev] usefulness of fsck"). If it turns out
# to be desirable, then creating a mount unit for the
# rootfs might help.
#
# Additional mounts can also be handled that way, should
# they become necesary.
APPEND_append = " rw"
APPEND_remove = "ro"
STATELESS_MV_ROOTFS += "fstab"
STATELESS_ETC_WHITELIST += "fstab"

STATELESS_ETC_WHITELIST += "smack/*"
# Smack default configurations from base-files have
# been moved away from /etc. Systemd has been patched
# so that we can give default rules path to its configure.
# Patch should still always look also from /etc the
# existence of locally configured rules which are
# read in addition to possible default rules
EXTRA_OECONF_append_pn-systemd = " --with-smack-default-rules-path=${datadir}/defaults/etc"

# nscd support is disabled via patch.
STATELESS_RM_pn-glibc = " \
    ld.so.conf \
    init.d/nscd \
    nscd.conf \
    tmpfiles.d/nscd.conf \
"

STATELESS_RM_pn-os-release = " \
    os-release \
"

# SSL certificates still come from ca-certificates, but the
# update-ca-certificates, its ca-certificates.conf and the
# entire resulting output under /etc/ssl get removed after
# creating the rootfs, so /etc/ssl/ca-certificates.crt is gone.
#
# What is used instead (via configure parameters, where necessary,
# and sometimes supported by additional patches):
# - /usr/share/ca-certificates has all certificates trusted by the
#   system
# - The optional /etc/ssl/cert.pem is a full trust store which can
#   add or revoke certificates (?).
#
# Clear Linux instructions for maintaining SSL certificates via
# /etc are out-dated (still explain about a /etc/ssl/certs directory,
# which is no longer in used because its content was moved to
# /usr/share/ca-certs). Nothing describes how to use /etc/ssl/cert.pem
# and it remains unclear whether it can really be used to revoke
# certificates. Most likely this would require additional tooling.
#
# TODO: it seems easier to make update-ca-certificates stateless:
# - move /etc/ssl/certs to /var/ssl/certs
# - make /etc/ca-certificates.conf optional
# - support /etc/ca-certificates/certs instead of /usr/local/share/ca-certificates
#   (because /usr/local is not supported for local administration)
# - support /usr/share/defaults/etc/update.d in addition to
#   /etc/ca-certificates/update.d (if we ever need it for system plugins)
STATELESS_FIX_SSL_PATHS = " \
    sed -i \
        -e 's;${sysconfdir}/ssl/certs;${localstatedir}/ssl/certs;g' \
        -e 's;/usr/local/share/ca-certificates;/etc/ca-certificates/certs;g' \
"
do_install_append_pn-ca-certificates_class-target () {
    ${STATELESS_FIX_SSL_PATHS}  \
        ${D}/${mandir}/man8/update-ca-certificates.8
}
EXTRA_OECONF_append_pn-curl = " \
    --with-ca-bundle=${localstatedir}/ssl/certs/ca-certificates.crt \
"
EXTRA_OECONF_remove_pn-curl = " \
    --with-ca-bundle=${sysconfdir}/ssl/certs/ca-certificates.crt \
"
stateless_patch_ssl_paths () {
    ${STATELESS_FIX_SSL_PATHS} \
        ${STATELESS_SSL_PATHS_TO_PATCH}
}
STATELESS_SSL_PATHS_TO_PATCH = ""
STATELESS_SSL_PATHS_TO_PATCH_pn-perl_class-target = " \
    $(find ${S} -name Tiny.pm) \
"
STATELESS_SSL_PATHS_TO_PATCH_pn-wget_class-target = " \
    ${S}/src/gnutls.c \
"
STATELESS_SSL_PATHS_TO_PATCH_pn-wpa-supplicant_class-target = " \
    ${S}/wpa_supplicant/wpa_supplicant.conf \
    ${S}/src/eap_peer/eap_config.h \
    ${WORKDIR}/wpa_supplicant.conf \
"
STATELESS_SSL_PATHS_TO_PATCH_pn-connman_class-target = " \
    ${S}/doc/connman-service.config.5.in \
"
STATELESS_SSL_PATHS_TO_PATH_pn-ca-certificates_class_target = " \
    ${S}/sbin/update-ca-certificates.8 \
"
do_patch[postfuncs] += "${@ 'stateless_patch_ssl_paths' if '${STATELESS_SSL_PATHS_TO_PATCH}' else ''}"
STATELESS_DEPRECATED_PATHS += "${sysconfdir}/ssl/certs"
STATELESS_MV_ROOTFS += " \
    ssl/certs=${localstatedir}/ssl/certs \
"
# The file is a complete list of all certificates provided by the system
# and therefore redundant, because those certificates are trusted even
# if not listed explicitly.
STATELESS_RM_ROOTFS += " \
    ca-certificates.conf \
"
STATELESS_ETC_WHITELIST += "ca-certificates.conf"
STATELESS_ETC_DIR_WHITELIST += "ssl/*"

STATELESS_RM_pn-tzdata = " \
    timezone \
    localtime \
"

# Ostro OS treats /usr/lib/locale/locale-archive as read-only part of
# the image, with content determined by IMAGE_LINGUAS. Local
# administrators cannot change this.
#
# This differs from Clear Linux, where /usr/lib/locale/locale-archive
# is a symlink to /var/cache/locale/locale-archive and the latter
# gets created at runtime via locale-archive-trigger.service.

# Whether the netbase files (services, protocols, hosts, rpc) need to
# be relocated depends on the image. It will be done during image
# creation.
STATELESS_PN_WHITELIST += "netbase"

# Base recipe copies some terminfo files to /etc and symlinks to
# them. Also sets up xterm-color as default xterm. We undo that here.
do_install_append_pn-ncurses () {
    for termlink in $(find ${D}${datadir}/terminfo -type l); do
        rm $termlink
        mv $(echo $termlink | sed -e 's;^${D}${datadir};${D}${sysconfdir};') $termlink
    done
    rm ${D}${sysconfdir}/terminfo/x/xterm
}
# TODO: avoid hard-coding the base files by maintaining a list
# in the upstream recipe.
FILES_${PN}-terminfo-base_append_pn-ncurses = "${@ ' '.join('${datadir}/terminfo/*/' + x for x in 'ansi console dumb linux rxvt screen screen-256color sun vt52 vt100 vt102 vt200 vt220 xterm-color xterm-xfree86 xterm-256color'.split())}"

# Files are empty by default.
STATELESS_MV_pn-tcp-wrappers = " \
    hosts.allow \
    hosts.deny \
"
FILES_${PN}-doc_append_pn-tcp-wrappers = " ${datadir}/doc"

# The recipe itself installs symlinks in ${sysconfdir}. We can redirect it into
# /lib instead.
sysconfdir_pn-systemd-serialgetty = "${base_libdir}"

STATELESS_MV_pn-readline = " \
   inputrc \
"

# Relies on several Clear Linux patches for changing the
# default options and the lookup of the moduli file.
# By default, root may log in, but only without a password (upstream default).
STATELESS_MV_pn-openssh = " \
   ssh/ssh_config \
   ssh/sshd_config \
   ssh/moduli=${datadir}/defaults/ssh/moduli \
   pam.d=${datadir}/pam.d \
"
STATELESS_RM_pn-openssh = " \
   ssh/sshd_config_readonly \
"
FILES_${PN}_append_pn-openssh = " ${datadir}/defaults ${datadir}/pam.d"

# /etc/dbus-1/session.d
# /etc/dbus-1/session-local.conf
# /etc/dbus-1/system.d
# /etc/dbus-1/system-local.conf
# are used if (and only if) present, whereas
# the actual system config tree is under /usr/share/dbus.
# Clear Linux had to patch dbus for that, the current
# dbus 1.10 in OE-core supports that without patches
# and without special configuration options. D-Bus
# services however may need to be updated to put
# their configuration files into  /usr/share/dbus-1:
# properly written services will use dbus-1.pc to
# find the paths, which are under /usr/share, but
# not all services use that.
STATELESS_MV_pn-dbus = " \
    dbus-1/system.conf \
    dbus-1/session.conf \
"

STATELESS_RELOCATE_pn-libnl = "True"
STATELESS_RELOCATE_pn-e2fsprogs = "True"

# Moving systemd/system from /etc/ to /lib works because
# relative symlinks remain valid. If we were to move elsewhere
# we would have to fix up relative symlinks.
STATELESS_MV_pn-systemd = " \
    pam.d=${datadir}/pam.d \
    dbus-1=${datadir}/dbus-1 \
    tmpfiles.d=${libdir}/tmpfiles.d \
    systemd/system=${base_libdir}/systemd/system \
    udev/rules.d=${base_libdir}/udev/rules.d \
    udev/udev.conf \
    systemd/bootchart.conf \
    systemd/journald.conf \
    systemd/logind.conf \
    systemd/system.conf \
    systemd/timesyncd.conf \
    systemd/user.conf \
"
FILES_${PN}_append_pn-systemd = " ${datadir}/defaults ${datadir}/pam.d ${datadir}/dbus-1"

# A symlink to /etc/systemd/user. Removed without replacement.
# Probably violates some XDG standard?
STATELESS_RM_pn-systemd += "xdg/systemd/user"
# Managed by connman at runtime.
STATELESS_RM_pn-systemd += "resolv.conf"

# Only two options are set:
# net.ipv4.conf.default.rp_filter=1
# net.ipv4.conf.all.rp_filter=1
STATELESS_MV_pn-procps = " \
    sysctl.conf \
    sysctl.d \
"

STATELESS_RELOCATE_pn-keyutils = "True"

STATELESS_MV_pn-ppp = " \
    chatscripts \
    ppp \
"

STATELESS_MV_pn-wget = " \
    wgetrc \
"

STATELESS_MV_pn-util-linux = " \
    pam.d=${datadir}/pam.d \
    default/mountall \
"
FILES_${PN}_append_pn-util-linux = " ${datadir}/pam.d"

# /etc/bluetooth only contains commented-out options, not required?
# bluez5.inc recipe hard-codes installation into ${sysconfdir},
# even though configure itself supports --with-dbusconfdir.
STATELESS_MV_pn-bluez5 = " \
    bluetooth \
    dbus-1=${datadir}/dbus-1 \
"

# --with-tmpfilesdir=${sysconfdir}/tmpfiles.d is set in the base recipe.
# We cannot change it here, not even with _append/_remove. So instead
# just move the file...
EXTRA_OECONF_append_pn-connman = " --with-dbusconfdir=${datadir} --with-dbusdatadir=${datadir}"
# main.conf contains NetworkInterfaceBlacklist=vmnet,vboxnet,virbr,ifb,ve-
# TODO: move somewhere where it is still used?
STATELESS_ETC_WHITELIST += "connman/main.conf"
STATELESS_MV_pn-connman = " \
    tmpfiles.d=${libdir}/tmpfiles.d \
"

FILES_${PN}_append_pn-connman = " ${datadir}/dbus-1 ${libdir}/tmpfiles.d"

# shadow was patched by Clear Linux such that it uses regular
# /etc but knows about alt-files in /usr/share/defaults/etc
# and works without /etc/login.defs and /etc/default/useradd.
# pam.d is expected to be /usr/share/pam.d.
STATELESS_MV_pn-shadow = " \
    pam.d=${datadir}/pam.d \
    default/useradd \
    login.defs \
"
FILES_${PN}_append_pn-shadow = " ${datadir}/pam.d"

# TODO: makes these components user-configurable again?
# libpam has to be relocated so that it matches the Clear Linux patches
# for shadow.
STATELESS_RELOCATE_pn-libpam = "${datadir}"
# TODO: auditd does not actually start correctly once relocated,
# and it puts its tmpfiles.d/audit-volatile.conf into the wrong place.
#STATELESS_RELOCATE_pn-audit = "True"
#STATELESS_RELOCATE_pn-auditd = "True"
#STATELESS_RELOCATE_pn-audispd-plugins = "True"
STATELESS_ETC_WHITELIST += " \
    audit/* \
    audisp/* \
    default/auditd \
    libaudit.conf \
"
STATELESS_MV_pn-audit = " \
    tmpfiles.d=${libdir}/tmpfiles.d \
"
FILES_${PN}_append_pn-audit = " ${libdir}/tmpfiles.d"

# atop is dropping files to crond and logrotate dirs,
# so those files are also moved because we are moving
# also logrotate and crond themselves.
STATELESS_MV_pn-atop = " \
    atop \
    tmpfiles.d=${libdir}/tmpfiles.d \
    cron.d=${datadir}/defaults/etc/cron.d \
    logrotate.d=${datadir}/defaults/etc/logrotate.d \
"

FILES_${PN}_append_pn-atop = " \
    ${libdir}/tmpfiles.d \
    ${datadir}/defaults/etc/cron.d \
    ${datadir}/defaults/etc/logrotate.d \
"

# Move logrotate out of etc and modify the hard
# coded path in logrotate.conf
STATELESS_RELOCATE_pn-logrotate = "${datadir}/defaults/etc"
do_install_append_pn-logrotate() {
    sed -i -e 's,^.*include.*,include ${sysconfdir}/logrotate.d,g' ${D}${sysconfdir}/logrotate.conf
}

# Move crond out of etc and modify the hard
# coded path in crond.service. Had to use workdir
# because cronie recipe has already install_append and
# stateless.inc seems to be running before that (so the
# file is not yet in systemd dir)
STATELESS_RELOCATE_pn-cronie = "${datadir}/defaults/etc"
do_install_append_pn-cronie() {
    sed -i -e 's,^.*Environment.*,EnvironmentFile=${sysconfdir}/sysconfig/crond,g' ${WORKDIR}/crond.service
}

# Move v86d (only module in qemu build). Systemd is
# trying to read the module conf from many places,
# one of them is libdir. These outside kernel compiled
# modules should work with just moving, inside kernel
# modules are split only after compile to move doesn't
# directly work in those (couple of those present in x86).
# modules-load.d dir itself is created in many recipes like
# systemd and kernel and it is not trivial to remove it.
# stateless.inc should however remove it when etc is otherwise
# empty.
STATELESS_MV_pn-v86d = "modules-load.d=${libdir}/modules-load.d"
FILES_${PN}_append_pn-v86d = " ${libdir}/modules-load.d"

# Locally managed by systemd.
STATELESS_ETC_WHITELIST += "machine-id"

# Irrelevant at the moment.
STATELESS_ETC_WHITELIST += "X11/*"

# Not used. TODO: remove instead.
STATELESS_ETC_WHITELIST += "default/volatiles/*"

# To be fixed later.
STATELESS_ETC_WHITELIST += " \
    bash_completion.d/* \
    bash_completion \
    profile.d/* \
"

STATELESS_MV_pn-systemd-watchdog = " \
   systemd=${base_libdir}/systemd \
"
FILES_${PN}_append_pn-systemd-watchdog = " ${base_libdir}/systemd"

# Relevant for systemd configuration installed during postinst.
STATELESS_MV_ROOTFS += " \
    systemd=${libdir}/systemd \
"

# Who needs a list of installed shells?
STATELESS_RM_ROOTFS += " \
    shells \
"

# TODO: A compiled file (?!). Move under /var?
STATELESS_ETC_WHITELIST += " \
   udev/hwdb.bin \
"

# TODO: /etc/motd still exists, but isn't used anymore?

# initramfs is by design read-only and thus does not have to be stateless.
STATELESS_PN_WHITELIST += "ostro-initramfs"

# Install nss-altfiles and activate it in ${datadir}/defaults/etc/nsswitch.conf.
CORE_IMAGE_EXTRA_INSTALL += "${@bb.utils.contains('STATELESS_PN_WHITELIST', '${PN}', '', 'nss-altfiles', d)}"
ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('STATELESS_PN_WHITELIST', '${PN}', '', 'stateless_activate_altfiles;', d)}"

stateless_activate_altfiles () {
    # Compared to OE-core, this replaces "compat" with "files altfiles",
    # and adds "altfiles" as fallback elsewhere.
    # "netgroup: nis" got removed without replacement.
    cat >${IMAGE_ROOTFS}${datadir}/defaults/etc/nsswitch.conf <<EOF
passwd:         files altfiles
group:          files altfiles
shadow:         files altfiles

hosts:          files altfiles dns
networks:       files altfiles

protocols:      db files altfiles
services:       db files altfiles
ethers:         db files altfiles
rpc:            db files altfiles
EOF
}

STATELESS_ALTFILES = " \
    group \
    hosts \
    passwd \
    protocols \
    rpc \
    services \
    shadow \
"

STATELESS_MV_ROOTFS += " \
    ${@ ' '.join('%s=${datadir}/defaults/etc/%s' % (x,x) for x in d.getVar('STATELESS_ALTFILES', True).split())} \
"

STATELESS_RM_ROOTFS += " \
    ${@ ' '.join(x + '-' for x in d.getVar('STATELESS_ALTFILES', True).split())} \
"

# TODO: is this really used?
STATELESS_ETC_WHITELIST += " \
    gshadow \
    gshadow- \
"
