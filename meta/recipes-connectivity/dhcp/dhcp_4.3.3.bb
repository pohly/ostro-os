require dhcp.inc

SRC_URI += "file://dhcp-3.0.3-dhclient-dbus.patch;striplevel=0 \
            file://fix-external-bind.patch \
            file://link-with-lcrypto.patch \
            file://fixsepbuild.patch \
            file://dhclient-script-drop-resolv.conf.dhclient.patch \
            file://replace-ifconfig-route.patch \
           "

SRC_URI[md5sum] = "c5577b09c9017cdd319a11ff6364268e"
SRC_URI[sha256sum] = "553c4945b09b1c1b904c4780f34f72aaefa2fc8c6556715de0bc9d4e3d255ede"
