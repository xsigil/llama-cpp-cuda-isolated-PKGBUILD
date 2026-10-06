# Maintainer: MASAHIRO SUGAYA <parorafia@xsigil.dev>
pkgname=llama-cpp-cuda-isolated
pkgver=b3800
pkgrel=1
pkgdesc="Stateless, hardware-accelerated local LLM inference server inside volatile RAM jail"
arch=('x86_64')
url="https://github.com/ggml-org/llama.cpp"
license=('MIT')
depends=('cuda' 'util-linux' 'systemd')
makedepends=('git' 'cmake')
backup=('etc/conf.d/llama-isolated')
install=llama-cpp.install
source=(
    "git+https://github.com/ggml-org/llama.cpp.git"
    'run_server.sh'
    'llama-cpp.service'
    'llama-isolated.conf'
    'llama-user.conf'
)
sha256sums=(
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
)

build() {
    cd "${srcdir}/llama.cpp"
    cmake -B build \
        -DGGML_CUDA=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_SERVER=ON
    cmake --build build --config Release -j"$(nproc)" --target llama-server
}

package() {
    cd "${srcdir}/llama.cpp"

    # 1. 実行バイナリ
    install -Dm755 build/bin/llama-server "${pkgdir}/usr/bin/llama-server"

    # 2. 共有ライブラリ (.so) を専用ディレクトリに隔離配置（whisper-cpp 等との衝突を防止）
    install -d "${pkgdir}/usr/lib/llama-cpp-isolated"
    find build/bin build -maxdepth 2 -name "*.so*" -exec cp -d {} "${pkgdir}/usr/lib/llama-cpp-isolated/" \;
    find "${pkgdir}/usr/lib/llama-cpp-isolated" -type f -name "*.so*" -exec chmod 755 {} +

    # 3. 隔離ランナー・systemdユニット・設定ファイル・sysusers定義
    install -Dm755 "${srcdir}/run_server.sh" "${pkgdir}/usr/lib/llama-cpp-isolated/run_server.sh"
    install -Dm644 "${srcdir}/llama-cpp.service" "${pkgdir}/usr/lib/systemd/system/llama-cpp.service"
    install -Dm644 "${srcdir}/llama-isolated.conf" "${pkgdir}/etc/conf.d/llama-isolated"
    install -Dm644 "${srcdir}/llama-user.conf" "${pkgdir}/usr/lib/sysusers.d/llama-cpp.conf"
}