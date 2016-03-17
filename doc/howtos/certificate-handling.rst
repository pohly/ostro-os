.. _certificate-handling:

Certificate Handling in the Ostro |trade| OS
############################################

This document explains how certificates and secret keys are managed in
the Ostro |trade| OS.


SSL certificates
================

SSL certificates are used by libraries like openssl or gnutls and thus
by higher-level libraries and tools like libsoup, libcurl, curl, and wget
to verify the authenticity of their peer when connecting to a remote
server. node.js uses openssl and thus also uses the system
certificates.

Ostro OS uses the ``ca-certificates`` package from OpenEmbedded, which
in turn takes it from Debian. This package contains a set SSL CA
certificates (maintained by the Mozilla Foundation, with a few
modifications applied by Debian) and the ``update-ca-certificates``
tool for managing the actual set of certificates that are used by
the system.

Certificates are installed in ``/usr/share/ca-certificates`` (provided
by the OS) or ``/etc/ca-certificates/certs`` (added by a local
administrator). However, applications and libraries are configured to
use a combined ``/var/ssl/certs/ca-certificates.crt`` or the
certificates linked to in ``/var/ssl/certs``. This represents the set
of certificates which are considered as trusted.

``update-ca-certificates`` is used to generate the content of
``/var/ssl/certs``. In Ostro, the default is to trust all installed
certificates. The optional ``/etc/ca-certificates.conf`` can be used to
exclude certificates that otherwise would be trusted, like this ::

   !mozilla/foobar.crt


Managing custom SSL certificates
--------------------------------

You should package new ``.crt`` files so they get installed under
``/usr/share/ca-certificates``, depend on ca-certificates, and
call ``update-ca-certificates`` in postinst and postrm scripts. Adding
or removing that package then will update the system SSL certificates
accordingly. Because the Ostro OS does not support individual packages in
installed images, this must be done when preparing the next revision
of an image.

Alternatively, certificates can also be modified directly without
packaging them, if the process manipulating
``/etc/ca-certificates/certs`` and calling
``update-ca-certificates`` has write access to that directory and
``/var/ssl/certs``.

Removing system SSL certificates
--------------------------------

In a ``ca-certificates_%.bbappend`` configuration file, you can extend
``do_install()`` to remove certificates from
``${D}${datadir}/ca-certificates`` before the ca-certificate package
gets created.


IMA/EVM and image signing
=========================

Linux IMA (Integrity Measurement Architecture) and EVM (Extended Verification Module) 
are technologies which ensure integrity by signing hashes of
file content and file meta data, respectively. There are several keys
involved:

* A root certificate authority: the public part is compiled
  into the Linux kernel itself and is installed on the device
  as part of the kernel.

* A signing key signed by the CA: the public part gets
  installed into ``/etc/keys/x509_evm.der`` of the initramfs at
  initramfs creation time.

The private keys need to be available only when building the Linux
kernel and images.


Creating IMA/EVM keys
---------------------

meta-integrity/README.md contains instructions for creating new
keys. As a default, that layer also provides keys which are known to
anyone and thus should not be used in production.

Updating IMA/EVM keys
---------------------

Updating keys is only possible as part of a complete image update because the
keys are not packaged. Updating the public keys
requires re-signing files with private keys, which are not available
on the device.

Updating keys in a running system is problematic: if IMA is active,
replacing core system components (like libc) with files that the
currently running kernel does not trust is going to make the
replacement libc unusable.
