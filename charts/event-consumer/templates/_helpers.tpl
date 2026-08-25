{{/*
릴리스 이름을 리소스 이름에 섞지 않는다. IRSA 신뢰 정책이 ServiceAccount 이름을
고정하고 있어서, 이름이 릴리스에 따라 달라지면 권한이 끊긴다.
*/}}
{{- define "app.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "app.labels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: adspectrum
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
셀렉터에는 배포마다 바뀌는 값을 넣지 않는다. Deployment의 selector는 생성 후
수정할 수 없어서, 이미지 태그 같은 것이 섞이면 다음 배포가 통째로 막힌다.
*/}}
{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
