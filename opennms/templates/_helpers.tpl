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
  {{- if .Values.dependencies.truststore }}
    {{- $password := "" }}
    {{- if .Values.dependencies.truststore.password }}
      {{- $password = "-Djavax.net.ssl.trustStorePassword=$(TRUSTSTORE_PASSWORD)" }}
    {{- end }}
    {{- $truststore := "-Djavax.net.ssl.trustStore=/etc/java/jks/truststore.jks" }}
    {{- if and .Values.dependencies.truststore.content }}
      {{- printf "%s %s %s" $common $truststore $password }}
    {{- end }}
  {{- else -}}
    {{- $common }}
  {{- end }}
{{- end }}
