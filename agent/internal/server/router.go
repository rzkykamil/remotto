package server

import (
	"fmt"
	"net/http"
	"sort"
	"strings"
)

// Router matches routes by exact path and method. It replaces http.ServeMux so
// that 404 and 405 responses use the error envelope and carry an Allow header.
//
// Routes must be registered with Handle before the router starts serving.
type Router struct {
	routes map[string]map[string]http.Handler
}

// NewRouter returns an empty Router.
func NewRouter() *Router {
	return &Router{routes: make(map[string]map[string]http.Handler)}
}

// Handle registers h for the exact method and path, for example "GET" and
// "/api/v1/status". It panics if the same method and path are registered twice.
func (r *Router) Handle(method, path string, h http.Handler) {
	byMethod, ok := r.routes[path]
	if !ok {
		byMethod = make(map[string]http.Handler)
		r.routes[path] = byMethod
	}
	if _, dup := byMethod[method]; dup {
		panic(fmt.Sprintf("server: route %s %s registered twice", method, path))
	}
	byMethod[method] = h
}

// ServeHTTP dispatches to the registered handler, or writes a 404 or 405 envelope.
func (r *Router) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	byMethod, ok := r.routes[req.URL.Path]
	if !ok {
		WriteError(w, http.StatusNotFound, CodeNotFound, "route not found")
		return
	}
	h, ok := byMethod[req.Method]
	if !ok {
		methods := make([]string, 0, len(byMethod))
		for m := range byMethod {
			methods = append(methods, m)
		}
		sort.Strings(methods)
		w.Header().Set("Allow", strings.Join(methods, ", "))
		WriteError(w, http.StatusMethodNotAllowed, CodeMethodNotAllowed, "method not allowed")
		return
	}
	h.ServeHTTP(w, req)
}
