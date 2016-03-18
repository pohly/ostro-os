.. _Building Images:

Building Ostro |trade| OS Images
################################

This technical note describes the basic instructions for building an Ostro |trade| OS image
from source using the Yocto Project tools.  You should already be familiar with these Yocto
Project tools, as explained in the `Yocto Project Quick Start Guide`_. 

.. _`Yocto Project Quick Start Guide`: http://www.yoctoproject.org/docs/current/yocto-project-qs/yocto-project-qs.html

Initial Steps
=============

1. Check out the ``ostro-os`` repository from the ``ostroproject`` GitHub area.  This will retrieve the Ostro OS source code
   and necessary Yocto Project tools and configuration files. The Ostro OS code is a combination of
   several different components in a single repository.  (See the README in the cloned copy you just made 
   for up-to-date details on what’s included.)
2. In the repository, run :command:`source oe-init-build-env` to setup the Yocto Project build environment.
3. Update the :file:`conf/local.conf` configuration file (more details about this in the sections below)
4. Generate an Ostro OS image using :command:`bitbake ostro-image` (additional build target options are explained
   in the sections below.)
5. Install and boot as described in the :ref:`booting-and-installation` tech note.

Depending on your development machine’s performance, building an image from source 
(the :command:`bitbake ostro-image` command) may take a few hours to complete the first time. 
It will download and compile all 
the source code needed to create the binary image, including the Linux kernel, 
compiler tools, upstream components and Ostro OS-specific patches.  (If you haven't 
done so yet, this might be a good time to read through 
the `Yocto Project Quick Start Guide`_.)

When the build process completes, the generated image will be in the folder 
:file:`build/tmp-glibc/deploy/images/$(MACHINE)`
       
If errors occur during the build, refer to the `Yocto Project Errors and Warnings`_ documentation to help 
resolve the issues and repeat the :command:`bitbake ostro-image` command to continue.

.. _`Yocto Project Errors and Warnings`: http://www.yoctoproject.org/docs/current/mega-manual/mega-manual.html#ref-qa-checks

Image Configuration
===================

Building images depends on choosing the private keys that are needed
during the build process. One either has to generate and configure
these keys or disable the features which depend on them.

In addition, images are locked down by default: for example, none of
the existing user accounts (including root) has a password set, so
logging into the running system is impossible. Before building an image,
you must choose a way of interacting with the system after it has booted.


Target MACHINE Architecture
----------------------------

The build's default target architecture ``MACHINE`` is ``intel-corei7-64``, 
as configured in :file:`build/conf/local.conf`. 
You can edit the :file:`local.conf` file to change this to a different machine appropriate for your platform. 

For currently :ref:`platforms`, the appropriate ``MACHINE`` selections are:

.. table:: Yocto MACHINE selection for Supported Hardware platforms

    ==========================  ====================================
    Platform                    Yocto Project MACHINE selection
    ==========================  ====================================
    GigaByte GB-BXBT-3825       intel-corei7-64
    Intel Galileo Gen2          intel-quark
    MinnowBoard MAX compatible  intel-corei7-64
    Intel Edison                edison
    BeagleBone Black            beaglebone
    ==========================  ====================================

Virtual machine images (a :file:`.vdi` file) are created for each of these builds hardware platforms as part 
of the build process (and included in the prebuilt image folders too).

Base Images
-----------

``ostro-image.bb`` is the image recipe used by the Ostro
project. It uses image features (configured via ``IMAGE_FEATURES``) to
control the content and the image configuration.

This image recipe can be used in two modes, depending on the ``swupd`` image feature:

* swupd active: produces a swupd update stream when building ``ostro-image`` and in
  addition defines virtual image recipes which produce image files that are
  compatible with that update stream.
* swupd not active: this is the traditional way of building images, where
  variables directly control what goes into the image.

Developers are encouraged to start building images the traditional
way without swupd and therefore swupd is off by default, because:

a) swupd support is still new and may have unexpected problems.
b) image and swupd bundle creation cause additional overhead
   due to the extra work that needs to be done.

The following instructions assume that swupd is not used.

.. TODO: document how to configure swupd once it is better understood
   and tested.

.. TODO: create a simple way for developers to build different images
   with different configuration and content in the same build
   configuration and document it. Probably need to move all of
   ostro-image.bb into a ostro-image.bbclass and thus make it possible
   to write a my-ostro-image.bb which just inherits
   ostro-image.bbclass and the modifies it.


