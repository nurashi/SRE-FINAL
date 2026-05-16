# SRE Final Project

Site Reliability Engineering project with Infrastructure as Code, CI/CD, Observability, and Auto-scaling.

## Architecture

- **Application**: Go (Gin) REST API with Prometheus metrics
- **Load Balancer**: NGINX
- **Observability**: Prometheus + Grafana + Alertmanager
- **IaC**: Terraform (Docker provider)
- **CI/CD**: GitHub Actions (self-hosted runner)
- **Load Testing**: Locust

## Project Structure

```
├── app/                    # Go application (clean architecture)
│   ├── domain/             # Domain models
│   ├── repository/         # In-memory storage
│   ├── service/            # Business logic layer
│   ├── api/                # HTTP handlers (Gin)
│   ├── metrics.go          # Prometheus metrics
│   ├── main.go             # Entry point
│   └── Dockerfile          # Multi-stage build
├── terraform/              # Infrastructure as Code
│   ├── main.tf             # Docker containers, network, volumes
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # Output values
│   └── nginx.conf.tftpl    # NGINX config template
├── monitoring/             # Observability stack
│   ├── prometheus/         # Metrics scraping config
│   ├── grafana/            # Dashboards + datasources
│   └── alertmanager/       # Alert routing
├── slo/                    # SLO definitions and alert rules
├── load-tests/             # Locust load testing
├── .github/workflows/      # CI/CD pipeline
├── docker-compose.yml      # Local deployment stack
├── nginx.conf              # NGINX config (docker-compose)
└── README.md
```

## Quick Start

### Deploy with Docker Compose

```bash
DOCKERHUB_USERNAME=nurashi TAG=latest docker compose up -d
```

### Deploy with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

### Endpoints

Accessible at server IP `192.168.1.65`:

| Service        | URL                                             |
|----------------|-------------------------------------------------|
| API (NGINX)    | http://192.168.1.65                             |
| API (direct)   | http://192.168.1.65:8080                        |
| Prometheus     | http://192.168.1.65:9090                        |
| Grafana        | http://192.168.1.65:3000                        |
| SLI Dashboard  | http://192.168.1.65:3000/d/sre-sli-dashboard   |
| Alertmanager   | http://192.168.1.65:9093                        |

Grafana login: `admin` / `admin`

### Load Testing

No pip needed — run Locust via Docker:

```bash
# Build locust image (one time)
docker build -t sre-final-locust -f load-tests/Dockerfile load-tests/

# Run with web UI (http://localhost:8089)
docker run --rm --network host sre-final-locust -f locustfile.py --host=http://localhost:80

# Run headless (no UI)
docker run --rm --network host sre-final-locust \
  -f locustfile.py --host=http://localhost:80 \
  --headless -u 100 -r 10 -t 5m
```

Options:
- `-u 100` — simultaneous users
- `-r 10` — spawn rate (users/second)
- `-t 5m` — run for 5 minutes

## SLIs and SLOs

| SLI            | Description                | SLO Target   | Window |
|----------------|----------------------------|--------------|--------|
| Availability   | Successful HTTP responses  | 99.9%        | 28d    |
| Latency (p99)  | Request duration p99      | < 1s         | 28d    |
| Throughput     | Requests per second        | 100 req/s    | 28d    |

## API Endpoints

| Method | Path             | Description     |
|--------|------------------|-----------------|
| GET    | /health          | Health check    |
| GET    | /ready           | Readiness probe |
| GET    | /metrics         | Prometheus metrics |
| GET    | /api/v1/tasks    | List tasks      |
| POST   | /api/v1/tasks    | Create task     |
| GET    | /api/v1/tasks/:id| Get task        |
| PUT    | /api/v1/tasks/:id| Update task     |
| DELETE | /api/v1/tasks/:id| Delete task     |

## CI/CD Pipeline

GitHub Actions workflow (self-hosted runner):
1. **Build & Test** - Go vet, compile
2. **Docker Build & Push** - Multi-stage image to Docker Hub
3. **Deploy** - Pull image and restart containers
4. **Health Check** - Verify service is healthy
5. **Validate** - Check Prometheus config and alert rules

Required GitHub Secrets:
- `DOCKERHUB_USERNAME` - Docker Hub username
- `DOCKERHUB_TOKEN` - Docker Hub access token

## Alerts

| Alert             | Severity | Condition                    |
|-------------------|----------|------------------------------|
| HighErrorRate     | critical | 5xx error rate > 5% for 2m   |
| HighLatency       | warning  | p99 latency > 1s for 2m      |
| ServiceDown       | critical | App unreachable for 1m       |
| HighRequestRate   | warning  | Request rate > 100/s for 2m  |

## Scaling

### Manual scaling via Terraform

```bash
terraform apply -var="app_replicas=4"
```

### Auto-scaling (Prometheus-driven)

The auto-scaler queries Prometheus every 30s and adjusts replicas based on request rate.

**Enable auto-scaling on the server:**

```bash
sudo cp scripts/autoscale.service /etc/systemd/system/
sudo cp scripts/autoscale.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now autoscale.timer
```

**Check status:**

```bash
systemctl status autoscale.timer
journalctl -u autoscale.service -f
```

**Thresholds** (configurable in `scripts/autoscale.sh`):

| Parameter | Value | Description |
|-----------|-------|-------------|
| `SCALE_UP_THRESHOLD` | 50 req/s | Scale up when rate exceeds this |
| `SCALE_DOWN_THRESHOLD` | 10 req/s | Scale down when rate drops below |
| `MAX_REPLICAS` | 5 | Absolute ceiling |
| `MIN_REPLICAS` | 1 | Absolute floor |
| `COOLDOWN_SECONDS` | 60 | Minimum time between scale operations |

### Verify scaling during load test

```bash
# Terminal 1: Run locust (web UI at http://localhost:8089)
docker run --rm --network host sre-final-locust -f locustfile.py --host=http://localhost:80

# Terminal 2: Watch autoscale logs
journalctl -u autoscale.service -f

# Browser: Grafana SLI dashboard
# http://192.168.1.65:3000/d/sre-sli-dashboard
```
