// Package docs serves the embedded OpenAPI contract and Swagger UI.
package docs

import (
	"embed"
	"net/http"
)

// Swagger UI static distribution: swagger-ui-dist 5.36.0 (Apache-2.0).
//
//go:embed openapi.yaml swagger
var files embed.FS

func Register(mux *http.ServeMux) {
	mux.Handle("GET /{$}", http.RedirectHandler("/swagger/", http.StatusFound))
	mux.Handle("GET /swagger/", http.FileServerFS(files))
	mux.HandleFunc("GET /openapi.yaml", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/yaml")
		http.ServeFileFS(w, r, files, "openapi.yaml")
	})
}
