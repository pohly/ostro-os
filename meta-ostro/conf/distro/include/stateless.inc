INHERIT += "stateless"

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
"

# /etc/fstab is required because without it, / remains read-only.
STATELESS_ETC_WHITELIST += "fstab"

# TODO: systemd must be patched to load Smack rules also from elsewhere
# than /etc/smack.
STATELESS_ETC_WHITELIST += "smack/*"

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

# TODO: /etc/ssl - populated by ca-certificates and used by gnutls, openssl, etc.
# If nothing really needs the combined /etc/ssl/ca-certificates.crt, perhaps
# we can replaced "trusted certificates are those in /etc/ssl" with
# "everything in /usr/share/ca-certificates", like Clear Linux does it?
#
# But then how can the local admin remove or replace certificates?
# Perhaps keep update-ca-certificates, but patch the system so that generated
# files are ephemeral (/run/ssl) and get populated on each boot?
# /etc/ca-certificates.conf has to be come optional, i.e. if not present,
# use everything under /usr/share/ca-certificates.
#
#EXTRA_OECONF_append_pn-gnutls = "${@bb.utils.contains('DISTRO_FEATURES', 'stateless', \
#  '--with-default-trust-store-file=${sysconfdir}/ssl/cert.pem --with-default-trust-store-dir=${datadir}/ca-certificates', \
#  '', d)}"
#STATELESS_RM_pn-ca-certificates = " \
#    ca-certificates.conf \
#"
STATELESS_ETC_WHITELIST += "ca-certificates.conf"
STATELESS_ETC_DIR_WHITELIST += "ssl/*"

STATELESS_RM_pn-tzdata = " \
    timezone \
    localtime \
"

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
