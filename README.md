# PostHog Helm Chart

This chart is a clean v1 Kubernetes chart for the current PostHog compose-era service topology in the sibling `posthog` source tree.

It intentionally does not preserve the old `PostHog/charts-clickhouse` values API. That repository is useful historical context, but its dependency stack and workload split are outdated.

The default PostHog image tag is pinned to the local source snapshot `696b444135bb`. Mutable tags such as `master` and `latest` are rejected by default; use `global.allowMutableImageTags=true` only for development.

## Profiles

- `profile.mode=bundled` deploys PostHog plus bundled backing services through maintained subcharts where practical.
- `profile.mode=external` deploys PostHog workloads and requires managed Postgres, Redis, Kafka/Redpanda, ClickHouse, object storage, session recording storage, and Temporal endpoints.

## Common Commands

Dependencies are vendored as unpacked chart directories because Helm 4 linting expects directories, while `helm dependency update` writes archives.

```bash
helm lint --strict .
helm template posthog . > /tmp/posthog.yaml
helm template posthog . -f ./examples/external-values.yaml > /tmp/posthog-external.yaml
helm template posthog . -f ./examples/full-compose-values.yaml > /tmp/posthog-full.yaml
```

To refresh dependencies:

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
    database: posthog
    user: posthog
    passwordSecret:
      name: posthog-postgres
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

When `external.postgres.passwordSecret.name` is set, the chart builds `DATABASE_URL` from host/user/database and injects `POSTGRES_PASSWORD` from that secret. This avoids putting database passwords in values files.

## Routing

Ingress and the optional Caddy proxy are generated from `routing.routes`. Add or change public paths there so both surfaces stay aligned.

## Operations

All workload components support the shared scheduling and availability controls:

- Global defaults: `global.nodeSelector`, `global.affinity`, `global.tolerations`, `global.topologySpreadConstraints`, `global.priorityClassName`, and `global.imagePullSecrets`.
- Per-component overrides: the same scheduling fields under `components.<name>`.
- Per-component `autoscaling` creates an `autoscaling/v2` HPA.
- Per-component `pdb` creates a `policy/v1` PodDisruptionBudget.
- Stateful component `persistence` supports `size`, `storageClass`, and `accessModes`.

## Compose Coverage

The chart models the runtime services from the hobby/base stack and exposes the dev/full compose support services as disabled components in `examples/full-compose-values.yaml`.

The following compose entries are intentionally not rendered as first-class Kubernetes workloads:

- `app` from `docker-compose.sandbox.yml`: a local devcontainer/IDE sandbox, not a deployable PostHog runtime service.
- `playwright` from `docker-compose.playwright.yml`: a local test runner with host-network and source mounts.
- `clickhouse-coordinator` from `docker-compose.dev-coordinator.yml`: a local multi-node ClickHouse development topology; production ClickHouse should be supplied by the operator or a managed/external cluster.
- `redis-cluster` from dev compose: a single-container local Redis cluster shim for tests; production Redis clustering should be handled by the Redis provider/chart.
- `opensearch-init` from dev compose: a profile-specific bootstrap helper tied to source-tree files; carry it as a site-specific Job when enabling that OpenSearch profile.
