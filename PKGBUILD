pkgname=llama-cpp-cuda-isolated
pkgver=1.0.0
pkgrel=1
pkgdesc="Stateless RAM-jailed llama.cpp server with CUDA acceleration and unshare/chroot isolation"
arch=('x86_64')
url="https://github.com/ggerganov/llama.cpp"
license=('MIT')
depends=('cuda' 'gcc-libs' 'glibc')
makedepends=('cmake' 'git' 'wget')
backup=('etc/conf.d/llama-isolated')
source=(
    "git+https://github.com/ggerganov/llama.cpp.git"
    "run_server.sh"
    "llama-cpp.service"
    "llama-isolated.conf"
)
sha256sums=(
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
)

# 任意の GGUF URL を指定（認証が必要な場合は環境変数 HF_TOKEN を利用可能）
_model_url="${MODEL_DOWNLOAD_URL:-https://huggingface.co/google/gemma-4-31b-it-GGUF/resolve/main/gemma-4-31b-it-Q4_K_M.gguf}"
_model_filename="model.gguf"

prepare() {
    cd "$srcdir"
    
    if [[ ! -f "${_model_filename}" ]]; then
        msg2 "Fetching model GGUF via resilient HTTP stream..."
        local auth_header=()
        if [[ -n "${HF_TOKEN:-}" ]]; then
            auth_header=(--header="Authorization: Bearer ${HF_TOKEN}")
        fi

        wget -c \
            --tries=0 \
            --retry-connrefused \
            --waitretry=5 \
            --read-timeout=30 \
            --timeout=15 \
            "${auth_header[@]}" \
            -O "${_model_filename}" \
            "${_model_url}"
    fi
}

build() {
    cd "$srcdir/llama.cpp"
    cmake -B build \
        -DGGML_CUDA=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build --config Release -j$(nproc)
}

package() {
    cd "$srcdir/llama.cpp"
    DESTDIR="$pkgdir" cmake --install build

    # 1. 隔離実行用スクリプトの配置
    install -d -m 0755 "$pkgdir/usr/lib/llama-cpp-isolated"
    install -m 0755 "$srcdir/run_server.sh" "$pkgdir/usr/lib/llama-cpp-isolated/run_server.sh"

    # 2. 設定ファイルの配置
    install -d -m 0755 "$pkgdir/etc/conf.d"
    install -m 0644 "$srcdir/llama-isolated.conf" "$pkgdir/etc/conf.d/llama-isolated"

    # 3. モデル格納ディレクトリの準備
    install -d -m 0755 "$pkgdir/srv/llama/models"
    install -m 0644 "$srcdir/${_model_filename}" "$pkgdir/srv/llama/models/${_model_filename}"

    # 4. systemd サービスの配置
    install -d -m 0755 "$pkgdir/usr/lib/systemd/system"
    install -m 0644 "$srcdir/llama-cpp.service" "$pkgdir/usr/lib/systemd/system/llama-cpp.service"
}
