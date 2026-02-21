pkgname="barbarian"
pkgver="1.0.1"
pkgrel="1"
pkgdesc="Simple wayland status bar"
arch=("x86_64")
depends=("wayland")
makedepends=("odin" "git")
url="https://github.com/xb-bx/barbarian"
source=("git+$url")
md5sums=("SKIP")

build() {
    cd $pkgname
    git submodule update --force --init --recursive
    make release
}
package() {
    cd $pkgname
    DESTDIR="${pkgdir}/" make install
}

