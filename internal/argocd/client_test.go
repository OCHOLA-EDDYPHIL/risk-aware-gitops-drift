package argocd

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const testToken = "test-token-value"

func TestGetApplicationBuildsPathAndSendsBearerToken(t *testing.T) {
	var gotPath string
	var gotAuth string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("Authorization")
		fmt.Fprint(w, `{"metadata":{"name":"guestbook","namespace":"argocd"},"spec":{"project":"default"},"status":{"sync":{"status":"OutOfSync"},"health":{"status":"Healthy"},"resources":[]}}`)
	}))
	defer server.Close()

	client, err := NewClient(server.URL, testToken)
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}

	if _, err := client.GetApplication(context.Background(), "guestbook"); err != nil {
		t.Fatalf("GetApplication() error = %v", err)
	}

	if gotPath != "/api/v1/applications/guestbook" {
		t.Fatalf("path = %q, want /api/v1/applications/guestbook", gotPath)
	}
	if gotAuth != "Bearer "+testToken {
		t.Fatalf("authorization header = %q", gotAuth)
	}
}

func TestGetApplicationHandles200(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"metadata":{"name":"guestbook","namespace":"argocd"},"spec":{"project":"default"},"status":{"sync":{"status":"OutOfSync"},"health":{"status":"Healthy"},"resources":[{"group":"apps","version":"v1","kind":"Deployment","namespace":"demo","name":"guestbook","status":"OutOfSync","health":{"status":"Healthy"}}]}}`)
	}))
	defer server.Close()

	client, err := NewClient(server.URL, testToken)
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	app, err := client.GetApplication(context.Background(), "guestbook")
	if err != nil {
		t.Fatalf("GetApplication() error = %v", err)
	}

	if app.Metadata.Name != "guestbook" {
		t.Fatalf("application name = %q", app.Metadata.Name)
	}
	if len(app.Status.Resources) != 1 {
		t.Fatalf("resources length = %d, want 1", len(app.Status.Resources))
	}
}

func TestGetApplicationHandles401WithoutTokenLeak(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "bad token "+testToken, http.StatusUnauthorized)
	}))
	defer server.Close()

	client, err := NewClient(server.URL, testToken)
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	_, err = client.GetApplication(context.Background(), "guestbook")
	if err == nil {
		t.Fatal("GetApplication() error = nil, want error")
	}
	if strings.Contains(err.Error(), testToken) {
		t.Fatalf("error leaked token: %v", err)
	}
	if !strings.Contains(err.Error(), "status 401") {
		t.Fatalf("error = %v, want status 401", err)
	}
}

func TestGetApplicationHandles404(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.NotFound(w, r)
	}))
	defer server.Close()

	client, err := NewClient(server.URL, testToken)
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	_, err = client.GetApplication(context.Background(), "missing")
	if err == nil || !strings.Contains(err.Error(), "status 404") {
		t.Fatalf("error = %v, want status 404", err)
	}
}

func TestGetApplicationHandlesInvalidJSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{not-json`)
	}))
	defer server.Close()

	client, err := NewClient(server.URL, testToken)
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	_, err = client.GetApplication(context.Background(), "guestbook")
	if err == nil || !strings.Contains(err.Error(), "decode argocd application") {
		t.Fatalf("error = %v, want decode error", err)
	}
}

func TestGetApplicationHandlesEmptyAppName(t *testing.T) {
	client, err := NewClient("https://argocd.example.local", testToken)
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	_, err = client.GetApplication(context.Background(), " ")
	if err == nil || !strings.Contains(err.Error(), "application name is required") {
		t.Fatalf("error = %v, want empty app name error", err)
	}
}

func TestNewClientValidatesInput(t *testing.T) {
	tests := []struct {
		name      string
		serverURL string
		token     string
	}{
		{name: "empty server", serverURL: "", token: testToken},
		{name: "empty token", serverURL: "https://argocd.example.local", token: ""},
		{name: "bad scheme", serverURL: "ftp://argocd.example.local", token: testToken},
		{name: "missing host", serverURL: "https://", token: testToken},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := NewClient(tt.serverURL, tt.token); err == nil {
				t.Fatal("NewClient() error = nil, want error")
			}
		})
	}
}
