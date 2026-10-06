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

# Clone the repository
```bash
git clone [https://github.com/xsigil/llama-cpp-cuda-isolated-PKGBUILD.git](https://github.com/xsigil/llama-cpp-cuda-isolated-PKGBUILD.git)
cd llama-cpp-cuda-isolated-PKGBUILD
```
# (Optional) Export Hugging Face token for gated models
```
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxx"
```
# Build package and install dependencies
```
makepkg -sric

```

## Configuration & Management

Modify `/etc/conf.d/llama-isolated` to customize thread counts, context limits, or host bind points.

# Reload and start the daemon
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now llama-cpp.service
```

# Query inference status
```
curl [http://127.0.0.1:8080/v1/models](http://127.0.0.1:8080/v1/models)
```

