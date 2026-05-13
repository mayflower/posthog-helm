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

{{- define "posthog.componentFullname" -}}
{{- printf "%s-%s" (include "posthog.fullname" .root) (include "posthog.componentName" .name) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "posthog.labels" -}}
app.kubernetes.io/name: {{ include "posthog.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
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
{{- $tag := required (printf "images.%s.tag is required" $imageName) $image.tag -}}
{{- if and (not $root.Values.global.allowMutableImageTags) (or (eq $tag "latest") (eq $tag "master")) -}}
{{- fail (printf "images.%s.tag must be immutable unless global.allowMutableImageTags=true" $imageName) -}}
{{- end -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}

{{- define "posthog.postgresHost" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- required "external.postgres.host is required in external mode unless external.postgres.url is set" .Values.external.postgres.host -}}
{{- else -}}
{{- .Values.internal.postgres.host -}}
{{- end -}}
{{- end -}}

{{- define "posthog.postgresUrl" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- if .Values.external.postgres.passwordSecret.name -}}
{{- printf "postgres://%s:$(POSTGRES_PASSWORD)@%s:%v/%s" .Values.external.postgres.user (required "external.postgres.host is required when using external.postgres.passwordSecret" .Values.external.postgres.host) .Values.external.postgres.port .Values.external.postgres.database -}}
{{- else -}}
{{- required "external.postgres.url is required in external mode unless external.postgres.passwordSecret.name is set" .Values.external.postgres.url -}}
{{- end -}}
{{- else -}}
{{- printf "postgres://%s:%s@%s:%v/%s" .Values.internal.postgres.user .Values.internal.postgres.password .Values.internal.postgres.host .Values.internal.postgres.port .Values.internal.postgres.database -}}
{{- end -}}
{{- end -}}

{{- define "posthog.redisHost" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- required "external.redis.host is required in external mode unless external.redis.url is set" .Values.external.redis.host -}}
{{- else -}}
{{- .Values.internal.redis.host -}}
{{- end -}}
{{- end -}}

{{- define "posthog.redisPort" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.redis.port }}{{- else -}}{{ .Values.internal.redis.port }}{{- end -}}
{{- end -}}

{{- define "posthog.redisUrl" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- required "external.redis.url is required in external mode" .Values.external.redis.url -}}
{{- else -}}
{{- printf "redis://%s:%v/" .Values.internal.redis.host .Values.internal.redis.port -}}
{{- end -}}
{{- end -}}

{{- define "posthog.kafkaHosts" -}}
{{- if eq .Values.profile.mode "external" -}}
{{- required "external.kafka.hosts is required in external mode" .Values.external.kafka.hosts -}}
{{- else -}}
{{- .Values.internal.kafka.hosts -}}
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

{{- define "posthog.objectStorageEndpoint" -}}
{{- if eq .Values.profile.mode "external" -}}{{ required "external.objectStorage.endpoint is required in external mode" .Values.external.objectStorage.endpoint }}{{- else -}}{{ .Values.internal.objectStorage.endpoint }}{{- end -}}
{{- end -}}

{{- define "posthog.objectStoragePublicEndpoint" -}}
{{- if eq .Values.profile.mode "external" -}}{{ default .Values.global.siteUrl .Values.external.objectStorage.publicEndpoint }}{{- else -}}{{ default .Values.global.siteUrl .Values.internal.objectStorage.publicEndpoint }}{{- end -}}
{{- end -}}

{{- define "posthog.objectStorageRegion" -}}
{{- if eq .Values.profile.mode "external" -}}{{ .Values.external.objectStorage.region }}{{- else -}}{{ .Values.internal.objectStorage.region }}{{- end -}}
{{- end -}}

{{- define "posthog.sessionRecordingEndpoint" -}}
{{- if eq .Values.profile.mode "external" -}}{{ required "external.sessionRecording.endpoint is required in external mode" .Values.external.sessionRecording.endpoint }}{{- else -}}{{ .Values.internal.sessionRecording.endpoint }}{{- end -}}
{{- end -}}

{{- define "posthog.temporalHost" -}}
{{- if eq .Values.profile.mode "external" -}}{{ required "external.temporal.host is required in external mode" .Values.external.temporal.host }}{{- else -}}{{ .Values.internal.temporal.host }}{{- end -}}
{{- end -}}

{{- define "posthog.commonEnv" -}}
- name: SITE_URL
  value: {{ .Values.global.siteUrl | quote }}
- name: DEPLOYMENT
  value: {{ .Values.global.deployment | quote }}
{{- if and (eq .Values.profile.mode "external") .Values.external.postgres.passwordSecret.name }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "posthog.postgresPasswordSecretName" . }}
      key: {{ include "posthog.postgresPasswordSecretKey" . }}
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
- name: KAFKA_HOSTS
  value: {{ include "posthog.kafkaHosts" . | quote }}
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
- name: OBJECT_STORAGE_ENABLED
  value: "true"
- name: OBJECT_STORAGE_ENDPOINT
  value: {{ include "posthog.objectStorageEndpoint" . | quote }}
- name: OBJECT_STORAGE_PUBLIC_ENDPOINT
  value: {{ include "posthog.objectStoragePublicEndpoint" . | quote }}
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
