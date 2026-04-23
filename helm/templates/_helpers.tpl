{{/*
Resolve the Federation API base URL.
If federation.url is explicitly set, use it.
Otherwise derive from global.env:
  "test" → https://federation.ndp.utah.edu/test
  "prod" (default) → https://federation.ndp.utah.edu
*/}}
{{- define "scidx.federationUrl" -}}
{{- if .Values.federation.url -}}
{{- .Values.federation.url -}}
{{- else if eq (.Values.global.env | default "prod") "test" -}}
https://federation.ndp.utah.edu/test
{{- else -}}
https://federation.ndp.utah.edu
{{- end -}}
{{- end -}}

{{/*
Resolve the IDP (Keycloak) hostname.
If global.clusterIdpHost is explicitly set, use it.
Otherwise derive from global.env:
  "test" → idp-test.nationaldataplatform.org
  "prod" (default) → idp.nationaldataplatform.org
*/}}
{{- define "scidx.clusterIdpHost" -}}
{{- if .Values.global.clusterIdpHost -}}
{{- .Values.global.clusterIdpHost -}}
{{- else if eq (.Values.global.env | default "prod") "test" -}}
idp-test.nationaldataplatform.org
{{- else -}}
idp.nationaldataplatform.org
{{- end -}}
{{- end -}}
