{{- define "app-with-helm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "app-with-helm.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "app-with-helm.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "app-with-helm.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "app-with-helm.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "app-with-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app-with-helm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
