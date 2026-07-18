package argocd

type Application struct {
	Metadata ApplicationMetadata `json:"metadata"`
	Spec     ApplicationSpec     `json:"spec"`
	Status   ApplicationStatus   `json:"status"`
}

type ApplicationMetadata struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
}

type ApplicationSpec struct {
	Project string `json:"project"`
}

type ApplicationStatus struct {
	Sync      SyncStatus       `json:"sync"`
	Health    HealthStatus     `json:"health"`
	Resources []ResourceStatus `json:"resources"`
}

type SyncStatus struct {
	Status string `json:"status"`
}

type HealthStatus struct {
	Status string `json:"status"`
}

type ResourceStatus struct {
	Group     string       `json:"group"`
	Version   string       `json:"version"`
	Kind      string       `json:"kind"`
	Namespace string       `json:"namespace"`
	Name      string       `json:"name"`
	Status    string       `json:"status"`
	Health    HealthStatus `json:"health"`
}

type ManagedResourcesResponse struct {
	Items []ResourceDiff `json:"items"`
}

// ResourceDiff mirrors the managed-resource evidence returned by Argo CD.
// PredictedLiveState is the normalized desired state and NormalizedLiveState
// is the normalized state currently observed in the cluster.
type ResourceDiff struct {
	Group               string `json:"group"`
	Kind                string `json:"kind"`
	Namespace           string `json:"namespace"`
	Name                string `json:"name"`
	TargetState         string `json:"targetState"`
	LiveState           string `json:"liveState"`
	NormalizedLiveState string `json:"normalizedLiveState"`
	PredictedLiveState  string `json:"predictedLiveState"`
	ResourceVersion     string `json:"resourceVersion"`
	Modified            bool   `json:"modified"`
}
