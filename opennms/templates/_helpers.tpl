{{/*
Expand the name of the chart.
*/}}
{{- define "opennms.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "opennms.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "opennms.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "opennms.labels" -}}
helm.sh/chart: {{ include "opennms.chart" . }}
{{ include "opennms.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "opennms.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opennms.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "opennms.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "opennms.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Define custom content for JVM_OPTS to conditionally handle Truststores
*/}}
{{- define "opennms.jvmOptions" -}}
  {{- $common := "-XX:+AlwaysPreTouch -XX:+UseG1GC -XX:+UseStringDeduplication" }}
  {{- if and .Values.dependencies.truststore .Values.dependencies.truststore.content }}
    {{- $truststore := "-Djavax.net.ssl.trustStore=/etc/java/jks/truststore.jks" }}
    {{- $password := "" }}
    {{- if .Values.dependencies.truststore.password }}
      {{- $password = "-Djavax.net.ssl.trustStorePassword=$(TRUSTSTORE_PASSWORD)" }}
    {{- end }}
    {{- printf "%s %s %s" $common $truststore $password }}
  {{- else -}}
    {{- $common }}
  {{- end }}
{{- end }}

{{/*
Define whether RRD is enabled
*/}}
{{- define "opennms.enable_tss_rrd" -}}
  {{ or (not .Values.opennms.configuration.enable_cortex) .Values.opennms.configuration.enable_tss_dual_write -}}
{{- end }}

{{/*
Define common content for Grafana Promtail
*/}}
{{- define "opennms.promtailBaseConfig" -}}
{{- $scheme := "http" -}}
{{- if ((.Values.dependencies).loki).ca_cert -}}
  {{- $scheme := "https" -}}
{{- end -}}
server:
  http_listen_port: 9080
  grpc_listen_port: 0
clients:
- tenant_id: {{ .Release.Name }}
  url: {{ printf "%s://%s:%d/loki/api/v1/push" $scheme ((.Values.dependencies).loki).hostname (((.Values.dependencies).loki).port | int) }}
  {{- if and ((.Values.dependencies).loki).username ((.Values.dependencies).loki).password }}
  basic_auth:
    username: {{ .Values.dependencies.loki.username }}
    password: {{ .Values.dependencies.loki.password }}
  {{- end }}
  {{- if ((.Values.dependencies).loki).ca_cert }}
  tls_config:
    ca_file: /etc/jks/loki-ca.cert
  {{- end }}
  external_labels:
    namespace: {{ .Release.Name }}
scrape_configs:
- job_name: system
  pipeline_stages:
  - multiline:
      firstline: '^\d{4}-\d{2}-\d{2}'
      max_wait_time: 3s
  static_configs:
  - targets:
    - localhost
{{- end }}

{{/*
Define Customer/Environment Domain
*/}}
{{- define "opennms.domain" -}}
{{- printf "%s.%s" .Release.Name .Values.domain -}}
{{- end }}
