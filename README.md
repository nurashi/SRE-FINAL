# SRE Final Project

Site Reliability Engineering project with Infrastructure as Code, CI/CD, Observability, and Auto-scaling on Kubernetes (K3s).

## Architecture

- **Application**: Go (Gin) REST API with Prometheus metrics
- **Orchestration**: K3s (Kubernetes) with Traefik Ingress
- **IaC**: Terraform (kubernetes provider)
- **CI/CD**: GitHub Actions (self-hosted runner)
- **Observability**: Prometheus + Grafana + Alertmanager
- **Auto-scaling**: K8s HPA (CPU + Memory)
- **Load Testing**: Locust (Docker)

## Project Structure

```
├── app/                    # Go application (clean architecture)
│   ├── domain/             # Domain models
│   ├── repository/         # In-memory storage
│   ├── service/            # Business logic
│   ├── api/                # HTTP handlers (Gin)
│   ├── metrics.go          # Prometheus metrics
│   ├── main.go             # Entry point
│   └── Dockerfile          # Multi-stage build
├── terraform/              # IaC (K8s provider)
│   ├── main.tf             # Namespace, Deployments, Services, HPA, Ingress, PVCs, ConfigMaps
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # URLs and commands
│   └── terraform.tfvars    # Default values
├── monitoring/             # Observability configs
│   ├── prometheus/
│   ├── grafana/
│   └── alertmanager/
├── slo/                    # SLO definitions and alert rules
├── load-tests/             # Locust via Docker
├── .github/workflows/      # CI/CD pipeline
├── docker-compose.yml      # Local dev / fallback deploy
├── docs/report.md          # Technical report (PDF-ready)
└── README.md
```

## Access URLs

| Service | URL |
|---------|-----|
| API | https://sre-nurashi.abzy.kz |
| Grafana | https://grafana-nurashi.abzy.kz |
| SLI Dashboard | https://grafana-nurashi.abzy.kz/d/sre-sli-dashboard |
| Prometheus | https://metrics-nurashi.abzy.kz |
| Alertmanager | https://alerts-nurashi.abzy.kz |

Grafana login: `admin` / `admin`

## One-time Server Setup

Before first deploy, give the GitHub Actions runner access to K3s:

```bash
sudo cp /etc/rancher/k3s/k3s.yaml /home/nurashi/.kube/config
sudo chown nurashi:nurashi /home/nurashi/.kube/config
```

## Deploy

CI/CD deploys automatically on push to `main`. Manual deploy:

```bash
cd terraform
terraform init
terraform apply -auto-approve \
  -var="dockerhub_username=nurashi" \
  -var="app_image_tag=latest"
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Health check |
| GET | /ready | Readiness probe |
| GET | /metrics | Prometheus metrics |
| GET | /api/v1/tasks | List tasks |
| POST | /api/v1/tasks | Create task |
| GET | /api/v1/tasks/:id | Get task |
| PUT | /api/v1/tasks/:id | Update task |
| DELETE | /api/v1/tasks/:id | Delete task |

## CI/CD Pipeline

GitHub Actions workflow (self-hosted runner):
1. **Build & Test** — Go vet, compile
2. **Docker Build & Push** — Multi-stage image to Docker Hub
3. **Deploy (Terraform)** — Namespace, Deployments, Services, HPA, Ingress, PVCs
4. **Health Check** — `kubectl rollout status` + curl via ingress
5. **Validate** — Check Prometheus config and alert rules

Required GitHub Secrets:
- `DOCKERHUB_USERNAME` — Docker Hub username
- `DOCKERHUB_TOKEN` — Docker Hub access token

## SLIs and SLOs

| SLI | Description | SLO Target | Window |
|-----|------------|-----------|--------|
| Availability | Successful HTTP responses | 99.9% | 28d |
| Latency (p99) | Request duration p99 | < 1s | 28d |
| Throughput | Requests per second | 100 req/s | 28d |

## Alerts

| Alert | Severity | Condition |
|-------|----------|-----------|
| HighErrorRate | critical | 5xx error rate > 5% for 2m |
| HighLatency | warning | p99 latency > 1s for 2m |
| ServiceDown | critical | App unreachable for 1m |
| HighRequestRate | warning | Request rate > 100/s for 2m |

## Auto-Scaling (HPA)

Kubernetes HPA scales app pods based on CPU > 70% or Memory > 80%:

```bash
# Check scaling status
kubectl get hpa -n sre-final --watch

# See current replicas
kubectl get pods -n sre-final -l app=sre-final
```

HPA configuration: 1-5 replicas, CPU 70%, Memory 80%.

## Scaling Demo

```bash
# Terminal 1: Run Locust load test
docker build -t sre-final-locust -f load-tests/Dockerfile load-tests/
docker run --rm --network host sre-final-locust -f locustfile.py --host=http://localhost:80

# Terminal 2: Watch HPA scale
kubectl get hpa -n sre-final --watch

# Browser: Grafana SLI dashboard
# https://grafana-nurashi.abzy.kz/d/sre-sli-dashboard
```

## Load Testing

No pip needed — run Locust via Docker:

```bash
docker build -t sre-final-locust -f load-tests/Dockerfile load-tests/

# Web UI (http://localhost:8089)
docker run --rm --network host sre-final-locust -f locustfile.py --host=http://localhost:80

# Headless (100 users, 10/s spawn, 5 minutes)
docker run --rm --network host sre-final-locust \
  -f locustfile.py --host=http://localhost:80 \
  --headless -u 100 -r 10 -t 5m
```
