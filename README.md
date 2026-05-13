# PostHog Helm Chart

This chart is a clean v1 Kubernetes chart for the current PostHog service topology in the sibling `posthog` source tree.

It intentionally does not preserve the old [`PostHog/charts-clickhouse`](https://github.com/PostHog/charts-clickhouse) values API. That repository is useful historical context, but its dependency stack and workload split are outdated. PostHog also published the background for ending official chart support in [Sunsetting Helm support for self-hosted PostHog](https://posthog.com/blog/sunsetting-helm-support-posthog).

The PostHog-owned runtime images follow the upstream container defaults and use the mutable `master` tag by default. `global.imagePullPolicy` defaults to `Always` so Kubernetes refreshes those images on rollout. Override `images.*.tag` in production when you need a controlled rollout.

## Profiles

- `profile.mode=bundled` deploys PostHog plus bundled backing services through maintained subcharts where practical.
- `profile.mode=external` deploys PostHog workloads and uses managed dependencies where configured. Kafka can still use the bundled Redpanda subchart by leaving `external.kafka.hosts` empty and enabling `subcharts.redpanda.enabled`.

## Install

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
  --version 0.2.12 \
  --namespace posthog \
  --create-namespace \
  --set global.domain=posthog.example.com \
  --set global.siteUrl=https://posthog.example.com
```

For production, use external backing services and provide runtime secrets before installing:

```bash
kubectl create namespace posthog
kubectl -n posthog create secret generic posthog-runtime-secrets \
  --from-literal=SECRET_KEY='<replace-me>' \
  --from-literal=ENCRYPTION_SALT_KEYS='<replace-me>' \
  --from-literal=CAPTURE_LOGS_JWT_SECRET='<replace-me>' \
  --from-literal=LIVESTREAM_JWT_SECRET='<replace-me>'

helm upgrade --install posthog . \
  --namespace posthog \
  -f ./examples/external-values.yaml
```

The external example expects separate provider-managed secrets for Postgres, ClickHouse, object storage, and session recording credentials. Update `examples/external-values.yaml` with your service endpoints and secret names before running the install.

## Validate

Dependencies are vendored as unpacked chart directories because Helm 4 linting expects directories, while `helm dependency update` writes archives.

```bash
helm lint --strict .
helm template posthog . > /tmp/posthog.yaml
helm template posthog . -f ./examples/external-values.yaml > /tmp/posthog-external.yaml
```

Refresh dependencies after changing `Chart.yaml` dependency versions:

```bash
helm dependency update .
for archive in ./charts/*.tgz; do tar -xzf "$archive" -C ./charts; done
rm ./charts/*.tgz
```

## Runtime Secrets

For production, create a runtime secret and set `secrets.existingSecret`. The secret must contain:

- `SECRET_KEY`
- `ENCRYPTION_SALT_KEYS`
- `CAPTURE_LOGS_JWT_SECRET`
- `LIVESTREAM_JWT_SECRET`

It must also contain these keys when you do not configure the provider-specific external secret refs below:

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

When `external.postgres.passwordSecret.name` is set, the chart builds `DATABASE_URL` from host/user/database, appends `sslmode`/`params`, and injects `POSTGRES_PASSWORD` from that secret. When `external.redis.passwordSecret.name` is set, the chart injects `REDIS_PASSWORD` and builds Redis URLs with Kubernetes env expansion. This avoids putting service passwords in values files.

## Kafka Topics

The `kafkaInit` hook creates the topics PostHog services expect before migrations and workloads start. The default list is exposed as `kafka.topics`; override it when you run with a custom PostHog Kafka prefix or a broker policy that manages topics separately.

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
