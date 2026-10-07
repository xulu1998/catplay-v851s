#!/bin/sh
# Prepares the CatPlay Yocto workspace for the v851s-rtl8733bs machine. Runs on a Linux build host (an
# aarch64 or x86_64 VM is fine; tested in an aarch64 lima VM with 16 GiB RAM + 8 GiB swap, 100 GiB disk).
# This repository must be visible on the build host at the same path as given here.
# Usage: sh scripts/yocto-setup.sh            (from the repository, on the build host)
# Then:  cd ~/yocto/catplay-firmware && . openembedded-core/oe-init-build-env ~/yocto/build
#        bitbake u5a-e28-image
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
Y=$HOME/yocto/catplay-firmware
B=$HOME/yocto/build
FW_REV=bd33f3286a7b      # catplay-firmware (Yocto 6.0.2 "wrynose" + meta-catplay)
CATPLAY_REV=dbb3ebbcde8a # catplay

if [ ! -d "$Y/openembedded-core/meta" ]; then
  git clone -q https://github.com/catplay-labs/catplay-firmware.git "$Y"
  git -C "$Y" checkout -q "$FW_REV"
  git -C "$Y" submodule update --init --recursive
fi

# catplay source bundle, same as upstream CI (meta-catplay/scripts/create-src-bundle.sh)
rm -rf "$HOME/yocto/catplay-src"
git clone -q https://github.com/catplay-labs/catplay.git "$HOME/yocto/catplay-src"
git -C "$HOME/yocto/catplay-src" checkout -q "$CATPLAY_REV"
bash "$Y/meta-catplay/scripts/create-src-bundle.sh" "$HOME/yocto/catplay-src"

mkdir -p "$B/conf"
sed "s|@U5A_REPO@|$REPO|" "$REPO/yocto/build-conf/bblayers.conf" > "$B/conf/bblayers.conf"
cp "$REPO/yocto/build-conf/local.conf" "$B/conf/local.conf"
echo "ready: cd $Y && . openembedded-core/oe-init-build-env $B && bitbake u5a-e28-image"
