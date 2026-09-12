{{- define "posthog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "posthog.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "posthog.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "posthog.componentName" -}}
{{- kebabcase . -}}
{{- end -}}

{{/*
<release>-<chart>-<component>, unless the component sets fullnameOverride.
The override exists so a chart component can take over a StatefulSet and its
claims from a subchart the chart used to bundle under a fixed name.
*/}}
{{- define "posthog.componentFullname" -}}
{{- $override := "" -}}
{{- if hasKey .root.Values.components (toString .name) -}}
{{- $override = default "" (index .root.Values.components (toString .name)).fullnameOverride -}}
{{- end -}}
{{- if $override -}}
{{- $override | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" (include "posthog.fullname" .root) (include "posthog.componentName" .name) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "posthog.serviceHost" -}}
{{- include "posthog.componentFullname" (dict "root" .root "name" .name) -}}
{{- end -}}

{{- define "posthog.serviceUrl" -}}
{{- $scheme := default "http" .scheme -}}
{{- printf "%s://%s:%v" $scheme (include "posthog.serviceHost" (dict "root" .root "name" .name)) .port -}}
{{- end -}}

{{/*
host:port without a scheme. gRPC clients differ on what they accept: the Node
and Python PersonHog clients add the scheme themselves (connect-node builds
`${scheme}://${addr}`, grpc-python takes a bare target), so a URL produces
`http://http://host:port`. The Rust clients go through tonic's
Endpoint::from_shared, which needs the scheme, so they keep serviceUrl.
*/}}
{{- define "posthog.serviceAddress" -}}
{{- printf "%s:%v" (include "posthog.serviceHost" (dict "root" .root "name" .name)) .port -}}
{{- end -}}

{{- define "posthog.labels" -}}
app.kubernetes.io/name: {{ include "posthog.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: posthog
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Pod security context for a component: its own, else the one declared on the
image family it runs (images.<name>.podSecurityContext, which knows the
numeric uid the image switches to), else the chart default.
*/}}
{{- define "posthog.podSecurityContext" -}}
{{- $image := index .root.Values.images .component.image -}}
{{- $ctx := default (default .root.Values.defaultPodSecurityContext $image.podSecurityContext) .component.podSecurityContext -}}
{{- with $ctx }}{{ toYaml . }}{{ end -}}
{{- end -}}

{{- define "posthog.selectorLabels" -}}
app.kubernetes.io/name: {{ include "posthog.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ include "posthog.componentName" .name }}
{{- end -}}

{{- define "posthog.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "posthog.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "posthog.secretName" -}}
{{- default (printf "%s-secrets" (include "posthog.fullname" .)) .Values.secrets.existingSecret -}}
{{- end -}}

{{/*
A generated secret value that survives upgrades. Order: the explicit value
from secrets.values, then whatever the Secret in the cluster already holds,
then a fresh random string. Without the lookup every `helm upgrade` minted a
new SECRET_KEY and ENCRYPTION_SALT_KEYS, which made already-encrypted
integration credentials unreadable and rolled every pod through the
checksum annotation. `helm template` and Argo CD render without cluster
access, so lookup finds nothing there: GitOps installs must supply
secrets.existingSecret or explicit secrets.values.
*/}}
{{- define "posthog.generatedSecretValue" -}}
{{- if .value -}}
{{- .value -}}
{{- else -}}
{{- /* Memoised on .Values for the whole render: secrets.yaml is included
       once per workload for the checksum annotation, and each include must
       see the same values or every checksum differs from the Secret. */ -}}
{{- if not (hasKey .root.Values.secrets "_generated") -}}
{{- $existing := lookup "v1" "Secret" .root.Release.Namespace (include "posthog.secretName" .root) -}}
{{- $data := dict -}}
{{- if $existing -}}{{- $data = default dict $existing.data -}}{{- end -}}
{{- $_ := set .root.Values.secrets "_generated" (dict "existing" $data "minted" dict) -}}
{{- end -}}
{{- $cache := index .root.Values.secrets "_generated" -}}
{{- if hasKey $cache.existing .key -}}
{{- index $cache.existing .key | b64dec -}}
{{- else -}}
{{- if not (hasKey $cache.minted .key) -}}
{{- if .rsa -}}
{{- $_ := set $cache.minted .key (genPrivateKey "rsa") -}}
{{- else -}}
{{- $_ := set $cache.minted .key (randAlphaNum .length) -}}
{{- end -}}
{{- end -}}
{{- index $cache.minted .key -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "posthog.postgresPasswordSecretName" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.postgres.passwordSecret.name -}}
{{- .Values.external.postgres.passwordSecret.name -}}
{{- else -}}
{{- include "posthog.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.postgresPasswordSecretKey" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.postgres.passwordSecret.name -}}
{{- .Values.external.postgres.passwordSecret.key -}}
{{- else -}}
postgres-password
{{- end -}}
{{- end -}}

{{- define "posthog.redisPasswordSecretName" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.redis.passwordSecret.name -}}
{{- .Values.external.redis.passwordSecret.name -}}
{{- else -}}
{{- include "posthog.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.redisPasswordSecretKey" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.redis.passwordSecret.name -}}
{{- .Values.external.redis.passwordSecret.key -}}
{{- else -}}
redis-password
{{- end -}}
{{- end -}}

{{- define "posthog.clickhousePasswordSecretName" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.clickhouse.passwordSecret.name -}}
{{- .Values.external.clickhouse.passwordSecret.name -}}
{{- else -}}
{{- include "posthog.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.clickhousePasswordSecretKey" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.clickhouse.passwordSecret.name -}}
{{- .Values.external.clickhouse.passwordSecret.key -}}
{{- else -}}
{{- .Values.secrets.keys.clickhousePassword -}}
{{- end -}}
{{- end -}}

{{- define "posthog.objectStorageAccessKeySecretName" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.objectStorage.accessKeySecret.name -}}
{{- .Values.external.objectStorage.accessKeySecret.name -}}
{{- else -}}
{{- include "posthog.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.objectStorageAccessKeySecretKey" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.objectStorage.accessKeySecret.name -}}
{{- .Values.external.objectStorage.accessKeySecret.key -}}
{{- else -}}
{{- .Values.secrets.keys.objectStorageAccessKey -}}
{{- end -}}
{{- end -}}

{{- define "posthog.objectStorageSecretKeySecretName" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.objectStorage.secretKeySecret.name -}}
{{- .Values.external.objectStorage.secretKeySecret.name -}}
{{- else -}}
{{- include "posthog.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.objectStorageSecretKeySecretKey" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.objectStorage.secretKeySecret.name -}}
{{- .Values.external.objectStorage.secretKeySecret.key -}}
{{- else -}}
{{- .Values.secrets.keys.objectStorageSecretKey -}}
{{- end -}}
{{- end -}}

{{- define "posthog.sessionRecordingAccessKeySecretName" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.sessionRecording.accessKeySecret.name -}}
{{- .Values.external.sessionRecording.accessKeySecret.name -}}
{{- else -}}
{{- include "posthog.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.sessionRecordingAccessKeySecretKey" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.sessionRecording.accessKeySecret.name -}}
{{- .Values.external.sessionRecording.accessKeySecret.key -}}
{{- else -}}
{{- .Values.secrets.keys.sessionRecordingAccessKey -}}
{{- end -}}
{{- end -}}

{{- define "posthog.sessionRecordingSecretKeySecretName" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.sessionRecording.secretKeySecret.name -}}
{{- .Values.external.sessionRecording.secretKeySecret.name -}}
{{- else -}}
{{- include "posthog.secretName" . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.sessionRecordingSecretKeySecretKey" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.sessionRecording.secretKeySecret.name -}}
{{- .Values.external.sessionRecording.secretKeySecret.key -}}
{{- else -}}
{{- .Values.secrets.keys.sessionRecordingSecretKey -}}
{{- end -}}
{{- end -}}

{{- define "posthog.image" -}}
{{- $root := .root -}}
{{- $imageName := .image -}}
{{- $image := index $root.Values.images $imageName -}}
{{- $repository := required (printf "images.%s.repository is required" $imageName) $image.repository -}}
{{- if $image.digest -}}
{{- printf "%s@%s" $repository $image.digest -}}
{{- else -}}
{{- $tag := required (printf "images.%s.tag or images.%s.digest is required" $imageName $imageName) $image.tag -}}
{{- if and (not $root.Values.global.allowMutableImageTags) (or (eq $tag "latest") (eq $tag "master")) -}}
{{- fail (printf "images.%s.tag is mutable; set global.allowMutableImageTags=true, provide an immutable tag, or set images.%s.digest" $imageName $imageName) -}}
{{- end -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{- define "posthog.postgresHost" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- required "external.postgres.host is required in external mode" .Values.external.postgres.host -}}
{{- else -}}
{{- tpl .Values.internal.postgres.host . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.postgresUser" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.postgres.user }}{{- else -}}{{ .Values.internal.postgres.user }}{{- end -}}
{{- end -}}

{{- define "posthog.postgresPort" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.postgres.port }}{{- else -}}{{ .Values.internal.postgres.port }}{{- end -}}
{{- end -}}

{{/*
The Postgres password as an env value: the literal bundled password, or a
$(POSTGRES_PASSWORD) expansion of the secret commonEnv injects in external
mode. Empty when external mode only has external.postgres.url, because the
password cannot be pulled back out of a URL in a template.
*/}}
{{- define "posthog.postgresPasswordValue" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- if .Values.external.postgres.passwordSecret.name -}}$(POSTGRES_PASSWORD){{- end -}}
{{- else -}}
{{- .Values.internal.postgres.password -}}
{{- end -}}
{{- end -}}

{{- define "posthog.postgresUrlQuery" -}}
{{- $params := dict -}}
{{- if .Values.external.postgres.sslMode -}}
{{- $_ := set $params "sslmode" .Values.external.postgres.sslMode -}}
{{- end -}}
{{- range $key, $value := .Values.external.postgres.params -}}
{{- $_ := set $params $key $value -}}
{{- end -}}
{{- if $params -}}
{{- $pairs := list -}}
{{- range $key, $value := $params -}}
{{- $pairs = append $pairs (printf "%s=%s" $key (toString $value | urlquery)) -}}
{{- end -}}
{{- printf "?%s" (join "&" $pairs) -}}
{{- end -}}
{{- end -}}

{{- define "posthog.postgresUrl" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- if .Values.external.postgres.passwordSecret.name -}}
{{- printf "postgres://%s:$(POSTGRES_PASSWORD)@%s:%v/%s%s" .Values.external.postgres.user (required "external.postgres.host is required when using external.postgres.passwordSecret" .Values.external.postgres.host) .Values.external.postgres.port .Values.external.postgres.database (include "posthog.postgresUrlQuery" .) -}}
{{- else -}}
{{- required "external.postgres.url is required in external mode unless external.postgres.passwordSecret.name is set" .Values.external.postgres.url -}}
{{- end -}}
{{- else -}}
{{- printf "postgres://%s:%s@%s:%v/%s" .Values.internal.postgres.user .Values.internal.postgres.password (tpl .Values.internal.postgres.host .) .Values.internal.postgres.port .Values.internal.postgres.database -}}
{{- end -}}
{{- end -}}

{{- define "posthog.redisHost" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- required "external.redis.host is required in external mode" .Values.external.redis.host -}}
{{- else -}}
{{- tpl .Values.internal.redis.host . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.redisPort" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.redis.port }}{{- else -}}{{ .Values.internal.redis.port }}{{- end -}}
{{- end -}}

{{- define "posthog.redisDatabase" -}}
{{- if eq .Values.profile.mode "external" -}}{{ default 0 .Values.external.redis.database }}{{- else -}}{{ default 0 .Values.internal.redis.database }}{{- end -}}
{{- end -}}

{{- define "posthog.redisTls" -}}
{{- if eq .Values.profile.mode "external" -}}{{ ternary "true" "false" (default false .Values.external.redis.tls) }}{{- else -}}{{ ternary "true" "false" (default false .Values.internal.redis.tls) }}{{- end -}}
{{- end -}}

{{/*
Host for Redis pools that take no password: empty when Redis needs one, so
the client falls back to REDIS_URL, which carries it.
*/}}
{{- define "posthog.cookielessRedisHost" -}}
{{- if and (eq .Values.profile.mode "external") (or .Values.external.redis.passwordSecret.name .Values.external.redis.url) -}}{{- else -}}{{ include "posthog.redisHost" . }}{{- end -}}
{{- end -}}

{{- define "posthog.redisPasswordEnv" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.redis.passwordSecret.name -}}$(REDIS_PASSWORD){{- end -}}
{{- end -}}

{{- define "posthog.redisUrl" -}}
{{- $scheme := ternary "rediss" "redis" (eq (include "posthog.redisTls" .) "true") -}}
{{- if eq .Values.profile.mode "external" -}}
{{- if .Values.external.redis.url -}}
{{- .Values.external.redis.url -}}
{{- else if .Values.external.redis.passwordSecret.name -}}
{{- printf "%s://:$(REDIS_PASSWORD)@%s:%v/%v" $scheme (required "external.redis.host is required when using external.redis.passwordSecret" .Values.external.redis.host) .Values.external.redis.port (default 0 .Values.external.redis.database) -}}
{{- else -}}
{{- printf "%s://%s:%v/%v" $scheme (required "external.redis.host is required in external mode" .Values.external.redis.host) .Values.external.redis.port (default 0 .Values.external.redis.database) -}}
{{- end -}}
{{- else -}}
{{- printf "%s://%s:%v/%v" $scheme (tpl .Values.internal.redis.host .) .Values.internal.redis.port (default 0 .Values.internal.redis.database) -}}
{{- end -}}
{{- end -}}

{{/*
The CDP shadow store. Every CDP process dual-writes to it, and the rate
limiters and hog watcher run the same token-bucket calls against both stores,
so it must not be the main Redis: pointed at one instance the same keys get
charged twice. External mode uses external.valkey when set and otherwise
falls back to the bundled component.
*/}}
{{- define "posthog.valkeyHost" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.valkey.host -}}{{ .Values.external.valkey.host }}{{- else -}}{{ tpl .Values.internal.valkey.host . }}{{- end -}}
{{- end -}}

{{- define "posthog.valkeyPort" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.valkey.host -}}{{ .Values.external.valkey.port }}{{- else -}}{{ .Values.internal.valkey.port }}{{- end -}}
{{- end -}}

{{- define "posthog.valkeyTls" -}}
{{- if and (eq .Values.profile.mode "external") .Values.external.valkey.host -}}{{ ternary "true" "false" (default false .Values.external.valkey.tls) }}{{- else -}}false{{- end -}}
{{- end -}}

{{- define "posthog.kafkaHosts" -}}
{{- if .Values.external.kafka.hosts -}}
{{- .Values.external.kafka.hosts -}}
{{- else if .Values.internal.kafka.hosts -}}
{{- .Values.internal.kafka.hosts -}}
{{- else -}}
{{- fail "either external.kafka.hosts or internal.kafka.hosts is required" -}}
{{- end -}}
{{- end -}}

{{- define "posthog.clickhouseHost" -}}
{{- if eq .Values.profile.mode "external" -}}{{ required "external.clickhouse.host is required in external mode" .Values.external.clickhouse.host }}{{- else -}}{{ .Values.internal.clickhouse.host }}{{- end -}}
{{- end -}}

{{- define "posthog.clickhouseDatabase" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.clickhouse.database }}{{- else -}}{{ .Values.internal.clickhouse.database }}{{- end -}}
{{- end -}}

{{- define "posthog.clickhouseUser" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.clickhouse.user }}{{- else -}}{{ .Values.internal.clickhouse.user }}{{- end -}}
{{- end -}}

{{- define "posthog.clickhouseSecure" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.clickhouse.secure }}{{- else -}}{{ .Values.internal.clickhouse.secure }}{{- end -}}
{{- end -}}

{{- define "posthog.clickhouseVerify" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.clickhouse.verify }}{{- else -}}{{ .Values.internal.clickhouse.verify }}{{- end -}}
{{- end -}}

{{- define "posthog.clickhouseCluster" -}}
{{- $configured := "" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- $configured = default "" .Values.external.clickhouse.cluster -}}
{{- else -}}
{{- $configured = default "" .Values.internal.clickhouse.cluster -}}
{{- end -}}
{{- if $configured -}}
{{- $configured -}}
{{- else if .Values.clickhouse.enabled -}}
{{- .Values.clickhouse.clusterName -}}
{{- end -}}
{{- end -}}

{{- define "posthog.clickhouseMigrationsCluster" -}}
{{- $configured := "" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- $configured = default "" .Values.external.clickhouse.migrationsCluster -}}
{{- else -}}
{{- $configured = default "" .Values.internal.clickhouse.migrationsCluster -}}
{{- end -}}
{{- if $configured -}}
{{- $configured -}}
{{- else -}}
{{- include "posthog.clickhouseCluster" . -}}
{{- end -}}
{{- end -}}

{{- define "posthog.objectStorageEndpoint" -}}
{{- if eq .Values.profile.mode "external" -}}{{ required "external.objectStorage.endpoint is required in external mode" .Values.external.objectStorage.endpoint }}{{- else -}}{{ tpl .Values.internal.objectStorage.endpoint . }}{{- end -}}
{{- end -}}

{{- define "posthog.objectStoragePublicEndpoint" -}}
{{- if eq .Values.profile.mode "external" -}}{{ default .Values.global.siteUrl .Values.external.objectStorage.publicEndpoint }}{{- else -}}{{ default .Values.global.siteUrl .Values.internal.objectStorage.publicEndpoint }}{{- end -}}
{{- end -}}

{{- define "posthog.objectStorageBucket" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.objectStorage.bucket }}{{- else -}}{{ .Values.internal.objectStorage.bucket }}{{- end -}}
{{- end -}}

{{- define "posthog.sessionRecordingBucket" -}}
{{- if eq .Values.profile.mode "external" -}}{{ default "posthog" .Values.external.sessionRecording.bucket }}{{- else -}}{{ default "posthog" .Values.internal.sessionRecording.bucket }}{{- end -}}
{{- end -}}

{{- define "posthog.sessionRecordingRegion" -}}
{{- if eq .Values.profile.mode "external" -}}{{ default "us-east-1" .Values.external.sessionRecording.region }}{{- else -}}{{ default "us-east-1" .Values.internal.sessionRecording.region }}{{- end -}}
{{- end -}}

{{- define "posthog.objectStorageRegion" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.objectStorage.region }}{{- else -}}{{ .Values.internal.objectStorage.region }}{{- end -}}
{{- end -}}

{{- define "posthog.sessionRecordingEndpoint" -}}
{{- if eq .Values.profile.mode "external" -}}{{ required "external.sessionRecording.endpoint is required in external mode" .Values.external.sessionRecording.endpoint }}{{- else -}}{{ tpl .Values.internal.sessionRecording.endpoint . }}{{- end -}}
{{- end -}}

{{- define "posthog.temporalHost" -}}
{{- if eq .Values.profile.mode "external" -}}{{ tpl (required "external.temporal.host is required in external mode" .Values.external.temporal.host) . }}{{- else -}}{{ tpl .Values.internal.temporal.host . }}{{- end -}}
{{- end -}}

{{- define "posthog.temporalPort" -}}
{{- if eq .Values.profile.mode "external" -}}{{ default 7233 .Values.external.temporal.port }}{{- else -}}{{ default 7233 .Values.internal.temporal.port }}{{- end -}}
{{- end -}}

{{- define "posthog.temporalAddress" -}}
{{- printf "%s:%v" (include "posthog.temporalHost" .) (include "posthog.temporalPort" .) -}}
{{- end -}}

{{- define "posthog.opensearchHost" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.opensearch.host }}{{- else -}}{{ tpl .Values.internal.opensearch.host . }}{{- end -}}
{{- end -}}

{{- define "posthog.opensearchUrl" -}}
{{- $host := include "posthog.opensearchHost" . -}}
{{- if $host -}}
{{- if hasPrefix "http" $host -}}{{ $host }}{{- else -}}{{ printf "http://%s" $host }}{{- end -}}
{{- end -}}
{{- end -}}

{{- define "posthog.commonEnv" -}}
- name: SITE_URL
  value: {{ .Values.global.siteUrl | quote }}
- name: DEPLOYMENT
  value: {{ .Values.global.deployment | quote }}
- name: HOME
  value: /tmp
- name: MPLCONFIGDIR
  value: /tmp/matplotlib
{{- if and (eq .Values.profile.mode "external") .Values.external.postgres.passwordSecret.name }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.postgresPasswordSecretName" . }}
      key: {{ include "posthog.postgresPasswordSecretKey" . }}
{{- end }}
{{- if and (eq .Values.profile.mode "external") .Values.external.redis.passwordSecret.name }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.redisPasswordSecretName" . }}
      key: {{ include "posthog.redisPasswordSecretKey" . }}
{{- end }}
- name: SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" . }}
      key: {{ .Values.secrets.keys.secretKey }}
- name: ENCRYPTION_SALT_KEYS
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" . }}
      key: {{ .Values.secrets.keys.encryptionSaltKeys }}
- name: CAPTURE_LOGS_JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" . }}
      key: {{ .Values.secrets.keys.captureLogsJwtSecret }}
- name: LIVESTREAM_JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" . }}
      key: {{ .Values.secrets.keys.livestreamJwtSecret }}
{{- with (default .Values.secrets.recordingApiJwtSecret .Values.secrets.keys.recordingApiJwtSecret) }}
- name: RECORDING_API_JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" $ }}
      key: {{ . }}
{{- end }}
- name: INTERNAL_API_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" . }}
      key: {{ .Values.secrets.keys.internalApiSecret }}
# Optional so an externally managed Secret without the key still starts;
# the migrate job then fails at setup_tasks_oauth outside hobby mode.
- name: OIDC_RSA_PRIVATE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" . }}
      key: {{ .Values.secrets.keys.oidcRsaPrivateKey }}
      optional: true
- name: DATABASE_URL
  value: {{ include "posthog.postgresUrl" . | quote }}
- name: PERSONS_DATABASE_URL
  value: {{ include "posthog.postgresUrl" . | quote }}
- name: BEHAVIORAL_COHORTS_DATABASE_URL
  value: {{ include "posthog.postgresUrl" . | quote }}
- name: PGHOST
  value: {{ include "posthog.postgresHost" . | quote }}
- name: REDIS_URL
  value: {{ include "posthog.redisUrl" . | quote }}
- name: POSTHOG_REDIS_HOST
  value: {{ include "posthog.redisHost" . | quote }}
- name: POSTHOG_REDIS_PORT
  value: {{ include "posthog.redisPort" . | quote }}
{{- if and (eq .Values.profile.mode "external") .Values.external.redis.passwordSecret.name }}
- name: POSTHOG_REDIS_PASSWORD
  value: "$(REDIS_PASSWORD)"
- name: CDP_REDIS_PASSWORD
  value: "$(REDIS_PASSWORD)"
- name: LOGS_REDIS_PASSWORD
  value: "$(REDIS_PASSWORD)"
- name: TRACES_REDIS_PASSWORD
  value: "$(REDIS_PASSWORD)"
{{- end }}
{{- if and (eq .Values.profile.mode "external") .Values.external.valkey.host .Values.external.valkey.passwordSecret.name }}
- name: CDP_VALKEY_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.external.valkey.passwordSecret.name }}
      key: {{ .Values.external.valkey.passwordSecret.key }}
{{- end }}
- name: KAFKA_HOSTS
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_CONSUMER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_DEFAULT_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_INGESTION_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_WARPSTREAM_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_WARPSTREAM_INGESTION_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_WARPSTREAM_LOGS_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_WAREHOUSE_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_WARPSTREAM_CALCULATED_EVENTS_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: KAFKA_WARPSTREAM_CYCLOTRON_PRODUCER_METADATA_BROKER_LIST
  value: {{ include "posthog.kafkaHosts" . | quote }}
- name: CDP_API_URL
  value: {{ include "posthog.serviceUrl" (dict "root" . "name" "plugins" "port" 6738) | quote }}
# Django defaults this to localhost:3001; cohort, user, flag and dashboard
# endpoints call it for flag definitions and local evaluation.
- name: FEATURE_FLAGS_SERVICE_URL
  value: {{ include "posthog.serviceUrl" (dict "root" . "name" "featureFlags" "port" 3001) | quote }}
{{- if .Values.components.browserless.enabled }}
# Image exports raise without a CDP URL; heatmap screenshots use the HTTP one.
# The token refs are optional so an externally managed Secret without the key
# still lets every pod start; exports then fail with an auth error instead.
- name: BROWSERLESS_CDP_URL
  value: {{ printf "ws://%s:3000" (include "posthog.serviceHost" (dict "root" . "name" "browserless")) | quote }}
- name: HEATMAP_BROWSERLESS_URL
  value: {{ include "posthog.serviceUrl" (dict "root" . "name" "browserless" "port" 3000) | quote }}
- name: BROWSERLESS_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" . }}
      key: {{ .Values.secrets.keys.browserlessToken }}
      optional: true
- name: HEATMAP_BROWSERLESS_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.secretName" . }}
      key: {{ .Values.secrets.keys.browserlessToken }}
      optional: true
{{- end }}
{{- if eq .Values.profile.mode "bundled" }}
# Data warehouse and data modeling. Outside debug mode Django assumes real
# AWS S3 for the warehouse bucket; USE_LOCAL_SETUP routes it through the
# bundled object store with these credentials instead.
- name: USE_LOCAL_SETUP
  value: "true"
- name: DATAWAREHOUSE_BUCKET
  value: {{ .Values.internal.objectStorage.dataWarehouseBucket | quote }}
- name: BUCKET_URL
  value: {{ printf "s3://%s" .Values.internal.objectStorage.dataWarehouseBucket | quote }}
- name: BUCKET_PATH
  value: {{ .Values.internal.objectStorage.dataWarehouseBucket | quote }}
- name: DATAWAREHOUSE_BUCKET_DOMAIN
  value: {{ include "posthog.objectStorageEndpoint" . | trimPrefix "http://" | trimPrefix "https://" | quote }}
- name: DATAWAREHOUSE_LOCAL_BUCKET_REGION
  value: {{ .Values.internal.objectStorage.region | quote }}
- name: DATAWAREHOUSE_LOCAL_ACCESS_KEY
  value: "$(OBJECT_STORAGE_ACCESS_KEY_ID)"
- name: DATAWAREHOUSE_LOCAL_ACCESS_SECRET
  value: "$(OBJECT_STORAGE_SECRET_ACCESS_KEY)"
{{- end }}
# Must match where the node image actually carries the database. The plugin
# server and the error-tracking consumer abort with ENOENT if it is missing, and
# there is no switch to run without GeoIP -- only MMDB_FILE_LOCATION and
# MMDB_LOAD_TIMEOUT_MS exist. Overridable because the path has moved between
# image builds; overriding it per component instead would produce a duplicate
# env entry, which the API server rejects.
- name: MMDB_FILE_LOCATION
  value: {{ .Values.mmdbFileLocation | default "/app/share/GeoLite2-City.mmdb" | quote }}
- name: TEMPORAL_HOST
  value: {{ include "posthog.temporalHost" . | quote }}
- name: TEMPORAL_PORT
  value: {{ include "posthog.temporalPort" . | quote }}
{{- with (include "posthog.opensearchUrl" .) }}
- name: OPENSEARCH_URL
  value: {{ . | quote }}
- name: OPENSEARCH_HOSTS
  value: {{ . | quote }}
{{- end }}
- name: CLICKHOUSE_HOST
  value: {{ include "posthog.clickhouseHost" . | quote }}
- name: CLICKHOUSE_DATABASE
  value: {{ include "posthog.clickhouseDatabase" . | quote }}
- name: CLICKHOUSE_USER
  value: {{ include "posthog.clickhouseUser" . | quote }}
- name: CLICKHOUSE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.clickhousePasswordSecretName" . }}
      key: {{ include "posthog.clickhousePasswordSecretKey" . }}
- name: CLICKHOUSE_SECURE
  value: {{ include "posthog.clickhouseSecure" . | quote }}
- name: CLICKHOUSE_VERIFY
  value: {{ include "posthog.clickhouseVerify" . | quote }}
{{- with (include "posthog.clickhouseMigrationsCluster" .) }}
- name: CLICKHOUSE_CLUSTER
  value: {{ . | quote }}
- name: CLICKHOUSE_MIGRATIONS_CLUSTER
  value: {{ . | quote }}
- name: CLICKHOUSE_SINGLE_SHARD_CLUSTER
  value: {{ . | quote }}
- name: CLICKHOUSE_WRITABLE_CLUSTER
  value: {{ . | quote }}
- name: CLICKHOUSE_PRIMARY_REPLICA_CLUSTER
  value: {{ . | quote }}
- name: CLICKHOUSE_AUX_CLUSTER
  value: {{ . | quote }}
- name: CLICKHOUSE_AI_EVENTS_CLUSTER
  value: {{ . | quote }}
- name: CLICKHOUSE_LOGS_CLUSTER
  value: {{ . | quote }}
# Django defaults this to "ops" for query_log_archive; a migration fails with
# "Requested cluster 'ops' not found" unless it maps to a real cluster.
- name: CLICKHOUSE_OPS_CLUSTER
  value: {{ . | quote }}
{{- end }}
- name: CLICKHOUSE_SATELLITE_CLUSTERS
  value: {{ .Values.clickhouse.satelliteClusters | quote }}
- name: CLICKHOUSE_LOGS_CLUSTER_HOST
  value: {{ include "posthog.clickhouseHost" . | quote }}
- name: CLICKHOUSE_LOGS_CLUSTER_DATABASE
  value: {{ include "posthog.clickhouseDatabase" . | quote }}
- name: CLICKHOUSE_LOGS_CLUSTER_USER
  value: {{ include "posthog.clickhouseUser" . | quote }}
- name: CLICKHOUSE_LOGS_CLUSTER_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.clickhousePasswordSecretName" . }}
      key: {{ include "posthog.clickhousePasswordSecretKey" . }}
- name: CLICKHOUSE_LOGS_CLUSTER_SECURE
  value: {{ include "posthog.clickhouseSecure" . | quote }}
- name: CLICKHOUSE_LOGS_CLUSTER_VERIFY
  value: {{ include "posthog.clickhouseVerify" . | quote }}
- name: OBJECT_STORAGE_ENABLED
  value: "true"
- name: OBJECT_STORAGE_ENDPOINT
  value: {{ include "posthog.objectStorageEndpoint" . | quote }}
- name: OBJECT_STORAGE_PUBLIC_ENDPOINT
  value: {{ include "posthog.objectStoragePublicEndpoint" . | quote }}
- name: OBJECT_STORAGE_BUCKET
  value: {{ include "posthog.objectStorageBucket" . | quote }}
- name: OBJECT_STORAGE_REGION
  value: {{ include "posthog.objectStorageRegion" . | quote }}
- name: OBJECT_STORAGE_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.objectStorageAccessKeySecretName" . }}
      key: {{ include "posthog.objectStorageAccessKeySecretKey" . }}
- name: OBJECT_STORAGE_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.objectStorageSecretKeySecretName" . }}
      key: {{ include "posthog.objectStorageSecretKeySecretKey" . }}
- name: SESSION_RECORDING_V2_S3_ENDPOINT
  value: {{ include "posthog.sessionRecordingEndpoint" . | quote }}
- name: SESSION_RECORDING_V2_S3_BUCKET
  value: {{ include "posthog.sessionRecordingBucket" . | quote }}
- name: SESSION_RECORDING_V2_S3_REGION
  value: {{ include "posthog.sessionRecordingRegion" . | quote }}
- name: SESSION_RECORDING_V2_S3_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.sessionRecordingAccessKeySecretName" . }}
      key: {{ include "posthog.sessionRecordingAccessKeySecretKey" . }}
- name: SESSION_RECORDING_V2_S3_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.sessionRecordingSecretKeySecretName" . }}
      key: {{ include "posthog.sessionRecordingSecretKeySecretKey" . }}
- name: IS_BEHIND_PROXY
  value: "true"
- name: DISABLE_SECURE_SSL_REDIRECT
  value: "true"
{{- end -}}

{{- define "posthog.renderEnvMap" -}}
{{- $root := .root -}}
{{- range $name, $value := .env }}
- name: {{ $name }}
  value: {{ tpl (toString $value) $root | quote }}
{{- end }}
{{- end -}}
