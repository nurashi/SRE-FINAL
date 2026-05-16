output "app_url" {
  description = "Application URL"
  value       = "https://sre-${var.domain_suffix}"
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "https://grafana-${var.domain_suffix}"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "https://metrics-${var.domain_suffix}"
}

output "alertmanager_url" {
  description = "Alertmanager URL"
  value       = "https://alerts-${var.domain_suffix}"
}

output "sli_dashboard" {
  description = "Direct link to SLI dashboard"
  value       = "https://grafana-${var.domain_suffix}/d/sre-sli-dashboard"
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = kubernetes_namespace_v1.sre_final.metadata[0].name
}

output "hpa_status" {
  description = "Check HPA scaling status"
  value       = "kubectl get hpa -n ${var.namespace}"
}
