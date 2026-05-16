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
  description = "Number of application replicas (horizontal scaling)"
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "Maximum number of replicas for auto-scaling"
  type        = number
  default     = 5
}

variable "min_replicas" {
  description = "Minimum number of replicas for auto-scaling"
  type        = number
  default     = 1
}

variable "scale_up_threshold" {
  description = "Requests per second threshold to trigger scale up"
  type        = number
  default     = 50
}

variable "scale_down_threshold" {
  description = "Requests per second threshold to trigger scale down"
  type        = number
  default     = 10
}

variable "app_port_base" {
  description = "Base port number for application instances"
  type        = number
  default     = 8080
}

variable "nginx_port" {
  description = "Port for the NGINX load balancer"
  type        = number
  default     = 80
}

variable "server_ip" {
  description = "Public/reachable IP of the server for external URLs"
  type        = string
  default     = "192.168.1.65"
}

variable "prometheus_port" {
  description = "Prometheus UI port"
  type        = number
  default     = 9090
}

variable "grafana_port" {
  description = "Grafana UI port"
  type        = number
  default     = 3000
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

variable "alertmanager_port" {
  description = "Alertmanager UI port"
  type        = number
  default     = 9093
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}
