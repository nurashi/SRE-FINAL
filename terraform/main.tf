terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "docker_network" "sre_final" {
  name   = "sre-final-network"
  driver = "bridge"

  ipam_config {
    subnet  = "10.10.0.0/16"
    gateway = "10.10.0.1"
  }
}

resource "docker_volume" "prometheus_data" {
  name = "sre_final_prometheus_data"
}

resource "docker_volume" "grafana_data" {
  name = "sre_final_grafana_data"
}

resource "docker_volume" "alertmanager_data" {
  name = "sre_final_alertmanager_data"
}

resource "docker_image" "app" {
  name         = "${var.dockerhub_username}/sre-final:${var.app_image_tag}"
  keep_locally = true
}

resource "docker_image" "prometheus" {
  name         = "prom/prometheus:v3.2.1"
  keep_locally = true
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:11.5.1"
  keep_locally = true
}

resource "docker_image" "alertmanager" {
  name         = "prom/alertmanager:v0.28.1"
  keep_locally = true
}

resource "docker_image" "nginx" {
  name         = "nginx:1.27-alpine"
  keep_locally = true
}

resource "docker_container" "app" {
  name    = "sre-final-app-${count.index}"
  image   = docker_image.app.image_id
  count   = var.app_replicas
  restart = "unless-stopped"

  networks_advanced {
    name    = docker_network.sre_final.name
    aliases = ["app"]
  }

  ports {
    internal = 8080
    external = var.app_port_base + count.index
  }

  env = [
    "PORT=8080",
  ]
}

resource "local_file" "nginx_config" {
  content = templatefile("${path.module}/nginx.conf.tftpl", {
    replicas = var.app_replicas
  })
  filename = "${path.root}/generated_nginx.conf"
}

resource "docker_container" "nginx" {
  name    = "sre-final-nginx"
  image   = docker_image.nginx.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.sre_final.name
  }

  ports {
    internal = 80
    external = var.nginx_port
  }

  volumes {
    host_path      = abspath(local_file.nginx_config.filename)
    container_path = "/etc/nginx/nginx.conf"
    read_only      = true
  }

  depends_on = [docker_container.app]
}

resource "docker_container" "prometheus" {
  name    = "sre-final-prometheus"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.sre_final.name
  }

  ports {
    internal = 9090
    external = var.prometheus_port
  }

  volumes {
    host_path      = abspath("${path.root}/../monitoring/prometheus/prometheus.yml")
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }

  volumes {
    host_path      = abspath("${path.root}/../slo/rules.yml")
    container_path = "/etc/prometheus/rules.yml"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.prometheus_data.name
    container_path = "/prometheus"
  }

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=30d",
    "--web.enable-admin-api",
  ]
}

resource "docker_container" "grafana" {
  name    = "sre-final-grafana"
  image   = docker_image.grafana.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.sre_final.name
  }

  ports {
    internal = 3000
    external = var.grafana_port
  }

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource",
    "GF_SERVER_ROOT_URL=http://${var.server_ip}:${var.grafana_port}",
    "GF_SERVER_DOMAIN=${var.server_ip}",
    "GF_SERVER_ENFORCE_DOMAIN=false",
    "GF_AUTH_ANONYMOUS_ENABLED=true",
    "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer",
  ]

  volumes {
    host_path      = abspath("${path.root}/../monitoring/grafana/provisioning")
    container_path = "/etc/grafana/provisioning"
    read_only      = true
  }

  volumes {
    host_path      = abspath("${path.root}/../monitoring/grafana/dashboards")
    container_path = "/var/lib/grafana/dashboards"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.grafana_data.name
    container_path = "/var/lib/grafana"
  }

  depends_on = [docker_container.prometheus]
}

resource "docker_container" "alertmanager" {
  name    = "sre-final-alertmanager"
  image   = docker_image.alertmanager.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.sre_final.name
  }

  ports {
    internal = 9093
    external = var.alertmanager_port
  }

  volumes {
    host_path      = abspath("${path.root}/../monitoring/alertmanager/alertmanager.yml")
    container_path = "/etc/alertmanager/alertmanager.yml"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.alertmanager_data.name
    container_path = "/alertmanager"
  }

  command = [
    "--config.file=/etc/alertmanager/alertmanager.yml",
    "--storage.path=/alertmanager",
  ]
}
