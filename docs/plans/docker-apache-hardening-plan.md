# docker-apache — Hardening & Release Plan

## Status

Planning branch: `plan/docker-apache-hardening`

Baseline:

- Repository: `infocyph/docker-apache`
- Default branch: `main`
- Current published release: `0.3.1`
- Current upstream base: `httpd:alpine`
- Review snapshot (2026-09-17): the rolling official tag currently resolves through the Apache 2.4.68 / Alpine 3.24 line; this is informational only and must not replace the rolling `httpd:alpine` contract.
- Runtime role: optional LocalDevStack Apache HTTP backend, mainly for Apache-compatible project routing and PHP-FPM/FastCGI integration
- Completed lower layers: shared Scriptomatic/Toolset foundations, `infocyph/runner:0.5`, `infocyph/nginx:0.4.1`
- Current LocalDevStack Apache HTTPS path: Nginx proxies to Apache over backend TLS with client-certificate verification; the release gate therefore needs a real Nginx -> Apache mTLS test, not only standalone Apache SSL syntax validation.

This plan supersedes the older LocalDevStack ecosystem-only Apache draft. It is based on the current repository and the contracts actually shipped by the lower layers.

### Hardline review additions

The repository review adds these requirements to the original draft:

1. Remove `apache-mod-fcgid`. LocalDevStack uses the official image's `mod_proxy_fcgi`; Alpine's `apache-mod-fcgid` is a separate module/package path and can pull Alpine's `apache2` server stack into the official `/usr/local/apache2` image. The final image must contain one Apache runtime, not two parallel distributions.
2. Remove `apache2-utils` unless an explicit runtime consumer is proven before implementation. No current `docker-apache`, LocalDevStack, or `docker-tools` contract requires its `ab`/`htpasswd`/related utilities.
3. Fix `SERVER_NAME` as a real runtime environment contract. The current updater expands it during the image build and therefore bakes `localhost` into `httpd.conf`.
4. Make `APACHE_LOG_DIR` a real runtime contract: create the default directory, support an override, and fail with an actionable startup/config error if the selected path cannot be used by the generated vhost contract.
5. Stop deleting or broadly rewriting unrelated upstream `conf/extra` includes. The image should own only the minimum Apache configuration it intentionally changes.
6. Add a small global defense-in-depth baseline: `ServerTokens Prod`, `ServerSignature Off`, `TraceEnable Off`, and `ProxyRequests Off`. Do not add application policy, HSTS, WAF rules, or project-specific access rules globally.
7. Make health failures diagnostic and always verify the port-80 listener even when no generated vhosts exist. An empty vhost directory is valid; an unreachable Apache listener is not healthy.
8. Add explicit read-only vhost/certificate mount tests matching LocalDevStack.
9. Add a real Nginx -> Apache backend-mTLS compatibility fixture using the current certificate and generated-vhost conventions.
10. Add workflow/config linting, native BuildKit validation, candidate vulnerability scanning, package-inventory checks, and build-cache use without weakening fresh-base behavior.
11. Fix README drift, including the current wrong run/build image name (`infocyph/docker-apache` vs published `infocyph/apache`) and the stale claim that `SERVER_NAME` is build-time only.

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
- Keep Docker DNS/service names as the upstream contract; do not add static-IP dependencies inside this image. Current LocalDevStack compose may still assign fixed addresses; migrating that higher-layer compose contract is outside this release.
- Keep PHP-FPM connectivity compatible with the current `docker-tools` vhost generator, including `SetHandler "proxy:fcgi://<php-service>:9000"` and Unix-socket variants where generated.
- Keep TLS material mounted from LocalDevStack rather than generated inside Apache.
- Keep backend HTTPS compatible with the current Nginx -> Apache mTLS contract.
- Keep `APACHE_LOG_DIR` compatible with generated vhosts that use `${APACHE_LOG_DIR}`.
- Keep `httpd-foreground` as the main runtime process and preserve normal Docker signal semantics.
- Keep the vhost and certificate mounts usable as read-only inputs.
- Do not add LocalDevStack orchestration, database, AI, model, or certificate-issuance responsibilities to this image.

---

# 3. Shared foundation contracts

## 3.1 Scriptomatic

Replace the stale `Scriptomatic/master` fetch with the completed canonical distribution contract:

```text
https://raw.githubusercontent.com/infocyph/Scriptomatic/main/bash/banner.sh
```

