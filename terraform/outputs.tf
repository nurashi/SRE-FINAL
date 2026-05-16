output "app_url" {
  description = "URL to access the application via NGINX"
  value       = "http://${var.server_ip}:${var.nginx_port}"
}

output "api_direct_url" {
  description = "Direct URL to the first app instance"
  value       = "http://${var.server_ip}:${var.app_port_base}"
}

output "prometheus_url" {
  description = "URL to access Prometheus"
  value       = "http://${var.server_ip}:${var.prometheus_port}"
}

output "grafana_url" {
  description = "URL to access Grafana dashboards"
  value       = "http://${var.server_ip}:${var.grafana_port}"
}

output "grafana_sli_dashboard" {
  description = "Direct link to SLI dashboard"
  value       = "http://${var.server_ip}:${var.grafana_port}/d/sre-sli-dashboard"
}

output "alertmanager_url" {
  description = "URL to access Alertmanager"
  value       = "http://${var.server_ip}:${var.alertmanager_port}"
}

output "app_replicas" {
  description = "Number of running application replicas"
  value       = var.app_replicas
}

output "environment" {
  description = "Current deployment environment"
  value       = var.environment
}

output "network_name" {
  description = "Docker network name"
  value       = docker_network.sre_final.name
}
