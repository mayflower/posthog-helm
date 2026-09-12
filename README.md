# PostHog Helm Chart

This chart is a clean v1 Kubernetes chart for the current PostHog service topology.

It intentionally does not preserve the old [`PostHog/charts-clickhouse`](https://github.com/PostHog/charts-clickhouse) values API. That repository is useful historical context, but its dependency stack and workload split are outdated. PostHog also published the background for ending official chart support in [Sunsetting Helm support for self-hosted PostHog](https://posthog.com/blog/sunsetting-helm-support-posthog).

The PostHog-owned runtime images follow the upstream container defaults and use the mutable `master` tag by default. `global.imagePullPolicy` defaults to `Always` so Kubernetes refreshes those images on rollout. Override `images.*.tag` in production when you need a controlled rollout.

## Requirements

- Kubernetes `>=1.28`
- Helm with OCI registry support
- A default `StorageClass` for the bundled evaluation profile
- A working Ingress controller when `ingress.enabled=true`
- External DNS pointing `global.domain` / `ingress.host` at the cluster when using a public URL
- cert-manager, Prometheus and Grafana are not part of this chart. Install them separately; `ingress.annotations` and `monitoring.serviceMonitor` connect to them.

## Images and Supply Chain

PostHog's own app image, `ghcr.io/posthog/posthog`, bundles the `ee/` directory, which is under the PostHog Enterprise License: free for development and testing, licensed for production only with a subscription. Everything outside `ee/` is MIT. PostHog maintains a `posthog-foss` source mirror with `ee/` removed but publishes no image from it, so this chart defaults `images.app` to a pure-MIT build from the [mayflower fork](https://github.com/mayflower/posthog): `ghcr.io/mayflower/posthog-foss`, with `ee/` replaced by a shim and the rest of the tree unchanged. The image is labelled MIT, keeps upstream's uid 10001, and is verified in that repository's CI against the chart's own commands (migrations, web, Celery worker, Temporal workers). It is pinned to the commit it was built from. Holders of an enterprise license can set `images.app.repository` back to `ghcr.io/posthog/posthog`. The Node and Rust images contain no enterprise code and stay on upstream's builds.

Because the FOSS app image is pinned to a commit while the node image follows upstream `master`, the two can drift apart. Pin `images.node.tag` to a build of the same source revision when one is available.

The other PostHog images default to the mutable `master` tag with pull policy `Always`, as upstream's hobby stack does. For a controlled rollout set an immutable `images.<name>.tag`, or `images.<name>.digest` (`sha256:...`), which wins over the tag. Set `global.allowMutableImageTags=false` to make the chart refuse `master` and `latest`.

No Bitnami images are involved. The bundled backing services are chart components on upstream images, the same ones upstream's compose stack uses: Postgres (`components.postgres`, official `postgres` image), ZooKeeper (`components.zookeeper`, official `zookeeper` image), Valkey (`components.valkey`), SeaweedFS for object storage (`components.objectStorage`) and for replay (`components.seaweedfs`), and Temporal. Redpanda and the ClickHouse operator are the only remaining subcharts. Each bundled store is a single replica with one claim; treat them as evaluation grade and run managed services in production.

Published chart versions are signed with cosign using GitHub's OIDC identity. Verify with:

```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/mayflower/posthog-helm/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/mayflower/posthog-helm/posthog:0.6.0
```

## Security Defaults

Every pod runs with seccomp `RuntimeDefault`, no privilege escalation, all capabilities dropped, and no ServiceAccount token mounted. Components running the PostHog app, node and Rust images also run as their image's non-root uid (`10001` and `65534`); images that stay root, such as Temporal and SeaweedFS, do not get `runAsNonRoot`. The pod context resolves from `components.<name>.podSecurityContext`, then `images.<name>.podSecurityContext`, then `defaultPodSecurityContext`.

`networkPolicy.enabled=true` adds a default-deny ingress policy for chart pods that allows the release namespace, the namespaces in `networkPolicy.ingress.namespaceSelector` (your ingress controller and Prometheus), and `networkPolicy.ingress.extraRules`. Subchart pods are not covered.

Every workload has resource requests and no limits; they are starting points, not measurements. Override `defaultResources` or `components.<name>.resources`.

## Install Ordering

The `kafkaInit` and `migrate` jobs run as `post-install,pre-upgrade` hooks. Helm creates pre-install hooks before anything else in a release, so a pre-install job that needs the chart's ServiceAccount, its Secret, or the bundled databases can never start in an empty namespace. On a fresh install the jobs therefore run once every resource exists, waiting inside the pod for Kafka and ClickHouse with bounded timeouts; on upgrades they run before the workloads roll, as before. `asyncMigrationsCheck` stays a post-install/post-upgrade hook and runs after `migrate`.

The jobs also carry Argo CD annotations (`argocd.argoproj.io/hook: Sync` for the init jobs, `PostSync` for the check), which Argo CD prefers over the Helm ones. A first Argo CD sync creates the jobs together with the rest of the release and they wait for their dependencies the same way. Override `components.<job>.annotations` if your sync policy needs something else.

Every job has an `activeDeadlineSeconds`, so a missing dependency fails the install with a job log instead of hanging it.

## Profiles

- `profile.mode=bundled` deploys PostHog plus bundled backing services: Redpanda through its subchart, ClickHouse through the Altinity operator, and Postgres, ZooKeeper, Valkey, SeaweedFS object storage, the SeaweedFS replay store, the Valkey CDP shadow store, Temporal and browserless as chart components. Use it for non-production evaluation.
- `profile.mode=external` deploys PostHog workloads and uses managed dependencies where configured. Kafka can still use the bundled Redpanda subchart by leaving `external.kafka.hosts` empty and enabling `subcharts.redpanda.enabled`.

## Quick Start

Install the bundled profile for a non-production evaluation:

```bash
helm upgrade --install posthog . \
  --namespace posthog \
  --create-namespace \
  --set global.domain=posthog.example.com \
  --set global.siteUrl=https://posthog.example.com
```

Install from the GitHub Container Registry after a chart version has been published:

```bash
helm upgrade --install posthog oci://ghcr.io/mayflower/posthog-helm/posthog \
  --version 0.6.0 \
  --namespace posthog \
  --create-namespace \
  --set global.domain=posthog.example.com \
  --set global.siteUrl=https://posthog.example.com
```

For local evaluation without DNS, disable ingress and port-forward the web service:

```bash
helm upgrade --install posthog . \
  --namespace posthog \
  --create-namespace \
  --set ingress.enabled=false \
  --set global.domain=localhost \
  --set global.siteUrl=http://localhost:8000

kubectl -n posthog port-forward svc/posthog-posthog-web 8000:8000
```

## Production Install

Production installs should use `profile.mode=external`, explicitly managed secrets, and a reviewed values file. Start from `examples/external-values.yaml`, replace every `*.example.com` endpoint, and create the referenced secrets before installing.

`examples/external-values.yaml` assumes managed Temporal and managed session-recording storage, so it disables the bundled `temporal` and `seaweedfs` components. If you want external Postgres/Redis/ClickHouse but bundled Temporal, keep `components.temporal.enabled=true` and set `external.temporal.host` to the templated chart service host as shown in `values.yaml`.

Generate runtime secrets:

```bash
kubectl create namespace posthog

SECRET_KEY="$(openssl rand -hex 50)"
ENCRYPTION_SALT_KEYS="$(openssl rand -hex 16)"
CAPTURE_LOGS_JWT_SECRET="$(openssl rand -hex 32)"
LIVESTREAM_JWT_SECRET="$(openssl rand -hex 32)"
INTERNAL_API_SECRET="$(openssl rand -hex 32)"

kubectl -n posthog create secret generic posthog-runtime-secrets \
  --from-literal=SECRET_KEY="${SECRET_KEY}" \
  --from-literal=ENCRYPTION_SALT_KEYS="${ENCRYPTION_SALT_KEYS}" \
  --from-literal=CAPTURE_LOGS_JWT_SECRET="${CAPTURE_LOGS_JWT_SECRET}" \
  --from-literal=LIVESTREAM_JWT_SECRET="${LIVESTREAM_JWT_SECRET}" \
  --from-literal=INTERNAL_API_SECRET="${INTERNAL_API_SECRET}"
```

`ENCRYPTION_SALT_KEYS` must contain one or more comma-separated 32-character URL-safe keys. `openssl rand -hex 16` produces a valid single key. Keep old keys in the comma-separated list when rotating so existing encrypted integration data remains decryptable.

When you let the chart generate these values instead, it mints them once and reads the existing Secret back on every upgrade, so keys stay stable. That relies on Helm's `lookup`, which `helm template` and Argo CD do not have: a GitOps install without `secrets.existingSecret` or explicit `secrets.values` would get fresh keys on every sync. Always set one of the two there.

Create provider credential secrets matching your production values file:

```bash
kubectl -n posthog create secret generic posthog-postgres \
  --from-literal=password='<postgres-password>'

kubectl -n posthog create secret generic posthog-redis \
  --from-literal=password='<redis-password>'

kubectl -n posthog create secret generic posthog-clickhouse \
  --from-literal=password='<clickhouse-password>'

kubectl -n posthog create secret generic posthog-object-storage \
  --from-literal=access-key='<object-storage-access-key>' \
  --from-literal=secret-key='<object-storage-secret-key>'

kubectl -n posthog create secret generic posthog-session-recording \
  --from-literal=access-key='<session-recording-access-key>' \
  --from-literal=secret-key='<session-recording-secret-key>'
```

Install from the published OCI chart:

```bash
helm upgrade --install posthog oci://ghcr.io/mayflower/posthog-helm/posthog \
  --version 0.6.0 \
  --namespace posthog \
  -f ./values.production.yaml
```

Install from a local checkout:

```bash
helm upgrade --install posthog . \
  --namespace posthog \
  -f ./examples/external-values.yaml
```

## External Dependencies

`examples/external-values.yaml` is a renderable template, not a production-ready endpoint list. Review these dependencies before installation:

| Dependency | Values | Requirements |
| --- | --- | --- |
| PostgreSQL | `external.postgres.*` | Reachable from the namespace. The bundled component creates the databases in `internal.postgres.extraDatabases` on first start; an external Postgres needs the same databases created by you. The configured user must own or be able to migrate the configured database. The chart currently uses the same Postgres URL for `DATABASE_URL`, `PERSONS_DATABASE_URL`, and `BEHAVIORAL_COHORTS_DATABASE_URL`. |
| Redis | `external.redis.*` | Reachable Redis endpoint. Use `external.redis.passwordSecret` for password auth, or remove it if your endpoint has no password. Set `external.redis.tls=true` only for TLS-enabled Redis endpoints. |
| Kafka or Redpanda | `external.kafka.hosts` or bundled Redpanda | Plain Kafka bootstrap string by default. If you need SASL/TLS, add the required PostHog env vars under the affected `components.*.extraEnv` and manage topics externally unless `rpk` can connect with the same settings. |
| ClickHouse | `external.clickhouse.*` | The configured user needs enough privileges for PostHog migrations: database/table creation, materialized views, dictionaries, Kafka-engine tables, named collections, and `SYSTEM FLUSH LOGS`. Set `cluster`/`migrationsCluster` when using replicated clusters. |
| Object storage | `external.objectStorage.*` | S3-compatible endpoint and bucket for general object storage. Create the bucket before installing when the provider does not auto-create buckets. |
| Session recording storage | `external.sessionRecording.*` | S3-compatible endpoint and credentials for replay payloads. This can share the same provider/secret as object storage, but keep a separate bucket or prefix operationally. |
| Temporal | `external.temporal.*`, `components.temporal.enabled` | Existing Temporal frontend endpoint, or the bundled Temporal component with `external.temporal.host` pointing at the chart service. Disable `components.temporal` only when you provide managed Temporal. The bundled Temporal reads its Postgres credentials from the chart's Postgres settings, so with external Postgres it needs `external.postgres.passwordSecret`; a bare `external.postgres.url` leaves `POSTGRES_PWD` empty. |
| CDP shadow store | `external.valkey.*`, `components.valkey.enabled` | Redis-compatible instance the CDP services dual-write to. It must be separate from the main Redis: the rate limiters run the same token-bucket calls against both, so one instance behind both names charges every key twice. The bundled `valkey` component is used unless `external.valkey.host` is set. Contents are disposable. |
| Headless browser | `components.browserless` | Chromium for image exports, subscriptions, heatmap and event screenshots; the PostHog image ships no browser and exports raise without it. Every Django process gets its URL and token while it is enabled. With an externally managed Secret, add a `BROWSERLESS_TOKEN` key; the token refs are optional so pods start without it, but exports then fail with an auth error. |
| Data warehouse storage | `internal.objectStorage.dataWarehouseBucket` | In bundled mode the chart routes warehouse and data modeling writes through the bundled object store (`USE_LOCAL_SETUP`). In external mode set `BUCKET_URL`, `DATAWAREHOUSE_BUCKET` and the AWS-style credentials through `extraEnv` on the warehouse workers, as upstream does. |
| Error tracking symbol resolution | `components.cymbalResolution` | Cymbal's processing mode has no inline symbol resolution and refuses to boot without a resolution service. The chart runs one behind a headless Service and points `cymbal` at it; it shares the object storage settings for symbol sets. |
| OpenSearch | `external.opensearch.host` | Optional but recommended for search-backed features. Include the URL scheme when TLS is used, for example `https://opensearch.example.com:9200`. |

## Runtime Secrets

For production, create a runtime secret and set `secrets.existingSecret`. The secret must contain:

- `SECRET_KEY`
- `ENCRYPTION_SALT_KEYS`
- `CAPTURE_LOGS_JWT_SECRET`
- `LIVESTREAM_JWT_SECRET`
- `INTERNAL_API_SECRET`

It must also contain these keys when you do not configure the provider-specific external secret refs:

- `CLICKHOUSE_PASSWORD`
- `OBJECT_STORAGE_ACCESS_KEY_ID`
- `OBJECT_STORAGE_SECRET_ACCESS_KEY`
- `SESSION_RECORDING_V2_S3_ACCESS_KEY_ID`
- `SESSION_RECORDING_V2_S3_SECRET_ACCESS_KEY`

The bundled defaults are meant to render and run a self-contained non-production stack. Replace them before real use.

External mode can use separate provider-managed secrets for service credentials:

```yaml
external:
  postgres:
    host: postgres.example.com
    port: 5432
    database: posthog
    user: posthog
    sslMode: require
    passwordSecret:
      name: posthog-postgres
      key: password
  redis:
    host: redis.example.com
    port: 6379
    database: 0
    tls: false
    passwordSecret:
      name: posthog-redis
      key: password
  clickhouse:
    passwordSecret:
      name: posthog-clickhouse
      key: password
  objectStorage:
    accessKeySecret:
      name: posthog-object-storage
      key: access-key
    secretKeySecret:
      name: posthog-object-storage
      key: secret-key
  sessionRecording:
    accessKeySecret:
      name: posthog-session-recording
      key: access-key
    secretKeySecret:
      name: posthog-session-recording
      key: secret-key
```

When `external.postgres.passwordSecret.name` is set, the chart builds `DATABASE_URL` from host/user/database, appends `sslmode`/`params`, and injects `POSTGRES_PASSWORD` from that secret. When `external.redis.passwordSecret.name` is set, the chart injects `REDIS_PASSWORD` and builds Redis URLs with Kubernetes env expansion. Logs and traces ingestion receive the Redis URL because PostHog's current Node.js Redis pool reads credentials from that URL for those components. This avoids putting service passwords in values files.

## Kafka Topics

The `kafkaInit` job creates the topics in `kafka.topics` once Kafka answers. It uses Redpanda's `rpk` CLI against `KAFKA_HOSTS` and only creates topics that are missing: changing `kafka.defaultPartitions` later does not alter existing topics, so repartition those yourself.

Use the built-in topic job only when `rpk topic list --brokers "$KAFKA_HOSTS"` and `rpk topic create ...` work from inside the cluster without extra SASL/TLS flags. For managed Kafka, pre-create topics yourself and disable the job:

```yaml
components:
  kafkaInit:
    enabled: false
```

Keep `kafka.defaultPartitions` and `kafka.defaultReplicationFactor` aligned with your broker policy when the chart creates topics. Override `kafka.topics` when you use custom PostHog topic names or broker-side topic management.

## Ingress, DNS, and TLS

`global.siteUrl` must be the externally reachable PostHog URL. Event capture, feature flags, session recording, and redirects depend on it. `ingress.host` defaults to `global.domain` when omitted.

`routing.routes` mirrors the upstream Caddy proxy from `docker-compose.base.yml`: capture (`/e`, `/i/v0`, `/i/v1/analytics/events`, `/batch`, `/capture`), AI capture, replay capture, logs/traces/metrics, flags including `/api/feature_flag/local_evaluation`, surveys and remote config, webhooks, livestream, and the web app for everything else. In bundled mode `routing.objectStorageRoute` also forwards `/<bucket>` to the bundled object store, because `OBJECT_STORAGE_PUBLIC_ENDPOINT` defaults to the site URL. The bundled object store creates every bucket in `internal.objectStorage.buckets` at startup; keep `internal.objectStorage.bucket` and `dataWarehouseBucket` in that list. In external mode set `external.objectStorage.publicEndpoint` instead.

The `/livestream` route must reach the service without its prefix. An Ingress cannot express that portably, so `ingress.stripPrefix.mode` controls it: `nginx` renders a second Ingress with ingress-nginx's `rewrite-target` annotation and buffering disabled for server-sent events; `none` passes the prefix through and leaves stripping to your controller; `auto` (the default) picks `nginx` when `ingress.className` contains `nginx` and `none` otherwise. The optional Caddy `proxy` component honours `stripPrefix` directly.

Example with cert-manager and nginx:

```yaml
global:
  domain: posthog.example.com
  siteUrl: https://posthog.example.com

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  tls:
    - secretName: posthog-tls
      hosts:
        - posthog.example.com
```

Example with Traefik:

```yaml
ingress:
  enabled: true
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
  tls:
    - secretName: posthog-tls
      hosts:
        - posthog.example.com
```

Example with an existing TLS secret:

```yaml
ingress:
  enabled: true
  className: nginx
  tls:
    - secretName: existing-posthog-tls
      hosts:
        - posthog.example.com
```

## Validate Before Install

Dependencies are vendored as unpacked chart directories because Helm 4 linting expects directories, while `helm dependency update` writes archives.

CI runs `helm lint`, the `helm-unittest` suites in `tests/`, and `kubeconform` over both profiles on every push. Locally:

```bash
helm plugin install --verify=false https://github.com/helm-unittest/helm-unittest
helm unittest .
helm lint --strict .
helm template posthog . > /tmp/posthog.yaml
helm template posthog . -f ./examples/external-values.yaml > /tmp/posthog-external.yaml
kubeconform -strict -ignore-missing-schemas /tmp/posthog.yaml
helm template posthog oci://ghcr.io/mayflower/posthog-helm/posthog \
  --version 0.6.0 \
  -f ./values.production.yaml > /tmp/posthog-production.yaml
```

Refresh dependencies after changing `Chart.yaml` dependency versions:

```bash
helm dependency update .
for archive in ./charts/*.tgz; do tar -xzf "$archive" -C ./charts; done
rm ./charts/*.tgz
```

## Verify After Install

Check that the install jobs and core pods completed:

```bash
kubectl -n posthog get jobs
kubectl -n posthog get pods
kubectl -n posthog logs job/posthog-posthog-migrate
kubectl -n posthog logs job/posthog-posthog-kafka-init
```

Check the externally routed app:

```bash
curl -I https://posthog.example.com/
curl -fsS https://posthog.example.com/preflight?mode=live
curl -fsS https://posthog.example.com/flags/?v=2
curl -fsS -X POST https://posthog.example.com/capture/ \
  -H 'Content-Type: application/json' \
  --data '{"api_key":"phc_replace_me","event":"helm_test","properties":{}}'
```

The `/capture/` request is only a transport check until you replace `api_key` with a real project key from the PostHog UI.

For local port-forward checks:

```bash
kubectl -n posthog port-forward svc/posthog-posthog-web 8000:8000
curl -fsS http://localhost:8000/preflight?mode=live
```

## Temporal Workers

A Temporal worker serves exactly one task queue, and outside of debug mode every PostHog product has its own queue. `temporalDjangoWorker` serves the general-purpose queue; the `temporalWorker*` components serve one queue each: batch exports, warehouse syncs and metadata, data modeling, error tracking and its lifecycle, session replay, experiments, LLM analytics, weekly digests, event screenshots, and log alerting are enabled by default. Workers for Max AI, LLM evals, replay vision, video export, the analytics platform and the managed warehouse are present but disabled, because they need an LLM provider key or another optional component.

Each worker is a full Django process. Disable the ones for products you do not use:

```yaml
components:
  temporalWorkerDataWarehouse:
    enabled: false
  temporalWorkerDataModeling:
    enabled: false
```

Upstream's hobby stack runs a single worker on the general-purpose queue, so batch exports and the warehouse do not run there; this chart covers them.

## Optional Feature Components

The default profile stays a generic PostHog install and keeps newer or heavier feature surfaces disabled until you explicitly opt in. These components render from the same generic workload template and inherit the chart's Postgres, Redis, Kafka, ClickHouse, Temporal, object-storage, scheduling, and monitoring settings.

Enable the components you need under `components`:

```yaml
components:
  embeddingWorker:
    enabled: true
    extraEnv:
      - name: OPENAI_API_KEY
        valueFrom:
          secretKeyRef:
            name: posthog-llm-provider
            key: openai-api-key
  batchImportWorker:
    enabled: true
  webhookS3Sink:
    enabled: true
  ingestionMetrics:
    enabled: true
  recordingRasterizer:
    enabled: true
```

Available optional components:

- `embeddingWorker` consumes `document_embeddings_input`, writes `clickhouse_document_embeddings`, and emits `document_embedding_results`. It needs an embedding provider key through `extraEnv`.
- `batchImportWorker` processes batch import jobs and emits into the normal capture ingestion topics.
- `webhookS3Sink` consumes `data_warehouse_source_webhooks` and writes webhook payload batches to the configured object storage.
- `ingestionMetrics` runs the Node.js metrics ingestion consumer for the `metrics_ingestion` topic family.
- `recordingRasterizer` runs the dedicated Chromium/ffmpeg recording rasterizer image for video exports and uses the chart's object-storage credentials.

The chart does not include `llmGateway`. Several prominent PostHog AI assistant, Slack, research-agent, and session-summary flows in the current PostHog source cross into `ee.hogai`/`ee.models`; keep those out of this generic FOSS-oriented chart until a self-hosted FOSS runtime path is explicit upstream.

PostHog's `services/mcp` code is not included here as a Kubernetes service. Upstream currently packages that server as a Cloudflare Worker with Durable Objects, while its Dockerfile is only an `mcp-remote` client wrapper to `https://mcp.posthog.com/mcp`. A self-hosted MCP service would need a separate upstream-supported server image or a deliberate port of the Worker runtime to a normal HTTP service.

## ClickHouse

The bundled ClickHouse profile grants the PostHog `app` user full ClickHouse privileges because PostHog migrations create databases, replicated tables, Kafka-engine tables, dictionaries, materialized views, and named-collection based Kafka engines. The migration job runs `SYSTEM FLUSH LOGS` before PostHog migrations so ClickHouse system log tables such as `system.crash_log` exist before PostHog creates materialized views over them. When you use an external ClickHouse service, provision the configured `external.clickhouse.user` with equivalent migration privileges before installing the chart.

## Routing

Ingress and the optional Caddy proxy are generated from `routing.routes`. Add or change public paths there so both surfaces stay aligned.

## Operations

All workload components support the shared scheduling and availability controls:

- Global defaults: `global.nodeSelector`, `global.affinity`, `global.tolerations`, `global.topologySpreadConstraints`, `global.priorityClassName`, and `global.imagePullSecrets`.
- Per-component overrides: the same scheduling fields under `components.<name>`.
- Per-component `autoscaling` creates an `autoscaling/v2` HPA.
- Per-component `pdb` creates a `policy/v1` PodDisruptionBudget.
- Stateful component `persistence` supports `size`, `storageClass`, and `accessModes`.
- `monitoring.serviceMonitor.enabled` creates Prometheus Operator `ServiceMonitor` resources for component ports named in `monitoring.serviceMonitor.portNames`.

Internal component URLs are generated from Helm release-aware service names. Do not hardcode short Docker Compose service names such as `plugins` or `recording-api` in production overrides; use the `posthog.serviceHost`, `posthog.serviceUrl`, and `posthog.temporalAddress` helpers when adding new component env vars.
