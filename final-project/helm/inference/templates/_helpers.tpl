{{- define "iris.name" -}}iris-inference{{- end }}
{{- define "iris.labels" -}}
app.kubernetes.io/name: {{ include "iris.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: mlops-final-project
{{- end }}