Image Formats for EFI platforms
-------------------------------

Note: The following chapter is applicable only to EFI platforms.

It is possible to produce different types of images:

.dsk:
    The basic format, which can be written to a block device with "dd".

.dsk.vdi:
    VirtualBox format, for running OSTRO inside a Virtual Machine.

compressed formats:
    Same as above, only compressed, to reduce (final) space occupation
    and speed up the transfer between systems of the Ostro OS image.
    Notice that the creation of compressed images will require additional
    temporary space, because the creation of the compressed image depends
    on the presence of the uncompressed one.

    All compression methods listed for ``COMPRESSIONTYPES`` in
    ``meta/classes/image_types.bbclass`` are supported. In addition,
    Ostro OS adds support for compressing with :command:`zip`. ``xz``
    is recommended, while ``zip`` may be useful in cases where images
    have to be decompressed on machines that do not have :command:`xz`
    readily available.

To customize the image format, modify ``local.conf``, adding the variable
``OSTRO_VM_IMAGE_TYPES``, set to any combination of the following::

    dsk dsk.xz dsk.vdi dsk.vdi.xz

It will also trigger the creation of corresponding symlinks.

Example::

    OSTRO_VM_IMAGE_TYPES = "dsk.xz dsk.vdi.xz"

will create both the raw and the VirtualBox images, both compressed.



Development Images
------------------

All images provided by the Ostro Project are targetting
developers. Because the project wants to avoid having developers
accidentally build images for real products that have development
features enabled, explicit changes in ``local.conf`` are needed to
enable them.

Developers building their own images for personal use can follow these
instructions to replicate the configuration of the published Ostro OS images. All necessary
private keys are provided in the ``ostro-os`` repository.

To do this, before building,  edit the :file:`conf/local.conf` configuration file, 
find the line
with ``# require conf/distro/include/ostro-os-development.inc`` and
uncomment it.

Because the uncustomized ``ostro-image`` does not even provide a way
to log in, including ``ostro-os-development.inc`` will also extend the
package selection such that the content matches what gets published as
the ``ostro-image-reference``. For example, an ssh server gets added.
If that is not desired, uncomment the lines with::

  OSTRO_DEVELOPMENT_EXTRA_FEATURES = ""
  OSTRO_DEVELOPMENT_EXTRA_INSTALL = ""


Accelerating Build Time Using Shared-State Files Cache
------------------------------------------------------

As explained in the `Yocto Project Shared State Cache documentation`_, by design
the build system builds everything from scratch unless it can determine that
parts do not need to be rebuilt. The Yocto Project shared state code supports
incremental builds and attempts to accelerate build time through the use
of prebuilt data cache objects configured with the ``SSTATE_MIRRORS`` setting.

By default, this ``SSTATE_MIRRORS`` configuration is disabled in :file:`conf/local.conf`
but can be easily enabled by uncommenting the ``SSTATE_MIRRORS`` line
in your :file:`conf/local.conf` file, as shown here:::

   # Example for Ostro OS setup, recommended to use it:
   #SSTATE_MIRRORS ?= "file://.* http://download.ostroproject.org/sstate/ostro-os/PATH"

 

.. _Yocto Project Shared State Cache documentation: http://www.yoctoproject.org/docs/2.0/mega-manual/mega-manual.html#shared-state-cache

Production Images
-----------------

When building production images, first follow the instructions
provided in :file:`meta-intel-iot-security/meta-integrity/README.md` for creating your own
keys. Then edit the :file:`conf/local.conf` configuration file and
set ``IMA_EVM_KEY_DIR`` to the directory containing
these keys or set the individual variables for each required
key (see ``ima-evm-rootfs.bbclass``).

In addition, find the line
with ``# require conf/distro/include/ostro-os-production.inc`` and
uncomment it. This documents that the intention really is to build
production images and disables a sanity check that would otherwise
abort a build.

Then add your custom applications and services by listing them as
additional packages as described in the next section.


Installing Additional Packages
------------------------------

Extend ``OSTRO_IMAGE_EXTRA_INSTALL`` to install additional packages
into all Ostro OS image variants, for example with::

    OSTRO_IMAGE_EXTRA_INSTALL += "strace"

Alternatively, ``CORE_IMAGE_EXTRA_INSTALL`` can also be used. The
difference is that this will also affect the initramfs images, which is
often not intended.
