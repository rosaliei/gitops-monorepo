{{- define "app.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/part-of: gitops-demo
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "app.selector" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* repository:tag, plus @digest when CI provided one */}}
{{- define "app.image" -}}
{{- $img := printf "%s:%s" (required "image.repository is required" .Values.image.repository) (required "image.tag is required" .Values.image.tag) -}}
{{- if .Values.image.digest }}{{ printf "%s@%s" $img .Values.image.digest }}{{ else }}{{ $img }}{{ end -}}
{{- end }}
