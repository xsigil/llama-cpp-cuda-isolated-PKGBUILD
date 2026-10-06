#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="/etc/conf.d/llama-isolated"
if [[ -f "${CONF_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONF_FILE}"
else
    echo "[-] Configuration file ${CONF_FILE} not found." >&2
    exit 1
fi

JAIL_DIR="${JAIL_ROOT:-/run/llama-jail}"
RUN_USER="llamacpp"
RUN_GROUP="llamacpp"

# ホストのCUDAライブラリパスを自動検出
CUDA_LIB_DIR=""
for candidate in \
    "/opt/cuda/targets/x86_64-linux/lib" \
    "/opt/cuda/lib64" \
    "/usr/local/cuda/lib64"; do
    if [[ -d "$candidate" ]]; then
        CUDA_LIB_DIR="$candidate"
        break
    fi
done

cleanup() {
    echo "[*] Tearing down isolated environment..."
    umount -l "${JAIL_DIR}/models" 2>/dev/null || true
    umount -l "${JAIL_DIR}/opt"    2>/dev/null || true
    umount -l "${JAIL_DIR}/dev"    2>/dev/null || true
    umount -l "${JAIL_DIR}/proc"   2>/dev/null || true
    umount -l "${JAIL_DIR}/sys"    2>/dev/null || true
    umount -l "${JAIL_DIR}/usr"    2>/dev/null || true
    umount -l "${JAIL_DIR}/lib64"  2>/dev/null || true
    umount -l "${JAIL_DIR}/lib"    2>/dev/null || true
    umount -l "${JAIL_DIR}"        2>/dev/null || true
    rm -rf "${JAIL_DIR}"
}
trap cleanup EXIT INT TERM

# 1. tmpfs マウント（RAM上に隔離ルートを生成）
mkdir -p "${JAIL_DIR}"
mount -t tmpfs -o "size=${JAIL_TMPFS_SIZE:-512M},mode=0755" tmpfs "${JAIL_DIR}"

# 2. 隔離ツリーの作成
mkdir -p "${JAIL_DIR}"/{dev,proc,sys,etc,usr,lib,lib64,tmp,models,opt}

# 3. 必要なツリーを Read-Only / 仮想マウント
mount --bind -o ro /usr "${JAIL_DIR}/usr"
mount --bind -o ro /lib "${JAIL_DIR}/lib"
[[ -d /lib64 ]] && mount --bind -o ro /lib64 "${JAIL_DIR}/lib64"
[[ -d /opt ]] && mount --bind -o ro /opt "${JAIL_DIR}/opt"
mount --bind /dev "${JAIL_DIR}/dev"
mount -t proc proc "${JAIL_DIR}/proc"
mount -t sysfs sysfs "${JAIL_DIR}/sys"

# 認証・DNS・リンカーキャッシュの投影
[[ -f /etc/ld.so.cache ]] && cp -a /etc/ld.so.cache "${JAIL_DIR}/etc/"
[[ -d /etc/ld.so.conf.d ]] && cp -a /etc/ld.so.conf* "${JAIL_DIR}/etc/"
cp -a /etc/passwd /etc/group /etc/resolv.conf "${JAIL_DIR}/etc/"

# モデル格納パスの読み取り専用マウント
mount --bind -o ro "${LLAMA_MODEL_DIR}" "${JAIL_DIR}/models"

# 4. unshare による名前空間隔離と chroot 実行
echo "[*] Launching llama-server inside stateless jail..."
EXEC_LD_PATH="/usr/lib/llama-cpp-isolated:/usr/lib:/usr/local/lib"
[[ -n "${CUDA_LIB_DIR}" ]] && EXEC_LD_PATH="${CUDA_LIB_DIR}:${EXEC_LD_PATH}"

exec unshare -m -p -i -u --fork \
    chroot --userspec="${RUN_USER}:${RUN_GROUP}" "${JAIL_DIR}" \
    /usr/bin/env LD_LIBRARY_PATH="${EXEC_LD_PATH}" \
    /usr/bin/llama-server \
        -m "/models/${LLAMA_MODEL_FILE}" \
        --host "${LLAMA_HOST}" \
        --port "${LLAMA_PORT}" \
        -c "${LLAMA_CTX_SIZE}" \
        -ngl "${LLAMA_N_GPU_LAYERS}" \
        --threads "${LLAMA_THREADS}"
