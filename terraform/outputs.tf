output "app_url" {
  description = "Application URL"
  value       = "https://${var.domain_app}"
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "https://${var.domain_grafana}"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "https://${var.domain_prometheus}"
}

output "alertmanager_url" {
  description = "Alertmanager URL"
  value       = "https://${var.domain_alertmanager}"
}

output "sli_dashboard" {
  description = "Direct link to SLI dashboard"
  value       = "https://${var.domain_grafana}/d/sre-sli-dashboard"
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = kubernetes_namespace_v1.sre_final.metadata[0].name
}

output "hpa_status" {
  description = "Check HPA scaling status"
  value       = "kubectl get hpa -n ${var.namespace}"
}
