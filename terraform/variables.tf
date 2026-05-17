variable "namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "sre-final"
}

variable "dockerhub_username" {
  description = "Docker Hub username for pulling images"
  type        = string
  default     = "nurashi"
}

variable "app_image_tag" {
  description = "Docker image tag for the application"
  type        = string
  default     = "latest"
}

variable "app_replicas" {
  description = "Number of application replicas"
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "Maximum replicas for HPA"
  type        = number
  default     = 5
}

variable "min_replicas" {
  description = "Minimum replicas for HPA"
  type        = number
  default     = 1
}

variable "domain_app" {
  description = "Domain for the application API"
  type        = string
  default     = "sre-nurashi.abzy.kz"
}

variable "domain_grafana" {
  description = "Domain for Grafana"
  type        = string
  default     = "grafana-sre-nurashi.abzy.kz"
}

variable "domain_prometheus" {
  description = "Domain for Prometheus"
  type        = string
  default     = "metrics-sre-nurashi.abzy.kz"
}

variable "domain_alertmanager" {
  description = "Domain for Alertmanager"
  type        = string
  default     = "alerts-sre-nurashi.abzy.kz"
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}
