# PostHog Helm Chart

This chart is a clean v1 Kubernetes chart for the current PostHog service topology in the sibling `posthog` source tree.

It intentionally does not preserve the old [`PostHog/charts-clickhouse`](https://github.com/PostHog/charts-clickhouse) values API. That repository is useful historical context, but its dependency stack and workload split are outdated. PostHog also published the background for ending official chart support in [Sunsetting Helm support for self-hosted PostHog](https://posthog.com/blog/sunsetting-helm-support-posthog).

The PostHog-owned runtime images follow the upstream container defaults and use the mutable `master` tag by default. `global.imagePullPolicy` defaults to `Always` so Kubernetes refreshes those images on rollout. Override `images.*.tag` in production when you need a controlled rollout.

## Profiles

- `profile.mode=bundled` deploys PostHog plus bundled backing services through maintained subcharts where practical.
- `profile.mode=external` deploys PostHog workloads and requires managed Postgres, Redis, Kafka/Redpanda, ClickHouse, object storage, session recording storage, and Temporal endpoints.

## Install

Install the bundled profile for a non-production evaluation:

```bash
helm upgrade --install posthog . \
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
