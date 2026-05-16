terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }

  backend "local" {
    path = "/home/nurashi/terraform-state/sre-final-k8s.tfstate"
  }
}

provider "kubernetes" {
  config_path = "/home/nurashi/.kube/config"
}

resource "kubernetes_namespace_v1" "sre_final" {
  metadata {
    name = var.namespace
  }
}

locals {
  prometheus_config = yamlencode({
    global = {
      scrape_interval     = "15s"
      scrape_timeout      = "10s"
      evaluation_interval = "15s"
    }
    alerting = {
      alertmanagers = [{
        static_configs = [{ targets = ["alertmanager.${var.namespace}.svc:9093"] }]
      }]
    }
    rule_files = ["/etc/prometheus/rules.yml"]
    scrape_configs = [
      {
        job_name        = "prometheus"
        static_configs  = [{ targets = ["localhost:9090"] }]
      },
      {
        job_name        = "sre-final-app"
        metrics_path    = "/metrics"
        scrape_interval = "5s"
        static_configs  = [{ targets = ["app.${var.namespace}.svc:80"] }]
      },
    ]
  })

  alertmanager_config = file("${path.module}/../monitoring/alertmanager/alertmanager.yml")
  rules_content       = file("${path.module}/../slo/rules.yml")
  grafana_ds          = file("${path.module}/../monitoring/grafana/provisioning/datasources/datasources.yml")
  grafana_dash_prov   = file("${path.module}/../monitoring/grafana/provisioning/dashboards/dashboards.yml")
  grafana_dashboard   = file("${path.module}/../monitoring/grafana/dashboards/sli-dashboard.json")
}

