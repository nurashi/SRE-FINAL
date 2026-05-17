# SRE Capstone Project — Production Readiness Review

**Team:** SRE-FINAL  
**Repository:** https://github.com/nurashi/SRE-FINAL  
**Date:** May 2026

---

## 1. Architecture Overview

```
                          Internet
                              │
                    ┌─────────▼─────────┐
                    │  Traefik Ingress   │  K3s Ingress Controller
                    │  (HTTP)            │
                    └─────────┬─────────┘
                              │
        ┌─────────┬───────────┼───────────┬─────────┐
        │         │           │           │         │
   sre-*.abzy.kz grafana-*  metrics-*  alerts-*   (Host-based routing)
        │         │           │           │
  ┌─────▼──┐ ┌───▼────┐ ┌───▼──────┐ ┌─▼──────────┐
  │ App    │ │Grafana │ │Prometheus│ │Alertmanager│
  │Deploymt│ │Deploymt│ │Deploymt  │ │Deploymt    │
  │ Replic │ │ Repl:1 │ │ Repl:1   │ │ Repl:1     │
  │ 2→5    │ └───┬────┘ └───┬──────┘ └─┬──────────┘
  │ (HPA)  │     │          │          │
  └───┬────┘     │          │          │
      │          │          │          │
      │          │    ┌─────▼──────┐   │
      │          │    │ Prometheus │   │
      │          │    │ ConfigMap  │   │
      │          │    │ (rules.yml)│   │
      │          │    └────────────┘   │
      │          │          │          │
  ┌───▼──────────▼──────────▼──────────▼───┐
  │          PVC (local-path)              │
  │   10Gi (prom) / 2Gi (graf) / 1Gi (am) │
  └────────────────────────────────────────┘
```

### Stack

| Layer | Technology |
|-------|-----------|
| Application | Go (Gin), in-memory storage |
| Containerization | Docker, multi-stage build |
| Orchestration | K3s (Kubernetes) |
| Ingress | Traefik |
| Infrastructure as Code | Terraform (kubernetes provider) |
| CI/CD | GitHub Actions (self-hosted runner) |
| Metrics | Prometheus |
| Dashboards | Grafana |
| Alerting | Alertmanager |
| Auto-scaling | K8s HPA (CPU + Memory) |
| Load Testing | Locust (Docker) |

---

## 2. Infrastructure as Code

### Terraform Resources (kubernetes provider)

| Resource | Purpose | Scaling |
|----------|---------|---------|
| `kubernetes_namespace` | Isolated namespace `sre-final` | Static |
| `kubernetes_deployment` × 4 | App, Prometheus, Grafana, Alertmanager | HPA on App |
| `kubernetes_service` × 4 | ClusterIP services | Static |
| `kubernetes_horizontal_pod_autoscaler_v2` | CPU > 70% or Memory > 80% → scale up | 1-5 replicas |
| `kubernetes_persistent_volume_claim` × 3 | Prometheus (10Gi), Grafana (2Gi), Alertmanager (1Gi) | local-path |
| `kubernetes_config_map` × 5 | Monitoring configs & dashboards | Static |
| `kubernetes_ingress_v1` | Traefik host-based routing for 4 domains | Static |

### Variables

```
app_replicas     = 2      (initial, HPA overrides)
max_replicas     = 5      (HPA ceiling)
min_replicas     = 1      (HPA floor)
domain_suffix    = nurashi.abzy.kz
namespace        = sre-final
```

### State Management

- Backend: local, path `/home/nurashi/terraform-state/sre-final-k8s.tfstate`
- State persisted between CI/CD runs
- `clean: false` on checkout preserves `.terraform/` provider cache

---

## 3. CI/CD Pipeline

### Workflow: `.github/workflows/ci-cd.yml`

```
git push main
    │
    ├─► build-and-test        go vet + go build
    │
    ├─► docker-build-push     docker/login → buildx → metadata → push
    │                         tags: latest, sha-<short>, main
    │
    ├─► deploy                terraform init → terraform apply (K8s provider)
    │                         → kubectl rollout status → health check
    │
    └─► prometheus-validate   promtool check config + rules
```

### Successful Execution

*[Insert screenshot of GitHub Actions — all jobs green]*

---

## 4. Observability & Alerting

### Prometheus

- **Scrape interval**: 5s for the app job
- **Retention**: 30 days
- **Metrics exported by app**:
  - `http_requests_total` (counter, labels: method, path, status)
  - `http_request_duration_seconds` (histogram, labels: method, path, status)
  - `http_requests_in_flight` (gauge)

### Grafana Dashboard

**SLI Dashboard** (`https://grafana-sre-nurashi.abzy.kz/d/sre-sli-dashboard`):

