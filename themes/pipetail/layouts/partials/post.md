# {{ .Title }}

{{ with .Description }}> {{ . }}

{{ end }}Published {{ .Date.Format "2006-01-02" }}{{ range .Params.authors }}{{ with site.GetPage (printf "/authors/%s" (. | urlize)) }} by {{ .Params.name | default .Title }}{{ end }}{{ end }}. Source: {{ .Permalink }}

{{ .RenderShortcodes }}
