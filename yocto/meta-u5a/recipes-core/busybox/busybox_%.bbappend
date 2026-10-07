# u5a-init needs devmem for the inherited usb0 NCM register write (E20-E26).
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:u5a = " file://u5a-devmem.cfg"
