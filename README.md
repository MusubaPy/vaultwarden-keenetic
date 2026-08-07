<p align="center">
  <strong>🔐 vaultwarden-keenetic</strong>
</p>

<p align="center">
  <a href="README.ru.md">🇷🇺 Русский</a>
</p>

<p align="center">
  <a href="https://github.com/MusubaPy/vaultwarden-keenetic/actions"><img src="https://img.shields.io/github/actions/workflow/status/MusubaPy/vaultwarden-keenetic/build.yml?style=flat&colorA=222222&colorB=3FB950" alt="CI"></a>
  <a href="https://github.com/MusubaPy/vaultwarden-keenetic/releases/latest"><img src="https://img.shields.io/github/v/release/MusubaPy/vaultwarden-keenetic?style=flat&colorA=222222&colorB=58A6FF" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/MusubaPy/vaultwarden-keenetic?style=flat&colorA=222222&colorB=58A6FF" alt="License"></a>
  <a href="https://www.rust-lang.org"><img src="https://img.shields.io/badge/Rust-DEA584?style=flat&colorA=222222&logo=rust&logoColor=white" alt="Rust"></a>
  <a href="https://www.mips.com"><img src="https://img.shields.io/badge/MIPS32r2-003366?style=flat&colorA=222222" alt="MIPS32r2"></a>
  <a href="https://keenetic.com"><img src="https://img.shields.io/badge/Keenetic-00A651?style=flat&colorA=222222&logo=keenetic&logoColor=white" alt="Keenetic"></a>
</p>

<p align="center">
  Run <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> on a Keenetic router with <strong>256 MB RAM</strong>.
  <br>
  Cross-compiled for MIPS32r2 big-endian · No Docker · No extra packages.
</p>

---

## Target Hardware

| | |
|---|---|
| **Router** | Keenetic Hero DSL KN-2410 |
| **SoC** | EcoNet EN7516G |
| **CPU** | MIPS 1004Kc (MIPS32r2, big-endian) |
| **ABI** | o32, soft-float |
| **Kernel** | Linux 4.9 |
| **libc** | glibc 2.27 (Entware mips-3.4) |
| **RAM** | 256 MB |

## Why Patches Are Needed

Vaultwarden's dependency tree uses `std::sync::atomic::AtomicU64`, which **doesn't exist** on 32-bit MIPS. Three crates currently need patching:

| Crate | Problem | Fix |
|-------|---------|-----|
| `cached` | Uses `AtomicU64` for cache counters | `portable-atomic` with mutex fallback |
| `mea` | Uses `AtomicU64` for async synchronization | `portable-atomic` with mutex fallback |
| `getrandom` | Calls `getrandom(2)` directly and receives `ENOSYS` on the Keenetic kernel | Force the `/dev/urandom` fallback on MIPS |

Additionally, the Rust `std` library (compiled from source via `-Z build-std`) uses 64-bit atomics internally, requiring `libatomic.so.1` at runtime.

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/MusubaPy/vaultwarden-keenetic.git
cd vaultwarden-keenetic

# 2. Install Rust nightly and the Entware SDK (see Prerequisites)

# 3. Build the MIPS binary locally
./scripts/build.sh

# 4. Perform the initial deployment
ROUTER=root@ROUTER_IP SSH_PORT=222 ./scripts/deploy.sh
```

The build script manages its own upstream Vaultwarden checkout under `build/source`. The router never compiles Rust code.

After the initial deployment, configure KeenDNS HTTPS as described below. Subsequent updates require one command:

```bash
./scripts/update.sh
```

The updater fetches upstream Vaultwarden, applies the maintained MIPS patches, reuses a cached binary when inputs are unchanged, uploads the binary, restarts the service, verifies port `8080`, and automatically restores the previous binary on failure. The live init script, `ADMIN_TOKEN`, database, attachments, and other persistent data are not overwritten.

## Trusted HTTPS with KeenDNS

Do not use Vaultwarden's self-signed certificate for mobile clients. Browsers may allow a manual exception, but Bitwarden applications normally require a certificate trusted by the operating system. KeenDNS can terminate trusted HTTPS on the router and proxy requests to Vaultwarden over the local network.

### 1. Create a web application domain

In the Keenetic web interface:

1. Open **Network Rules** > **Domain Name** > **KeenDNS**.
2. Configure a KeenDNS router name if one does not already exist, for example `example.keenetic.pro`.
3. Under **Access to web applications running on your network**, click **Add**.
4. Select the Keenetic router itself as the host because Vaultwarden runs on the router.
5. Enter a subdomain such as `vaultwarden`.
6. Set remote Internet access to **Unrestricted**.
7. Set the TCP port to `8080`.
8. Save the rule.

The resulting public address will look like:

```text
https://vaultwarden.example.keenetic.pro
```

Use the exact generated address in Vaultwarden and in every Bitwarden client. Do not append `:8080` to the public URL.

### 2. Configure Vaultwarden behind the KeenDNS proxy

Edit `/opt/etc/init.d/S91vaultwarden` on the router so that the network settings match this topology:

```sh
export ROCKET_ADDRESS=0.0.0.0
export ROCKET_PORT=8080
export DOMAIN=https://vaultwarden.example.keenetic.pro
```

KeenDNS should terminate HTTPS. Remove or comment out the `ROCKET_TLS` export so Vaultwarden serves plain HTTP only on the internal port:

```sh
# ROCKET_TLS is intentionally disabled; HTTPS terminates on KeenDNS.
```

Restart and verify the service:

```sh
/opt/etc/init.d/S91vaultwarden restart
/opt/etc/init.d/S91vaultwarden status
```

Then open the public KeenDNS address. The browser and mobile application should accept the certificate without a warning.

### 3. Secure the installation

After creating the required account:

1. Set `SIGNUPS_ALLOWED=false` in `/opt/etc/init.d/S91vaultwarden`.
2. Generate an Argon2id PHC string with `/opt/bin/vaultwarden hash`.
3. Store the complete PHC string in `ADMIN_TOKEN`, enclosed in single quotes.
4. Restart Vaultwarden and sign in to `/admin` with the original password used to generate the hash, not with the PHC string.

Never commit the live `ADMIN_TOKEN`, TLS private keys, or Vaultwarden data directory to this repository.

## Prerequisites

### Rust Toolchain

```bash
curl https://sh.rustup.rs -sSf | sh
rustup toolchain install nightly
rustup +nightly component add rust-src
```

### Entware SDK

Download the MIPS32r2 toolchain from [Entware wiki](https://wiki.keenetic.com/entware) and extract to `~/tmp/entware-sdk`:

```bash
# Expected layout:
ls ~/tmp/entware-sdk/staging_dir/toolchain-mips_mips32r2_gcc-8.4.0_glibc-2.27/
```

### Vaultwarden Source

No separate source checkout is required. `scripts/build.sh` clones and maintains upstream Vaultwarden in `build/source`.

## Project Structure

```text
vaultwarden-keenetic/
├── vendor/                  # Patched crate sources used by the build
│   ├── cached/              #   AtomicU64 to portable-atomic
│   ├── mea/                 #   AtomicU64 to portable-atomic
│   └── getrandom/           #   MIPS /dev/urandom fallback
├── patches/                 # Historical/reference diffs
├── scripts/
│   ├── build.sh             # Managed checkout, patching, and cross-compilation
│   ├── deploy.sh            # Initial deployment
│   ├── update.sh            # One-command safe update with rollback
│   └── gen-tls.sh           # Optional self-signed certificate helper
├── config/
│   ├── .cargo/config.toml   # Cargo cross-compilation template
│   └── S91vaultwarden       # Initial Entware service template
└── .github/workflows/
    └── build.yml
