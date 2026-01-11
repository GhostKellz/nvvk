# Maintainer: GhostKellz <ghost@ghostkellz.sh>
pkgname=nvvk
pkgver=1.0.0
pkgrel=1
pkgdesc="NVIDIA Vulkan Extensions Wrapper - VK_NV_low_latency2 and diagnostics"
arch=('x86_64')
url="https://github.com/ghostkellz/nvvk"
license=('MIT')
depends=('glibc' 'vulkan-icd-loader')
makedepends=('zig>=0.14' 'vulkan-headers')
provides=('libnvvk.so')
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    zig build -Doptimize=ReleaseFast -Dlinkage=dynamic
}

package() {
    cd "$pkgname-$pkgver"

    # CLI binary
    install -Dm755 zig-out/bin/nvvk-cli "$pkgdir/usr/bin/nvvk-cli"

    # Shared library for FFI
    install -Dm755 zig-out/lib/libnvvk.so "$pkgdir/usr/lib/libnvvk.so"

    # C headers for development
    install -Dm644 include/nvvk.h "$pkgdir/usr/include/nvvk.h"
    install -Dm644 include/nvvk_low_latency.h "$pkgdir/usr/include/nvvk_low_latency.h"
    install -Dm644 include/nvvk_diagnostics.h "$pkgdir/usr/include/nvvk_diagnostics.h"

    # Documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