Use bounded retries/timeouts, verify the file is non-empty, and syntax-check it with Bash before installation.

Do not create a Scriptomatic release/tag dependency; `main` is intentionally the canonical Scriptomatic channel.

## 3.2 Toolset

Replace the raw `Toolset/main/ChromaCat/chromacat` download with the stable checksum-verifying Toolset installer:

```text
https://github.com/infocyph/Toolset/releases/latest/download/install.sh
```

Install only `chromacat` to `/usr/local/bin`, validate the installer before running it, and verify `chromacat --version` during the build.

This should follow the same downstream convention already shipped by Runner 0.5 and Nginx 0.4.1.

Do not use `chromacat --self-update` as an image maintenance mechanism. Container contents remain immutable; helper updates arrive through a new image build.

---

# 4. File-by-file implementation plan

## 4.1 `Dockerfile`

Current concerns:

- stale Scriptomatic `master` URL;
- raw mutable Toolset source download;
- `apache-mod-fcgid` is not the FastCGI path used by LocalDevStack and can install Alpine's separate Apache stack alongside the official image;
- `apache2-utils` has no proven current runtime consumer;
- rolling `httpd:alpine` base has no permanent compatibility gate;
- build validates configuration only indirectly through `update_httpd.sh`;
- `/var/log/apache2` is an advertised/generated-vhost path but is not explicitly created by the image;
- banner hook can be made consistent with the hardened Runner/Nginx convention.

Plan:

1. Keep `FROM httpd:alpine` and keep it rolling; do not pin Apache or Alpine in the Dockerfile.
2. Remove `apache-mod-fcgid`. Use the `mod_proxy_fcgi.so` already shipped with the official `/usr/local/apache2` runtime.
3. Remove `apache2-utils` unless implementation uncovers a documented runtime requirement. If retained, document the exact command/consumer and test it.
4. Add a CI/package-inventory assertion that the final image does not accidentally install Alpine's `apache2` server package or `apache-mod-fcgid`.
5. Keep only runtime packages that have a proven purpose:
   - `bash`, `figlet`, `ncurses`, and `gawk` for the Scriptomatic/ChromaCat interactive tooling;
   - `tzdata` for runtime timezone support;
   - `musl-locales` while `LANG`/`LC_ALL` remain part of the shell UX contract;
   - `curl` for helper acquisition and runtime health checks;
   - `ca-certificates` for HTTPS verification.
6. Remove redundant cleanup that `apk add --no-cache` already makes unnecessary unless a measurable layer reduction remains.
7. Create `/usr/local/apache2/conf/vhosts` and the default `${APACHE_LOG_DIR}` (`/var/log/apache2`) explicitly.
8. Migrate Scriptomatic banner consumption to `main` using bounded download behavior.
9. Migrate `chromacat` to Toolset's latest stable installer.
10. Verify downloaded helper syntax/version before finalizing the layer.
11. Copy image-owned scripts only from this repository.
12. Run `update_httpd.sh` during build, then run both `httpd -t` and a required-module inventory check (`httpd -M`) as build-time gates.
13. Preserve `/app` as the working directory.
14. Preserve ports `80` and `443`; Apache being behind Nginx does not require inventing additional ports.
15. Preserve one Docker `HEALTHCHECK`, implemented by the repository health script.
16. Use OCI version/revision/created/source/base metadata from the publication workflow rather than hard-coded release metadata.
17. Keep the final image root-capable because Apache startup, privileged ports, runtime timezone setup, and current official-image behavior rely on it. A non-root conversion is a separate compatibility project, not a hidden change in this release.
18. Record/report final image size and package inventory in CI so removals are visible and accidental image growth is reviewable; avoid an arbitrary absolute size threshold tied to a rolling base.

## 4.2 `scripts/update_httpd.sh`

This script is the most important Apache-specific hardening target.

Plan:

1. Preserve idempotent enabling of required modules/directives.
2. Validate every requested module file against the actual official `httpd:alpine` module set in CI before modifying configuration.
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
5. Make `SERVER_NAME` runtime-configurable. Do not interpolate `${SERVER_NAME}` in the build shell; write a runtime Apache environment reference (with the image default remaining `localhost`) and test `docker run -e SERVER_NAME=...` explicitly.
6. Preserve `APACHE_LOG_DIR` environment expansion used by current generated vhosts and validate the default/override paths through tests.
7. Keep `Listen 80` / `Listen 443` only if the base configuration still requires explicit normalization; prove this against fresh upstream images.
8. Add only the small global hardening baseline owned by this image:
   - `ServerTokens Prod`;
   - `ServerSignature Off`;
   - `TraceEnable Off`;
   - `ProxyRequests Off`.