```

## Environment Variables

The live values are stored in `/opt/etc/init.d/S91vaultwarden` on the router. `scripts/update.sh` preserves that file.

| Variable | Recommended value | Description |
|----------|-------------------|-------------|
| `ROCKET_PORT` | `8080` | Internal listening port |
| `ROCKET_ADDRESS` | `0.0.0.0` | Required for the KeenDNS proxy to reach the service |
| `DOMAIN` | `https://vaultwarden.example.keenetic.pro` | Exact public KeenDNS web application URL |
| `ADMIN_TOKEN` | Argon2id PHC string | Admin panel authentication hash |
| `SIGNUPS_ALLOWED` | `false` after account creation | Prevent public registrations |
| `ICON_SERVICE` | `internal` | Favicon proxy suitable for low-memory systems |
| `LOG_LEVEL` | `warn` | Minimal logging |

## Router Management

```bash
ssh -p 222 root@ROUTER_IP

/opt/etc/init.d/S91vaultwarden status    # Check if running
/opt/etc/init.d/S91vaultwarden restart   # Restart
/opt/etc/init.d/S91vaultwarden stop      # Stop

tail -f /opt/var/log/vaultwarden.log     # Live logs
/opt/bin/vaultwarden hash                # Generate admin token hash
```

## Updating Vaultwarden

Run the updater from this repository on the build PC:

```bash
ROUTER=root@ROUTER_IP SSH_PORT=222 ./scripts/update.sh
```

Only one router password prompt is expected because SSH connection multiplexing is used. Compilation always runs on the PC. If the upstream commit, toolchain, Cargo inputs, and maintained patches are unchanged, the existing binary is reused. The router receives a staged binary, retains the previous version for rollback, and keeps its configuration and data untouched.

Build and router logs are saved locally under `build/` when relevant:

```text
build/cargo-build.log
build/router-vaultwarden.log
```

## Technical Notes

### AtomicU64 on MIPS32

MIPS32r2 has no native 64-bit atomic instructions. The `portable-atomic` crate provides a mutex-based fallback that's used when the `fallback` feature is enabled. This adds negligible overhead for the cache counters and content-length tracking where `AtomicU64` is used.

### getrandom on Linux 4.9

The Keenetic kernel doesn't expose the `getrandom(2)` syscall (added for MIPS in Linux 4.7 but may be disabled in the Keenetic firmware). The patched `getrandom` crate forces the `/dev/urandom` file-based fallback.

### libatomic.so.1

The Rust standard library (compiled from source via `-Z build-std`) uses `__atomic_*` builtins for internal 64-bit operations. These are provided by GCC's `libatomic`. Static linking fails in PIE binaries (no `-fPIC` in the toolchain's `libatomic.a`), so the shared library (~102 KB) must be present on the router.

### Memory Considerations

With 256 MB RAM, these settings help:
- `LOG_LEVEL=warn` — minimal logging
- `ICON_SERVICE=internal` — avoids spawning external HTTP requests for favicons
- `panic=abort` — smaller binary, no unwinding
- `strip=debuginfo` — removes debug symbols

## License

This project is licensed under the [MIT License](LICENSE).

Vaultwarden is licensed under [AGPL-3.0](https://github.com/dani-garcia/vaultwarden/blob/main/LICENSE.txt).
