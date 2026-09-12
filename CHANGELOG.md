# Changelog

## 0.6.5

- Temporal workers set `TEMPORAL_HEALTH_MAX_IDLE_SECONDS` alongside the health port: upstream starts the health server only when both are set, so the readiness probes added in 0.5.0 never had anything to talk to and the workers stayed unready.

## 0.6.4

- `OIDC_RSA_PRIVATE_KEY` is injected from the chart Secret, generated as a 2048-bit RSA key when not supplied. Outside hobby mode the migrate job provisions OAuth applications and fails without it. Externally managed Secrets should add the key; the env ref is optional so pods still start without it.

## 0.6.3

- The bundled ClickHouse defines all nine Kafka named collections upstream's single-node config defines (`warpstream_shared`, `warpstream_cyclotron`, `warpstream_logs`, `warpstream_traces` and `warpstream_metrics` were missing), so migrations that name them no longer fail.

## 0.6.2

- The app image runs as root again with only the seccomp profile: its Dockerfile ends as root and `bin/docker-server` drops privileges itself with `setpriv`, which fails when the pod already runs as uid 10001. The node image keeps uid 10001.
- The general ingester's cookieless Redis host is left empty whenever the external Redis needs a password, so the Node pool falls back to the authenticated `REDIS_URL` instead of dying on its first command.

## 0.6.1

- `components.<name>.fullnameOverride` names a component's objects directly, so a chart component can take over a StatefulSet and its claims from a subchart the chart used to bundle under a fixed name (the ZooKeeper `data-zookeeper-0` claim, for instance).
- `components.<name>.annotations` is applied to Deployments and StatefulSets, not only Jobs.
- `CLICKHOUSE_OPS_CLUSTER` joins the cluster aliases mapped to the configured cluster; Django defaults it to `ops` and a migration fails without it.
- The app image defaults to the pure-MIT `posthog-foss` build (see 0.6.0 notes).

## 0.6.0

- The app image defaults to `ghcr.io/mayflower/posthog-foss`, a pure-MIT build with the enterprise-licensed `ee/` directory replaced by a shim, pinned to its build commit. Upstream's `ghcr.io/posthog/posthog` bundles code that is only licensed for production with a subscription; set `images.app.repository` back to it if you hold one.
- No Bitnami images remain. Bundled Postgres and ZooKeeper are chart components on the official `postgres` and `zookeeper` images, matching upstream's compose stack; the Bitnami subcharts are removed. Postgres creates the databases in `internal.postgres.extraDatabases` on first start. The ClickHouse operator's CRD hook uses `alpine/k8s` for kubectl, and the optional Kafka UI moved to the maintained `kafbat/kafka-ui` fork.
- The bundled Redis and MinIO subcharts are gone. Valkey (`components.valkey`, StatefulSet with persistence) serves the Redis role and SeaweedFS (`components.objectStorage`) serves general object storage, with buckets and the S3 identity created at startup from `internal.objectStorage.buckets` and the chart's object storage credentials. The CDP shadow store is now `components.valkeyShadow`.
- Bundled installs upgrading from 0.5.0 or earlier get empty stores, Postgres included: dump and restore Postgres, and copy Redis and bucket contents over before switching, or accept starting from scratch.
- `internal.objectStorage.endpoint` and `internal.sessionRecording.endpoint` are templated and now resolve to the chart's own service names; the replay store endpoint previously pointed at a hostname that did not exist.

## 0.5.0

- (Superseded in 0.6.0.) Bundled Postgres, Redis, MinIO and the ClickHouse operator's kubectl hook were pinned to frozen `bitnamilegacy` images; the subchart defaults had drifted to a floating `latest` after Bitnami's catalog change.
- `images.<name>.digest` pins an image by digest and wins over the tag.
- Restricted pod security defaults: seccomp `RuntimeDefault` everywhere, `runAsNonRoot` with the image's numeric uid for the PostHog app, node and Rust images, no ServiceAccount token automount.
- Resource requests on every workload, readiness probes on capture, ingestion, property-defs, PersonHog, cymbal, livestream, Temporal, SeaweedFS and the Temporal workers.
- Opt-in NetworkPolicy (`networkPolicy.enabled`).
- ConfigMap checksums roll the proxy, Temporal and livestream pods on config changes.
- The bundled ClickHouse `api` user's password comes from the chart Secret.
- Failed hook jobs expire after a day (`ttlSecondsAfterFinished`).
- Labels carry `app.kubernetes.io/version` and `part-of`.
- Chart metadata for Artifact Hub, helm-unittest suites, kubeconform in CI, keyless cosign signing on publish.
- Removed: cert-manager, Prometheus, Grafana, Loki and Promtail are no longer chart dependencies. Install them separately.

## 0.4.0

- One Temporal worker per task queue; upstream serves one queue per process.
- Browserless component for exports, subscriptions and screenshots.
- `FEATURE_FLAGS_SERVICE_URL` in the common env, cookieless Redis on the general ingester, capture's exception topic, three missing Kafka topics, bundled data warehouse storage.

## 0.3.0

- Init jobs run post-install and pre-upgrade so fresh installs work; bounded waits; Argo CD hook annotations.
- Generated secrets are preserved across upgrades.
- PersonHog address formats, feature-flags database variables, Cymbal resolution service, Temporal Postgres credentials, separate Valkey shadow store.
- Upstream routing paths, livestream prefix rewrite, AI capture mode and blob offload, SeaweedFS 4.29 with bucket bootstrap.
