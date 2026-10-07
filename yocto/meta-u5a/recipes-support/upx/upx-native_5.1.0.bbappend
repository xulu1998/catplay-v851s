# The u5a-build VM is aarch64; upstream only fetches the amd64 binary.
SRC_URI:aarch64 = "https://github.com/upx/upx/releases/download/v${PV}/upx-${PV}-arm64_linux.tar.xz;name=arm64"
SRC_URI[arm64.sha256sum] = "222dde34dfa3244a31b06c97820ee651515270e524736f532ac8456783afe76e"
S:aarch64 = "${UNPACKDIR}/upx-${PV}-arm64_linux"
COMPATIBLE_HOST:aarch64 = "aarch64.*-linux"