| Panel | Metric | Purpose |
|-------|--------|---------|
| Request Rate | `rate(http_requests_total[5m])` | Traffic volume |
| Error Rate | `5xx / total × 100` | Availability SLI |
| Response Time (p50/p95/p99) | `histogram_quantile(...)` | Latency SLI |
| Requests In Flight | `http_requests_in_flight` | Concurrency |
| Availability SLI | `(1 - error_rate) × 100` | SLO compliance gauge |
| Latency SLO p99 | `histogram_quantile(0.99, ...)` | p99 vs. 1s target |
| Heatmap | Request duration distribution | Anomaly detection |

*[Insert screenshot of Grafana SLI Dashboard]*

### Alertmanager Rules

| Alert | Severity | Expression | For |
|-------|----------|-----------|-----|
| HighErrorRate | critical | 5xx error rate > 5% | 2m |
| HighLatency | warning | p99 latency > 1s | 2m |
| ServiceDown | critical | App unreachable | 1m |
| HighRequestRate | warning | Request rate > 100/s | 2m |

*[Insert screenshot of Alertmanager firing alert]*

---

## 5. SRE Operations

### SLIs and SLOs

| SLI | Metric | SLO Target | Window | Error Budget |
|-----|--------|-----------|--------|-------------|
| Availability | `(1 - (5xx / total)) × 100` | **99.9%** | 28d | 0.1% |
| Latency (p99) | `histogram_quantile(0.99, ...)` | **< 1.0s** | 28d | 1.0s |
| Throughput | `rate(http_requests_total[1m])` | **100 req/s** | 28d | — |

### Auto-Scaling (K8s HPA)

Kubernetes Horizontal Pod Autoscaler manages replicas automatically:

```yaml
minReplicas: 1
maxReplicas: 5
metrics:
  - cpu:    70% utilization
  - memory: 80% utilization
```

Check scaling status:
```bash
kubectl get hpa -n sre-final --watch
```

*[Insert screenshot showing HPA scaling during load test]*

### Load Testing

**Tool**: Locust via Docker (`load-tests/Dockerfile`)

```bash
# Build (one time)
docker build -t sre-final-locust -f load-tests/Dockerfile load-tests/

# Web UI
docker run --rm --network host sre-final-locust -f locustfile.py --host=http://localhost:80

# Headless (100 users, 10/s spawn, 5 minutes)
docker run --rm --network host sre-final-locust \
  -f locustfile.py --host=http://localhost:80 \
  --headless -u 100 -r 10 -t 5m
```

*[Insert screenshot of Locust with users/spawn rate]*
*[Insert screenshot of Grafana showing traffic spike + scaling]*

---

## 6. Access URLs

| Service | URL |
|---------|-----|
| API | https://sre-nurashi.abzy.kz |
| Grafana | https://grafana-sre-nurashi.abzy.kz |
| SLI Dashboard | https://grafana-sre-nurashi.abzy.kz/d/sre-sli-dashboard |
| Prometheus | https://metrics-sre-nurashi.abzy.kz |
| Alertmanager | https://alerts-sre-nurashi.abzy.kz |

## 7. Project Structure

```
SRE-FINAL/
├── app/                          # Go application
│   ├── domain/models.go
│   ├── repository/memory.go
│   ├── service/task.go
│   ├── api/router.go
│   ├── metrics.go
│   ├── main.go
│   └── Dockerfile
├── terraform/                    # IaC (K8s provider)
│   ├── main.tf                   # Namespace, Deployments, Services, HPA, Ingress, PVC, ConfigMaps
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars
├── monitoring/
│   ├── prometheus/prometheus.yml
│   ├── grafana/dashboards/
│   ├── grafana/provisioning/
│   └── alertmanager/
├── slo/
│   ├── rules.yml
│   └── slos.yaml
├── load-tests/
│   ├── Dockerfile
│   ├── locustfile.py
│   └── requirements.txt
├── .github/workflows/ci-cd.yml
├── docker-compose.yml            # Fallback (local dev)
├── docs/report.md
└── README.md
```

---

## 8. Screenshots Checklist

| # | Screenshot | Description |
|---|-----------|-------------|
| 1 | GitHub Actions — all jobs green | CI/CD pipeline successful execution |
| 2 | Grafana SLI Dashboard | All 7 panels showing live metrics |
| 3 | Alertmanager firing alert | Alert being triggered |
| 4 | Locust load test running | Users spawned, requests flowing |
| 5 | Grafana during load test | Traffic spike visible |
| 6 | `kubectl get hpa -n sre-final` | HPA showing increased replicas |

*[Attach all screenshots above]*

---

## 9. Conclusion

The SRE-FINAL project demonstrates a complete production-ready infrastructure on Kubernetes:

- **Reproducible**: `terraform apply` provisions entire K8s namespace from scratch
- **Automated**: GitHub Actions CI/CD builds, tests, and deploys on every push
- **Observable**: Prometheus metrics → Grafana dashboards → Alertmanager notifications
- **Scalable**: K8s HPA auto-scales pods based on CPU and memory utilization
- **Testable**: Locust load testing validates SLOs and triggers auto-scaling

All four assignment steps are fully implemented and verified.
