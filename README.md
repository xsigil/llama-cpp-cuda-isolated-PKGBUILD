# llama-cpp-cuda-isolated

Stateless, ephemeral, and fully reproducible deployment architecture for `llama.cpp` using native Linux primitives (`tmpfs`, `unshare`, `chroot`) managed under Arch Linux `PKGBUILD`.

## Architecture Overview

```text
[ Host OS Storage ]
  └─ /srv/llama/models/model.gguf (Read-Only)
           │
           │ (mount --bind -o ro)
           ▼
[ Stateless RAM Jail (/run/llama-jail - tmpfs) ]
  ├── /models/model.gguf
  ├── Minimal Read-Only VFS (/usr, /lib64, /dev, /proc)
  └── [ llama-server ] (unshare: PID, IPC, UTS, Mount)
           │
           └─ Bound strictly to 127.0.0.1:8080 (No Host Bleed)
```

* **Stateless Execution**: The root filesystem is mounted as a dedicated `tmpfs` under `/run/llama-jail`. When the service terminates, the entire execution environment dissolves from memory.
* **Zero-Copy Model Isolation**: Models reside on host storage and are projected into the jail via read-only bind mounts, preventing tampering, duplication, and write exhaustion.
* **Complete Decoupling**: Inference processes have zero visibility into `/home`, `/root`, or host storage trees.

## Requirements

* Arch Linux
* NVIDIA GPU with CUDA Toolkit installed
* Base development tools (`base-devel`, `cmake`)

## Installation & Deployment

### 1. Clone the repository
```bash
git clone https://github.com/xsigil/llama-cpp-cuda-isolated-PKGBUILD.git
cd llama-cpp-cuda-isolated-PKGBUILD
```

### 2. Build and install package
```bash
makepkg -sric
```

## Model Setup

This daemonless stateless jail expects models to reside in `/srv/llama/models/model.gguf`.

### Downloading from Hugging Face

Set your Hugging Face Access Token (`HF_TOKEN`) and download your target GGUF model using `wget -c` (resumable):

```bash
# 1. Create model repository directory
sudo mkdir -p /srv/llama/models

# 2. Download model directly via Hugging Face API
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export MODEL_URL="https://huggingface.co/<org>/<model-repo>/resolve/main/<model-file>.gguf"

sudo wget -c \
    --header="Authorization: Bearer ${HF_TOKEN}" \
    "${MODEL_URL}" \
    -O /srv/llama/models/model.gguf

# 3. Set strict read permissions for the jail user
sudo chown -R llamacpp:llamacpp /srv/llama/models
sudo chmod 644 /srv/llama/models/model.gguf
```

## Configuration & Management

Modify `/etc/conf.d/llama-isolated` to customize thread counts, context limits, or host bind points.

### Reload and start the daemon
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now llama-cpp.service
```

### Verify inference service
```bash
curl http://127.0.0.1:8080/v1/models
```

For security architecture and threat modeling details, see [DESIGN.md](DESIGN.md).