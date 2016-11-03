import oe.path


def copyxattrtree(src, dst):
    """
    Copy all of the files in src to dst preserving extended attributes

    src -- the source to copy from
    dst -- the destination to copy to
    """
    import subprocess
    cmd = "tar --xattrs --xattrs-include='*' -cf - -C %s -p . | tar -p --xattrs --xattrs-include='*' -xf - -C %s" % (src, dst)
    subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)


def copyxattrfiles(d, filelist, src, dst, archive=False):
    """
    copy files preserving extended attributes

    d -- the bitbake data store
    filelist -- a list of file paths
    src -- where to copy the files from
    dst -- where to copy the files to
    archive -- create archive at dst instead of writing into that directory
    """
    import subprocess
    import tempfile

    bb.utils.mkdirhier(os.path.dirname(dst) if archive else dst)
    files = sorted(filelist)

    workdir = d.getVar('WORKDIR', True)
    fd, copyfile = tempfile.mkstemp(dir=workdir)
    os.close(fd)
    with open(copyfile, 'w') as fdest:
        fdest.write('-C%s\n' % src)
        for f in files:
            fdest.write('%s\n' % f)

    if archive:
        cmd = "tar --xattrs --xattrs-include='*' --no-recursion -zcf %s -T %s -p" % (dst, copyfile)
    else:
        cmd = "tar --xattrs --xattrs-include='*' --no-recursion -cf - -T %s -p | tar -p --xattrs --xattrs-include='*' -xf - -C %s" % (copyfile, dst)
    subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
    output = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
    if output:
        bb.fatal('Unexpected output from the following command:\n%s\n%s' % (cmd, output))
    os.remove(copyfile)


def remove_empty_directories(tree):
    """
    remove any empty sub-directories of the passed path

    tree -- the root of the tree whose empty children should be deleted
    """
    for dir, _, _ in os.walk(tree, topdown=False):
        try:
            os.rmdir(dir)
        except OSError as err:
            bb.debug(4, 'Not removing %s (it is probably not empty): %s' % (dir, err.strerror))
