# docker-apache — Hardening & Release Plan

## Status

Planning branch: `plan/docker-apache-hardening`

Baseline:

- Repository: `infocyph/docker-apache`
- Default branch: `main`
- Current published release: `0.3.1`
- Current upstream base: `httpd:alpine`
- Runtime role: optional LocalDevStack Apache HTTP backend, mainly for Apache-compatible project routing and PHP-FPM/FastCGI integration
- Completed lower layers: shared Scriptomatic/Toolset foundations, `infocyph/runner:0.5`, `infocyph/nginx:0.4.1`

This plan supersedes the older LocalDevStack ecosystem-only Apache draft. It is based on the current repository and the contracts actually shipped by the lower layers.

---

# 1. Goal

Harden `docker-apache` as a small, predictable, independently publishable Apache backend for LocalDevStack while preserving its optional role behind Nginx.

Apache should remain responsible for:

1. providing Apache semantics for projects that need them;
2. serving generated Apache vhosts;
3. proxying PHP requests to PHP-FPM through `mod_proxy_fcgi`;
4. supporting rewrite/header/SSL/HTTP2 behavior required by generated LocalDevStack vhosts;
5. exposing reliable configuration and runtime health signals.

Apache must not become a second LocalDevStack edge router or control plane. Nginx remains the primary LocalDevStack HTTP/TLS edge.

---

# 2. Architecture invariants

Preserve these contracts unless tests prove a contract is broken:

- Keep `httpd:alpine` as the rolling upstream base.
- Keep Apache optional; LocalDevStack must still work for projects routed directly through Nginx/PHP-FPM or Node.
- Keep generated vhosts under `/usr/local/apache2/conf/vhosts`.
- Keep project source under `/app`.
- Keep Docker DNS/service names as the upstream contract; do not add static-IP dependencies.
- Keep PHP-FPM connectivity compatible with the LocalDevStack vhost generator.
- Keep TLS material mounted from LocalDevStack rather than generated inside Apache.
- Keep `httpd-foreground` as the main runtime process and preserve normal Docker signal semantics.
- Do not add LocalDevStack orchestration, database, AI, model, or certificate-issuance responsibilities to this image.

---

# 3. Shared foundation contracts

## 3.1 Scriptomatic

Replace the stale `Scriptomatic/master` fetch with the completed canonical distribution contract:

```text
https://raw.githubusercontent.com/infocyph/Scriptomatic/main/bash/banner.sh
```

Use bounded retries/timeouts, verify the file is non-empty, and syntax-check it before installation.

Do not create a Scriptomatic release/tag dependency; `main` is intentionally the canonical Scriptomatic channel.

## 3.2 Toolset

Replace the raw `Toolset/main/ChromaCat/chromacat` download with the stable checksum-verifying Toolset installer:

```text
https://github.com/infocyph/Toolset/releases/latest/download/install.sh
```

Install only `chromacat` to `/usr/local/bin`, validate the installer before running it, and verify `chromacat --version` during the build.

This should follow the same downstream convention already shipped by Runner 0.5 and Nginx 0.4.1.

---

# 4. File-by-file implementation plan

## 4.1 `Dockerfile`

Current concerns:

- stale Scriptomatic `master` URL;
- raw mutable Toolset source download;
- rolling `httpd:alpine` base has no permanent compatibility gate;
- build validates configuration only indirectly through `update_httpd.sh`;
- banner hook can be made consistent with the hardened Runner/Nginx convention.

Plan:

1. Keep `FROM httpd:alpine`.
2. Keep required Alpine packages only; verify whether both `apache2-utils` and `apache-mod-fcgid` are truly required with the official `httpd` image and generated vhosts before removing either.
3. Keep `curl` and CA certificates because shared helper installation needs HTTPS.
4. Migrate Scriptomatic banner consumption to `main` using bounded download behavior.
5. Migrate `chromacat` to Toolset's latest stable installer.
6. Verify downloaded helper syntax/version before finalizing the layer.
7. Copy image-owned scripts only from this repository.
8. Run `update_httpd.sh` during build, then run `httpd -t` as a build-time gate.
9. Preserve `/app` working directory.
10. Preserve ports `80` and `443`; Apache being behind Nginx does not require inventing additional ports.
11. Preserve the image healthcheck but strengthen its implementation rather than adding a second health mechanism.
12. Use OCI version/revision/created metadata from the publication workflow rather than hard-coded release metadata.
13. Keep the final image root-capable because Apache startup/config/runtime expectations currently rely on the official image behavior; do not introduce a non-root conversion without a separate compatibility project.

## 4.2 `scripts/update_httpd.sh`

This script is the most important Apache-specific hardening target.

Plan:

1. Preserve idempotent enabling of required modules/directives.
2. Validate every module against the actual official `httpd:alpine` module set in CI.
3. Keep required modules for current LocalDevStack behavior:
   - `proxy_module`;
   - `proxy_fcgi_module`;
   - `setenvif_module`;
   - `rewrite_module`;
   - `ssl_module`;
   - `socache_shmcb_module`;
   - `headers_module`;
   - `deflate_module`;
   - `http2_module`.
4. Preserve `IncludeOptional conf/vhosts/*.conf` so an empty vhost directory is valid.
5. Preserve configurable `SERVER_NAME`.
6. Keep `Listen 80` / `Listen 443` only if the base configuration still requires explicit normalization; prove this in tests.
7. Make repeated execution produce the same `httpd.conf` byte-for-byte after the first successful run.
8. Avoid broad regex replacement that could modify unrelated upstream configuration.
9. Run `httpd -t` after mutation and fail the image build on invalid output.
10. Add fixtures proving PHP-FPM proxy directives, rewrite rules, SSL vhosts, and ordinary static vhosts remain valid.
11. Do not remove this script after execution unless there is a strong reason; keeping it available can improve diagnostics/reproducibility. If self-deletion is retained, explicitly test/document that contract.

## 4.3 `scripts/entrypoint.sh`

Plan:

- preserve timezone setup;
- keep invalid timezone best-effort rather than fatal;
- ensure all diagnostics go to stderr;
- preserve final `exec "$@"` exactly so signals reach `httpd-foreground`;
- do not add background workers to the Apache entrypoint;
- add entrypoint smoke coverage for valid/invalid/unset `TZ`.

## 4.4 `scripts/healthcheck.sh`

Current behavior validates `httpd -t`, conditionally checks mounted TLS files, and curls localhost only when at least one vhost exists.

Plan:

1. Keep configuration validation as the first gate.
2. Keep an empty vhost directory healthy.
3. For configured vhosts, verify the Apache process is actually serving rather than relying only on syntax.
4. Avoid assuming a project vhost responds `200`; a redirect, auth response, or expected `404` can still prove the listener is alive. Test connection success separately from application semantics.
5. Preserve TLS-material existence checks when configured vhosts enable SSL.
6. Bound curl timeout so a broken listener cannot stall Docker health checks.
7. Add a dedicated fixture for HTTP-only and TLS-enabled vhost cases.

## 4.5 `README.md`

Reconcile documentation with the actual role:

- Apache is an optional LocalDevStack backend, not the primary edge;
- Nginx 0.4.1 is the primary HTTP/TLS router in the current lower-layer architecture;
- explain `/app`, vhost, TLS and log mounts;
- document `SERVER_NAME` and `TZ`;
- document health behavior;
- document Docker Hub/GHCR tags and immutable release semantics;
- remove examples that imply static container IPs are required;
- add a minimal standalone smoke example only for debugging the image.

## 4.6 `.github/workflows/check.yml` — new

Add permanent validation on PRs/pushes:

- `sh -n`/`bash -n` according to each script's declared shell;
- ShellCheck;
- fresh `httpd:alpine` image build with `--pull`;
- build-time `httpd -t`;
- container startup and Docker-health verification;
- default empty-vhost smoke;
- synthetic static vhost smoke;
- PHP-FPM proxy syntax fixture;
- SSL-vhost fixture with ephemeral CI certificates;
- entrypoint timezone tests;
- clean SIGTERM shutdown;
- architecture-appropriate release contract checks.

No private certificate material is committed; generate CI fixtures at runtime.

## 4.7 `.github/workflows/docker.publish.yml`

Replace the legacy workflow with the hardened publication contract already proven by Runner 0.5 / Nginx 0.4.1:

- release event publishes immutable release tag + `latest`;
- schedule/manual refresh resolves latest published Apache source and publishes only `latest`;
- never overwrite an existing version tag;
- `workflow_dispatch` support;
- concurrency guard;
- timeout;
- current Action majors;
- fresh release-candidate build before registry login/publish;
- amd64 + arm64 where the official base and runtime tests pass;
- Docker Hub + GHCR from one multi-arch build;
- BuildKit provenance;
- SBOM;
- GitHub attestations;
- post-publish digest verification;
- LocalDevStack compatibility gate using the current LocalDevStack Apache compose/vhost contract.

## 4.8 `.dockerignore`, `.gitignore`, `.gitattributes`, `LICENSE`

- keep build context minimal;
- preserve LF for shell files;
- add test/generated fixture ignores only when needed;
- no license change.

---

# 5. New test surface

Suggested files:

```text
tests/static.sh
tests/image-smoke.sh
tests/httpd-config.sh
tests/healthcheck.sh
tests/release-gate.sh
tests/fixtures/vhosts/static.conf
tests/fixtures/vhosts/php-fpm.conf
tests/fixtures/vhosts/ssl.conf
```

The fixtures should be minimal and test Apache contracts, not duplicate the full LocalDevStack generator.

---

# 6. LocalDevStack compatibility gates

Before release, prove compatibility with:

1. current Nginx 0.4.1 routing to Apache by Docker DNS;
2. representative Apache project vhost;
3. PHP-FPM upstream generated by current LocalDevStack/docker-tools templates;
4. mounted project source under `/app`;
5. shared LocalDevStack certificate paths;
6. mounted logs expected by Runner 0.5;
7. absence of static-IP assumptions inside the Apache image.

The LocalDevStack version update happens only after the new Apache image is published and these gates pass.

---

# 7. Explicit non-goals

Do not add:

- LLM/AI functionality;
- Ollama client/runtime packages;
- Docker socket requirements;
- project lifecycle commands;
- certificate generation;
- database tooling;
- Nginx-style reserved host routing;
- automatic vhost generation inside Apache.

Those belong to higher layers.

---

# 8. Acceptance criteria

The Apache hardening release is ready when:

1. permanent CI is green;
2. a fresh rolling `httpd:alpine` image builds successfully;
3. all repository scripts pass syntax/ShellCheck gates;
4. `httpd -t` passes after configuration mutation;
5. configuration mutation is idempotent;
6. HTTP and SSL health fixtures pass;
7. representative PHP-FPM and Apache vhosts validate;
8. container shutdown is signal-clean;
9. Scriptomatic uses its current canonical channel and Toolset uses the stable installer;
10. release tags cannot be overwritten by scheduled rebuilds;
11. Docker Hub/GHCR multi-arch publish and attestations pass;
12. LocalDevStack works through Nginx 0.4.1 -> Apache without fixed-IP coupling.

---

# 9. Recommended implementation order

1. Add tests/CI around the current behavior.
2. Harden shared helper installation in `Dockerfile`.
3. Harden and make `update_httpd.sh` provably idempotent.
4. Harden healthcheck/entrypoint.
5. Add LocalDevStack compatibility gate.
6. Modernize publication workflow.
7. Reconcile README.
8. Run final fresh upstream/release candidate validation.
9. Publish the next Apache release.