# ── App ──────────────────────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
    labels    = { app = "sre-final" }
  }

  spec {
    replicas = var.app_replicas

    selector {
      match_labels = { app = "sre-final" }
    }

    template {
      metadata {
        labels = { app = "sre-final" }
      }

      spec {
        container {
          name  = "app"
          image = "${var.dockerhub_username}/sre-final:${var.app_image_tag}"

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "PORT"
            value = "8080"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8080
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name      = "app"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  spec {
    selector = { app = "sre-final" }
    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "app" {
  metadata {
    name      = "app-hpa"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.app.metadata[0].name
    }

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }
  }
}

# ── Prometheus ────────────────────────────────────────────────────────────────

resource "kubernetes_config_map_v1" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  data = {
    "prometheus.yml" = local.prometheus_config
    "rules.yml"      = local.rules_content
  }
}

resource "kubernetes_persistent_volume_claim_v1" "prometheus" {
  metadata {
    name      = "prometheus-data"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }

  timeouts {
    create = "2m"
  }
}

resource "kubernetes_deployment_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
    labels    = { app = "prometheus" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "prometheus" }
    }

    template {
      metadata {
        labels = { app = "prometheus" }
      }

      spec {
        container {
          name  = "prometheus"
          image = "prom/prometheus:v3.2.1"

          port {
            container_port = 9090
            name           = "http"
          }

          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--storage.tsdb.retention.time=30d",
            "--web.enable-admin-api",
          ]

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/prometheus"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.prometheus_config.metadata[0].name
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.prometheus.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  spec {
    selector = { app = "prometheus" }
    port {
      port        = 9090
      target_port = 9090
      protocol    = "TCP"
    }
  }
}

# ── Grafana ───────────────────────────────────────────────────────────────────

resource "kubernetes_config_map_v1" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  data = {
    "datasources.yml" = local.grafana_ds
  }
}

resource "kubernetes_config_map_v1" "grafana_dashboards_prov" {
  metadata {
    name      = "grafana-dashboards-prov"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  data = {
    "dashboards.yml" = local.grafana_dash_prov
  }
}

resource "kubernetes_config_map_v1" "grafana_dashboard_sli" {
  metadata {
    name      = "grafana-dashboard-sli"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  data = {
    "sli-dashboard.json" = local.grafana_dashboard
  }

  lifecycle {
    ignore_changes = [data]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "grafana" {
  metadata {
    name      = "grafana-data"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }

  timeouts {
    create = "2m"
  }
}

resource "kubernetes_deployment_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
    labels    = { app = "grafana" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "grafana" }
    }

    template {
      metadata {
        labels = { app = "grafana" }
      }

      spec {
        container {
          name  = "grafana"
          image = "grafana/grafana:11.5.1"

          port {
            container_port = 3000
            name           = "http"
          }

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = var.grafana_admin_user
          }
          env {
            name  = "GF_SECURITY_ADMIN_PASSWORD"
            value = var.grafana_admin_password
          }
          env {
            name  = "GF_SERVER_ROOT_URL"
            value = "https://grafana-${var.domain_suffix}"
          }
          env {
            name  = "GF_SERVER_DOMAIN"
            value = "grafana-${var.domain_suffix}"
          }
          env {
            name  = "GF_SERVER_ENFORCE_DOMAIN"
            value = "false"
          }
          env {
            name  = "GF_AUTH_ANONYMOUS_ENABLED"
            value = "true"
          }
          env {
            name  = "GF_AUTH_ANONYMOUS_ORG_ROLE"
            value = "Viewer"
          }
          env {
            name  = "GF_INSTALL_PLUGINS"
            value = "grafana-clock-panel"
          }

          volume_mount {
            name       = "datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
            read_only  = true
          }
          volume_mount {
            name       = "dashboards-prov"
            mount_path = "/etc/grafana/provisioning/dashboards"
            read_only  = true
          }
          volume_mount {
            name       = "dashboards-json"
            mount_path = "/var/lib/grafana/dashboards"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/grafana"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "datasources"
          config_map {
            name = kubernetes_config_map_v1.grafana_datasources.metadata[0].name
          }
        }
        volume {
          name = "dashboards-prov"
          config_map {
            name = kubernetes_config_map_v1.grafana_dashboards_prov.metadata[0].name
          }
        }
        volume {
          name = "dashboards-json"
          config_map {
            name = kubernetes_config_map_v1.grafana_dashboard_sli.metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.grafana.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  spec {
    selector = { app = "grafana" }
    port {
      port        = 3000
      target_port = 3000
      protocol    = "TCP"
    }
  }
}

# ── Alertmanager ──────────────────────────────────────────────────────────────

resource "kubernetes_config_map_v1" "alertmanager_config" {
  metadata {
    name      = "alertmanager-config"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  data = {
    "alertmanager.yml" = local.alertmanager_config
  }
}

resource "kubernetes_persistent_volume_claim_v1" "alertmanager" {
  metadata {
    name      = "alertmanager-data"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }

  timeouts {
    create = "2m"
  }
}

resource "kubernetes_deployment_v1" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
    labels    = { app = "alertmanager" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "alertmanager" }
    }

    template {
      metadata {
        labels = { app = "alertmanager" }
      }

      spec {
        container {
          name  = "alertmanager"
          image = "prom/alertmanager:v0.28.1"

          port {
            container_port = 9093
            name           = "http"
          }

          args = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager",
          ]

          volume_mount {
            name       = "config"
            mount_path = "/etc/alertmanager"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/alertmanager"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.alertmanager_config.metadata[0].name
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.alertmanager.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
  }

  spec {
    selector = { app = "alertmanager" }
    port {
      port        = 9093
      target_port = 9093
      protocol    = "TCP"
    }
  }
}

# ── Ingress ───────────────────────────────────────────────────────────────────

resource "kubernetes_ingress_v1" "main" {
  metadata {
    name      = "sre-final-ingress"
    namespace = kubernetes_namespace_v1.sre_final.metadata[0].name
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "sre-${var.domain_suffix}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.app.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "grafana-${var.domain_suffix}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.grafana.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }

    rule {
      host = "metrics-${var.domain_suffix}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.prometheus.metadata[0].name
              port {
                number = 9090
              }
            }
          }
        }
      }
    }

    rule {
      host = "alerts-${var.domain_suffix}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.alertmanager.metadata[0].name
              port {
                number = 9093
              }
            }
          }
        }
      }
    }
  }
}
