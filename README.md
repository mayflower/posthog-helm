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

## Profiles

- `profile.mode=bundled` deploys PostHog plus bundled backing services through maintained subcharts where practical. Use it for non-production evaluation.
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
  --version 0.2.29 \
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
  --version 0.2.29 \
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
| PostgreSQL | `external.postgres.*` | Reachable from the namespace. The configured user must own or be able to migrate the configured database. The chart currently uses the same Postgres URL for `DATABASE_URL`, `PERSONS_DATABASE_URL`, and `BEHAVIORAL_COHORTS_DATABASE_URL`. |
| Redis | `external.redis.*` | Reachable Redis endpoint. Use `external.redis.passwordSecret` for password auth, or remove it if your endpoint has no password. Set `external.redis.tls=true` only for TLS-enabled Redis endpoints. |
| Kafka or Redpanda | `external.kafka.hosts` or bundled Redpanda | Plain Kafka bootstrap string by default. If you need SASL/TLS, add the required PostHog env vars under the affected `components.*.extraEnv` and manage topics externally unless `rpk` can connect with the same settings. |
| ClickHouse | `external.clickhouse.*` | The configured user needs enough privileges for PostHog migrations: database/table creation, materialized views, dictionaries, Kafka-engine tables, named collections, and `SYSTEM FLUSH LOGS`. Set `cluster`/`migrationsCluster` when using replicated clusters. |
| Object storage | `external.objectStorage.*` | S3-compatible endpoint and bucket for general object storage. Create the bucket before installing when the provider does not auto-create buckets. |
| Session recording storage | `external.sessionRecording.*` | S3-compatible endpoint and credentials for replay payloads. This can share the same provider/secret as object storage, but keep a separate bucket or prefix operationally. |
| Temporal | `external.temporal.*`, `components.temporal.enabled` | Existing Temporal frontend endpoint, or the bundled Temporal component with `external.temporal.host` pointing at the chart service. Disable `components.temporal` only when you provide managed Temporal. |
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

The `kafkaInit` job creates the topics in `kafka.topics` before migrations and workloads start. It uses Redpanda's `rpk` CLI against `KAFKA_HOSTS`.

Use the built-in topic job only when `rpk topic list --brokers "$KAFKA_HOSTS"` and `rpk topic create ...` work from inside the cluster without extra SASL/TLS flags. For managed Kafka, pre-create topics yourself and disable the job:

```yaml
components:
  kafkaInit:
    enabled: false
```

Keep `kafka.defaultPartitions` and `kafka.defaultReplicationFactor` aligned with your broker policy when the chart creates topics. Override `kafka.topics` when you use custom PostHog topic names or broker-side topic management.

## Ingress, DNS, and TLS

`global.siteUrl` must be the externally reachable PostHog URL. Event capture, feature flags, session recording, and redirects depend on it. `ingress.host` defaults to `global.domain` when omitted.

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

```bash
helm lint --strict .
helm template posthog . > /tmp/posthog.yaml
helm template posthog . -f ./examples/external-values.yaml > /tmp/posthog-external.yaml
helm template posthog oci://ghcr.io/mayflower/posthog-helm/posthog \
  --version 0.2.29 \
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
