# pseudo does not handle xattrs correctly for hardlinks:
# https://bugzilla.yoctoproject.org/show_bug.cgi?id=9317
#
# This started to become a problem when copying rootfs
# content around for swupd bundle creation. As a workaround,
# we avoid having hardlinks in the rootfs and replace them
# with symlinks.

do_install_append_class-target () {
    set -x
    for target in e2fsck mke2fs tune2fs; do
        inode=$(ls -1 -i ${D}/${base_sbindir}/$target | cut -d ' ' -f1)
        ls -1 -i ${D}/${base_sbindir} | grep -w -e "^$inode" | cut -d ' ' -f2 | while read linkname; do
            if [ "$target" != "$linkname" ]; then
               ln -sf $target ${D}/${base_sbindir}/$linkname
            fi
        done
    done
}