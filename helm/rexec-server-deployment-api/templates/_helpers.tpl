{{- define "deployment-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "deployment-api.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | lower | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride | lower -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "deployment-api.labels" -}}
app.kubernetes.io/name: {{ include "deployment-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "deployment-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "deployment-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "deployment-api.kubeconfigSecretName" -}}
{{- printf "%s-kubeconfig" (include "deployment-api.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "deployment-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- include "deployment-api.fullname" . -}}
{{- end -}}
{{- end -}}
