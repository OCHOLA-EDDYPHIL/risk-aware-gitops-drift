package argocd

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strings"
	"time"
)

const defaultTimeout = 10 * time.Second

type Client struct {
	baseURL    *url.URL
	token      string
	httpClient *http.Client
}

func NewClient(serverURL string, token string) (*Client, error) {
	serverURL = strings.TrimSpace(serverURL)
	token = strings.TrimSpace(token)

	if serverURL == "" {
		return nil, errors.New("argocd server URL is required")
	}
	if token == "" {
		return nil, errors.New("argocd auth token is required")
	}

	parsed, err := url.Parse(serverURL)
	if err != nil {
		return nil, fmt.Errorf("invalid argocd server URL: %w", err)
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return nil, errors.New("invalid argocd server URL: scheme must be http or https")
	}
	if parsed.Host == "" {
		return nil, errors.New("invalid argocd server URL: host is required")
	}

	return &Client{
		baseURL: parsed,
		token:   token,
		httpClient: &http.Client{
			Timeout: defaultTimeout,
		},
	}, nil
}

func (c *Client) GetApplication(ctx context.Context, appName string) (*Application, error) {
	if err := validateApplicationRequest(c, appName); err != nil {
		return nil, err
	}
	appName = strings.TrimSpace(appName)

	endpoint := *c.baseURL
	endpoint.Path = path.Join(endpoint.Path, "api", "v1", "applications", appName)
	endpoint.RawQuery = ""
	endpoint.Fragment = ""

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("create argocd application request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("get argocd application %q: %w", appName, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return nil, statusError(appName, resp.StatusCode, resp.Body)
	}

	var app Application
	decoder := json.NewDecoder(resp.Body)
	if err := decoder.Decode(&app); err != nil {
		return nil, fmt.Errorf("decode argocd application %q: %w", appName, err)
	}

	return &app, nil
}

func (c *Client) GetManagedResources(ctx context.Context, appName string) (*ManagedResourcesResponse, error) {
	if err := validateApplicationRequest(c, appName); err != nil {
		return nil, err
	}
	appName = strings.TrimSpace(appName)

	endpoint := *c.baseURL
	endpoint.Path = path.Join(endpoint.Path, "api", "v1", "applications", appName, "managed-resources")
	endpoint.RawQuery = ""
	endpoint.Fragment = ""

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("create argocd managed resources request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("get argocd managed resources for %q: %w", appName, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return nil, statusError(appName, resp.StatusCode, resp.Body)
	}

	var resources ManagedResourcesResponse
	decoder := json.NewDecoder(resp.Body)
	if err := decoder.Decode(&resources); err != nil {
		return nil, fmt.Errorf("decode argocd managed resources for %q: %w", appName, err)
	}
	if resources.Items == nil {
		resources.Items = []ResourceDiff{}
	}
	return &resources, nil
}

func validateApplicationRequest(c *Client, appName string) error {
	if c == nil {
		return errors.New("argocd client is nil")
	}
	appName = strings.TrimSpace(appName)
	if appName == "" {
		return errors.New("argocd application name is required")
	}
	if strings.Contains(appName, "/") {
		return errors.New("argocd application name must not contain '/'")
	}
	return nil
}

func statusError(appName string, statusCode int, body io.Reader) error {
	_, _ = io.Copy(io.Discard, io.LimitReader(body, 4096))

	switch statusCode {
	case http.StatusUnauthorized:
		return fmt.Errorf("get argocd application %q: unauthorized (status 401)", appName)
	case http.StatusForbidden:
		return fmt.Errorf("get argocd application %q: forbidden (status 403)", appName)
	case http.StatusNotFound:
		return fmt.Errorf("get argocd application %q: not found (status 404)", appName)
	default:
		return fmt.Errorf("get argocd application %q: unexpected status %d", appName, statusCode)
	}
}