9. Keep the current SSL session-cache behavior only if the current LocalDevStack backend-TLS fixtures still justify it; otherwise prefer upstream defaults over unexplained tuning.
10. Make repeated execution produce the same `httpd.conf` byte-for-byte after the first successful run.
11. Do not delete broad `conf/extra/*.conf` include patterns or otherwise remove unrelated upstream configuration. If one upstream include is demonstrably incompatible, target that exact line and cover it with a regression fixture.
12. Avoid broad regex replacement that could modify unrelated upstream configuration.
13. Run `httpd -t` after mutation and fail the image build on invalid output.
14. Add fixtures proving PHP-FPM proxy directives, rewrite rules, SSL/mTLS vhosts, HTTP/2 directives, and ordinary static vhosts remain valid.
15. Keep this script in the final image for diagnostics/reproducibility; remove the current self-deletion behavior.
16. Emit concise actionable failure messages; success output should remain minimal.

## 4.3 `scripts/entrypoint.sh`

Plan:

- preserve timezone setup;
- keep invalid timezone best-effort rather than fatal;
- normalize an empty/unset `SERVER_NAME` to `localhost` for the runtime Apache substitution contract;
- normalize an empty/unset `APACHE_LOG_DIR` to `/var/log/apache2`;
- ensure the selected log directory exists and report a clear error if it cannot be created/used;
- keep diagnostics on stderr;
- preserve arbitrary command overrides;
- preserve final `exec "$@"` exactly so signals reach `httpd-foreground`;
- do not add background workers to the Apache entrypoint;
- add entrypoint smoke coverage for valid/invalid/unset `TZ`, runtime `SERVER_NAME`, log-dir override, and command override.

## 4.4 `scripts/healthcheck.sh`

Current behavior validates `httpd -t`, conditionally checks mounted TLS files, and curls localhost only when at least one vhost exists.

Plan:

1. Keep configuration validation as the first gate.
2. Keep an empty vhost directory valid.
3. Always verify the port-80 Apache listener, even with zero generated vhosts. Do not use `curl --fail`; any valid HTTP response status can prove the listener is alive.
4. Use bounded connect and total timeouts so a broken listener cannot stall Docker health checks.
5. For configured SSL vhosts, verify required server certificate/key and CA inputs referenced by the current LocalDevStack template are readable.
6. Do not require the Apache container to own/use the Nginx client's private key merely to satisfy health checking. Real backend mTLS is validated from the proxy/client side in CI.
7. Keep health semantics about Apache/runtime reachability, not application correctness: redirects, authentication responses, or expected `404`s are healthy if the listener/configuration is functioning.
8. Print one concise reason to stderr on failure (`config invalid`, `listener unreachable`, `certificate missing`, etc.) and stay quiet on success so `docker inspect` health output is useful.
9. Add dedicated fixtures for empty-vhost, HTTP-only, SSL-enabled, missing-TLS-input, and broken-listener cases.

## 4.5 Apache global hardening boundary

The image may enforce only server-wide protections that are safe for all generated LocalDevStack vhosts:

```text
ServerTokens Prod
ServerSignature Off
TraceEnable Off
ProxyRequests Off
```

Do not globally inject:

- HSTS;
- CSP or application security headers;
- directory/index policy;
- `AllowOverride` policy;
- request-body limits;
- project-specific file deny rules;
- WAF/ModSecurity;
- edge TLS cipher policy beyond what is required to support the generated Apache backend vhosts.

Those belong to generated vhosts or the Nginx edge and must remain independently evolvable.

## 4.6 `README.md`

Reconcile documentation with the actual role and published image contract:

- Apache is an optional LocalDevStack backend, not the primary edge;
- Nginx 0.4.1 is the primary HTTP/TLS router in the current lower-layer architecture;
- use the published image name `infocyph/apache`, not `infocyph/docker-apache`, in build/run/pull examples;
- explain `/app`, vhost, TLS and log mounts;
- document `SERVER_NAME`, `TZ`, and `APACHE_LOG_DIR` as runtime environment contracts and show their actual defaults;
- remove the statement that `SERVER_NAME` is build-time only after the runtime fix lands;
- document health behavior and how to inspect the last health failure;
- document Docker Hub/GHCR tags and immutable release-tag semantics;
- explain that `latest` can be refreshed from a published release against a newer rolling `httpd:alpine` base while the immutable release tag is never overwritten;
- remove examples that imply static container IPs are required;
- add a minimal standalone smoke example only for debugging the image;
- add concise troubleshooting commands for `httpd -t`, `httpd -M`, `/usr/local/bin/healthcheck`, and version inspection.

## 4.7 `.github/workflows/check.yml` — new

Add permanent validation on PRs/pushes and a scheduled rolling-upstream compatibility run:

- `sh -n`/`bash -n` according to each script's declared shell;
- ShellCheck;
- `actionlint` for workflow syntax/expressions;
- native BuildKit/Dockerfile validation (`docker buildx build --check` with the current supported BuildKit interface);
- fresh `httpd:alpine` image build with pull enabled;
- build-time `httpd -t` and required `httpd -M` assertions;
- final package inventory proving Alpine's `apache2`/`apache-mod-fcgid` server path is absent;
- final image size/package report;
- container startup and Docker-health verification;
- default empty-vhost smoke plus real listener check;
- synthetic static vhost smoke;
- PHP-FPM TCP and supported Unix-socket proxy syntax fixtures;
- runtime `SERVER_NAME` override test;
- runtime `APACHE_LOG_DIR` override test;
- global hardening-directive assertion;
- SSL-vhost fixture with ephemeral CI certificates;
- real Nginx -> Apache backend-mTLS fixture matching current `docker-tools` certificate names/verification behavior;
- read-only generated-vhost and certificate mounts;
- entrypoint timezone tests;
- arbitrary command override test;
- clean SIGTERM shutdown;
- architecture-appropriate release contract checks.

No private certificate material is committed; generate CI fixtures at runtime.

The scheduled compatibility run exists because `httpd:alpine` is intentionally rolling. It must use a fresh base pull so upstream changes are discovered before a release/refresh path surprises the repository.

## 4.8 `.github/workflows/docker.publish.yml`

Replace the legacy workflow with the hardened publication contract already proven by Runner 0.5 / Nginx 0.4.1:

- release events use `github.event.release.tag_name` directly; do not resolve "latest release" during a release event;
- a release event publishes the immutable release tag + `latest`;
- scheduled/manual refresh resolves the latest published Apache release source and publishes only `latest`;
- scheduled/manual refresh must never write an existing version tag;
- replace the current ambiguous `0 0 * * */2` cadence with one explicit documented refresh cadence; prefer a simple daily upstream refresh over a misleading "every two days" cron expression;
- `workflow_dispatch` support for an explicit latest refresh without mutating version tags;
- concurrency guard preventing overlapping publish/refresh runs;
- job/step timeouts;
- current supported Action majors at implementation time;
- least-privilege job permissions, with registry/package/attestation permissions isolated to the publish path;
- QEMU + Buildx setup where required for tested multi-arch publication;
- fresh release-candidate build with pull enabled before registry login/publish;
- run the same Apache config/runtime/LocalDevStack compatibility gates against the candidate before credentials are used;
- candidate vulnerability scan before publication; block known fixable `CRITICAL` findings and report remaining findings without pretending an unfixed upstream issue can be repaired in this repository;
- amd64 + arm64 where the official base and runtime tests pass;
- Docker Hub + GHCR from one multi-arch build;
- GHA BuildKit cache may be used for unchanged layers, but base-image freshness must remain enabled and correctness must not depend on cache hits;
- BuildKit provenance;
- SBOM;
- GitHub attestations;
- OCI source/revision/version/created/base-name metadata;
- post-publish digest verification in both registries;
- on a release event, verify release-tag and `latest` resolve to the expected published digest;
- LocalDevStack compatibility gate using the current Apache compose/vhost/backend-mTLS contract.

## 4.9 `.dockerignore`, `.gitignore`, `.gitattributes`, `LICENSE`

- keep build context minimal;
- preserve LF for shell files;
- add `tests/` and generated fixture paths to `.dockerignore` once the new test suite exists, because the runtime Dockerfile copies only image-owned runtime files;
- add test/generated fixture ignores to `.gitignore` only when they are actually generated in-tree;
- no license change.

---

# 5. New test surface

Suggested files:

```text
tests/static.sh
tests/image-smoke.sh
tests/httpd-config.sh
tests/healthcheck.sh
tests/runtime-env.sh
tests/package-inventory.sh
tests/hardening.sh
tests/readonly-mounts.sh
tests/mtls-proxy.sh
tests/release-gate.sh
tests/fixtures/vhosts/static.conf
tests/fixtures/vhosts/php-fpm.conf
tests/fixtures/vhosts/ssl.conf
```

The fixtures should be minimal and test Apache contracts, not duplicate the full LocalDevStack generator.

Where a compatibility behavior is owned by `docker-tools`, prefer consuming or translating the current template shape in the gate rather than creating a divergent second template specification.

---

# 6. LocalDevStack compatibility gates

Before release, prove compatibility with:

1. current Nginx routing to Apache by Docker DNS/service name;
2. representative Apache project vhost;
3. PHP-FPM upstream generated by current LocalDevStack/docker-tools templates;
4. mounted project source under `/app`;
5. `${APACHE_LOG_DIR}`-based generated log paths;
6. shared LocalDevStack certificate paths;
7. Nginx -> Apache HTTPS with `lds-client-internal` client authentication, trusted root CA, SNI, and Apache `SSLVerifyClient require` behavior;
8. HTTP/2 directives used by the generated HTTPS Apache vhost;
9. vhost and certificate mounts operating read-only;
10. mounted logs expected by Runner 0.5;
11. absence of static-IP assumptions inside the Apache image.

Current LocalDevStack compose still assigns fixed addresses to HTTP services. That is a higher-layer compose concern: this image must work without those addresses, while changing/removing them belongs to a later LocalDevStack change.

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
- automatic vhost generation inside Apache;
- ModSecurity/WAF policy;
- application-level security headers;
- a second Alpine-packaged Apache runtime;
- hidden migration of LocalDevStack's fixed compose IPs;
- read-only-rootfs/non-root conversion without a dedicated compatibility project.

Those belong to higher layers or separate projects.

---

# 8. Acceptance criteria

The Apache hardening release is ready when:

1. permanent CI is green, including the scheduled rolling-upstream gate;
2. a fresh rolling `httpd:alpine` image builds successfully;
3. all repository scripts pass syntax/ShellCheck gates and workflows pass `actionlint`;
4. native BuildKit validation passes;
5. `httpd -t` passes after configuration mutation;
6. required official-image Apache modules are present/loaded and the Alpine `apache2`/`apache-mod-fcgid` server path is absent;
7. configuration mutation is idempotent and does not delete unrelated upstream config;
8. runtime `SERVER_NAME` override is proven rather than baked at build time;
9. default/overridden `APACHE_LOG_DIR` works with generated vhost logging;
10. empty-vhost, HTTP, SSL, and diagnostic failure health fixtures pass with bounded timeouts;
11. global defense-in-depth directives are active;
12. representative PHP-FPM and Apache vhosts validate;
13. Nginx -> Apache backend mTLS works with current LocalDevStack/docker-tools certificate conventions;
14. vhost/certificate read-only mounts work;
15. container shutdown is signal-clean;
16. Scriptomatic uses its current canonical channel and Toolset uses the stable installer;
17. candidate vulnerability scan has no known fixable `CRITICAL` blocker;
18. release tags cannot be overwritten by scheduled/manual rebuilds;
19. Docker Hub/GHCR multi-arch publish, SBOM/provenance/attestations, and digest verification pass;
20. LocalDevStack works through Nginx -> Apache without requiring fixed-IP coupling from the image;
21. README uses `infocyph/apache` and documents the actual runtime contract.

---

# 9. Recommended implementation order

1. Add tests/CI around the current behavior, including package inventory and rolling-base checks.
2. Remove the duplicate/unneeded Alpine Apache package path and harden shared helper installation.
3. Harden `update_httpd.sh`, add the safe global baseline, and make mutation provably idempotent/non-destructive.
4. Fix runtime `SERVER_NAME` and `APACHE_LOG_DIR` contracts.
5. Harden healthcheck/entrypoint diagnostics.
6. Add SSL, read-only-mount, and real Nginx -> Apache backend-mTLS gates.
7. Add the full LocalDevStack compatibility gate.
8. Modernize publication workflow and supply-chain verification.
9. Reconcile README and build context.
10. Run final fresh-upstream/release-candidate validation.
11. Publish the next Apache release.
