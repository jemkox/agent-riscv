#!/bin/sh
# L7 rootfs slimming for the 64 MB rv32cpu linux_sim machine.
# The Sv32 kernel here boots with an initramfs only; the 6.12.27 loadable
# module tree (~16 MB) is never used and does not fit the 64 MB window.
set -e
T="$1"
[ -d "$T" ] || exit 0
rm -rf "${T}/lib/modules" "${T}/usr/lib/modules" "${T}/modules" 2>/dev/null || true
rm -rf "${T}/etc/udev" "${T}/usr/share/zoneinfo" "${T}/etc/ppp" 2>/dev/null || true
rm -f "${T}/etc/init.d/S40network" 2>/dev/null || true
exit 0
