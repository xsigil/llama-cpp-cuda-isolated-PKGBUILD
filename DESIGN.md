# Design Architecture & Threat Model: llama-cpp-cuda-isolated

This document outlines the security rationale, design constraints, and operational architecture of running `llama.cpp` inside a stateless RAM (`tmpfs`) jail orchestrated via Linux kernel primitives (`unshare`, `chroot`, bind mounts) and Arch Linux packaging.

---

## 1. Problem Statement: The Local Inference Dilemma

Running Large Language Models (LLMs) locally is driven by the mandate to process sensitive, proprietary, or regulated data without exposing it to third-party APIs. However, the prevailing execution patterns create severe security contradictions:

1. **Privilege Overreach**: Tools like Ollama and generic Docker containers often run as root or require access to the Docker socket, granting daemon-level control over the host.
2. **Persistence & Bleed**: Container runtimes maintain read-write overlays and disk caches. A compromised inference runtime can leave persistent artifacts, backdoors, or exfiltrated embeddings on physical media.
3. **Container Runtime Attack Surface**: A standard container stack comprises a monolithic daemon (`dockerd`/`containerd`), virtual bridge networking, dynamic cgroups management, and layered file systems—introducing tens of thousands of lines of host-privileged code as an exploitation surface.
4. **Data Proximity Risk**: When an LLM runtime shares the host filesystem, prompt injection vulnerabilities (direct or indirect) can escalate to local file disclosure (e.g., accessing `~/.ssh`, GPG keyrings, bash history, or host environment variables).

---

## 2. Architecture Comparison

| Vector | Traditional Container (Docker/Podman) | Native Execution | **llama-cpp-cuda-isolated** |
| --- | --- | --- | --- |
| **Runtime Intermediary** | Daemon (`containerd`, rootless podman) | None | **None** (Kernel primitives only) |
| **Root Filesystem** | Persistent CoW Layer (OverlayFS) | Host root (`/`) | **Ephemeral RAM (`tmpfs`, 512MB)** |
| **Disk Artifacts** | Layer diffs, model cache blobs | Direct writes to host | **Zero** (100% volatile, vanishes on exit) |
| **Model Access** | Copied into volume / mounted host dir | Direct file read/write | **Strictly Read-Only Bind Mount** |
| **Host Namespace Bleed** | Bridge network, port mapping overhead | Full host visibility | **Isolated PID, IPC, UTS, Mount namespaces** |
| **Host Secrets Exposure** | Dependent on volume flags | Complete host read access | **Total Invisibility** (paths unmounted) |
| **Package Lifecycle** | Out-of-tree image registries, Dockerfiles | Manual build / binaries | **Native PKGBUILD (`pacman -S / -R`)** |

---

## 3. Core Security Invariants

### Invariant A: Total Ephemerality (Stateless Execution)

The jail root is mounted on a dedicated RAM-backed `tmpfs` under `/run/llama-jail`.

* The jail exists **only in physical memory**.
* When `llama-cpp.service` terminates, the system executes an automated unmount sequence and wipes the directory tree.
* **Attack Consequence**: Even if an attacker achieves arbitrary code execution (RCE) via a memory safety bug in `llama.cpp` or a malformed tensor exploit, **no persistent hooks, scheduled tasks, or modified binaries can survive a service restart**. Persistence on disk is structurally impossible.

### Invariant B: Zero-Copy, Immutable Model Exposure

Large model weights (e.g., 20GB–70GB GGUF files) are neither duplicated into RAM nor copied into container layers.

* The host directory `/srv/llama/models` is projected into `/run/llama-jail/models` via `mount --bind -o ro`.
* **Attack Consequence**: The compromised inference process cannot overwrite, poison, or tamper with the model weights on disk.

### Invariant C: Blinded VFS (Host Obfuscation)

The inference process does not see the host's `/home`, `/root`, `/var`, `/boot`, or non-essential `/mnt` storage.

* Only `/usr` and `/lib` are projected (read-only) to supply dynamic linking dependencies (glibc, CUDA runtime).
* Only `/dev` is mounted to allow direct IOCTL communication with NVIDIA GPU drivers.
* **Attack Consequence**: Standard directory traversal techniques (e.g., `../../etc/shadow` or scanning `/home/*/.ssh`) immediately terminate at the boundary of the `chroot` jail. To the inference process, the host does not exist.

### Invariant D: Least Privilege Process Dropping

While setting up kernel namespaces and mounts requires `CAP_SYS_ADMIN` (handled by the systemd unit at invocation), the executing binary is demoted immediately before execution:

```bash
unshare -m -p -i -u --fork chroot --userspec="llamacpp:llamacpp" ...

```

* **UID/GID Isolation**: The server runs under an unprivileged system identity (`llamacpp`).
* **Kernel Mitigations**: Inherits systemd limits prohibiting kernel module loading (`ProtectKernelModules=yes`) and control group manipulation (`ProtectControlGroups=yes`).

---

## 4. Execution Topology

```text
[ Physical Host Storage ]
  └── /srv/llama/models/model.gguf  ─── (mount --bind -o ro) ───┐
                                                                │
[ Host Memory / Kernel ]                                        ▼
  └── systemd (root)                                  [ /run/llama-jail (tmpfs) ]
        │                                               ├── /models/model.gguf (RO)
        ▼ fork/exec                                     ├── /usr, /lib64 (RO bind)
     run_server.sh                                      ├── /dev (CUDA nodes)
        │                                               └── /tmp (RAM-only rw)
        ▼                                                       │
     unshare (-m, -p, -i, -u)                                   ▼
        ▼                                              [ llama-server ]
     chroot (userspec="llamacpp:llamacpp")             - User: llamacpp
                                                       - Net: 127.0.0.1:8080
                                                       - Context: Isolated PID 1

```

---

## 5. Threat Model Analysis

### Threat 1: Prompt Injection / RCE via Parsing Bug

* **Vector**: An untrusted prompt causes a buffer overflow in the GGUF parsing logic or token evaluation engine, yielding shell access.
* **Mitigation**: The shell spawns inside the tmpfs chroot as the unprivileged user `llamacpp`. It cannot read host data, write to disk, access external networks beyond loopback, or modify its own libraries. A systemd restart instantly purges all changes.

### Threat 2: Host Secret Exfiltration

* **Vector**: A rogue model extension attempts to read credentials, cloud keys, or bash histories.
* **Mitigation**: `/home`, `/root`, and `/etc/security` are physically absent from the jail namespace. The file read operations fail with `ENOENT` (No such file or directory).

### Threat 3: Model Weight Poisoning

* **Vector**: An internal exploit attempts to alter model tensors to create backdoor trigger words.
* **Mitigation**: The bind mount is enforced as Read-Only (`-o ro`) by the kernel VFS layer. Any write operation fails with `EROFS` (Read-only file system).

### Threat 4: Rogue Network Exfiltration

* **Vector**: Compromised runtime attempts an outbound reverse shell or telemetry transmission.
* **Mitigation**: The daemon binds strictly to `127.0.0.1`. Paired with host-level egress filtering (e.g., `nftables`), the `llamacpp` UID can be completely denied outbound socket allocation (`sk_alloc`).

---

## 6. Security as Code via PKGBUILD

Security infrastructure fails when deployment is fragmented. Packaging this architecture inside an Arch Linux `PKGBUILD` transforms high-assurance sandboxing into an automated, deterministic operation:

1. **Deterministic Verification**: Checksums ensure the underlying source and build configuration match trusted baselines.
2. **FHS Compliance**: Binaries, systemd units, configuration files, and model mount points land in standard Arch filesystem paths without polluting the OS.
3. **Atomic Decommissioning**: Running `pacman -R llama-cpp-cuda-isolated` completely removes the service definitions and isolation wrappers, leaving no orphaned daemons or configuration drift.


### Appendix: Egress Containment via nftables

To physically prevent reverse shell establishment, C2 beaconing, and network-based data exfiltration in the event of process compromise, egress filtering is enforced using kernel-level socket credentials (`meta skuid`).

#### 1. Security Requirements

* **Strict Drop**: Any packet generated by the `llamacpp` system user destined outside the loopback interface (`lo` / `127.0.0.1`) is dropped immediately by the netfilter engine.
* **External Interface Isolation**: Outbound traffic traversing external physical or virtual interfaces (`eth0`, `wlan0`, `tailscale0`, etc.), DNS queries (port 53), and ICMP are completely blocked.
* **Inbound Preservation**: Only local clients connecting to `127.0.0.1:8080` and corresponding `ESTABLISHED` reply packets from `llamacpp` are permitted.

---

#### 2. Configuration: `/etc/nftables.d/llama-sandbox.nft`

```nft
#!/usr/sbin/nft -f

table inet llama_jail {
    chain output {
        type filter hook output priority filter; policy accept;

        # 1. Ignore non-jail traffic
        meta skuid != "llamacpp" accept

        # 2. Allow loopback traffic (bind & reply on 127.0.0.1)
        oif "lo" accept

        # 3. Allow established/related responses to inbound connections
        ct state established,related accept

        # 4. Log and drop all external outbound packet attempts
        log prefix "[NFT_LLAMA_EGRESS_BLOCKED] " flags all drop
    }
}

```

---

#### 3. Deployment & Verification

1. **Include Configuration**
Append the include directive to `/etc/nftables.conf`:
```text
include "/etc/nftables.d/llama-sandbox.nft"

```


2. **Reload Ruleset**
```bash
sudo nft -f /etc/nftables.conf

```


3. **Verify Egress Containment**
Execute outbound requests under the `llamacpp` identity to confirm immediate termination:
```bash
# External connection attempt (fails with timeout or host unreachable)
sudo -u llamacpp curl -m 3 https://1.1.1.1
# => curl: (7) Couldn't connect to server

# Local inference loopback check (succeeds)
curl http://127.0.0.1:8080/v1/models
# => HTTP 200 OK

```


4. **Audit Kernel Logs**
Dropped packets produce verifiable traces in the system journal:
```bash
sudo journalctl -k -g "NFT_LLAMA_EGRESS_BLOCKED"

```



---

#### 4. Security Guarantees

* **Socket Allocation Invalidation**: The moment `connect()` targets an external routable IP, netfilter drops the SYN packet, rendering reverse shells impossible.
* **DNS Tunneling Defense**: Outbound UDP/TCP port 53 traffic is blocked alongside standard IP routing, shutting down DNS-based side-channel exfiltration.
