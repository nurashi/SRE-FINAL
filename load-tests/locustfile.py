from locust import HttpUser, task, between, events
import random
import time


class SREFinalUser(HttpUser):
    wait_time = between(0.1, 1.0)
    host = "http://localhost:8080"

    def on_start(self):
        self.client.headers = {
            "Content-Type": "application/json",
            "Host": "sre-nurashi.abzy.kz",
        }

    @task(6)
    def get_tasks(self):
        self.client.get("/api/v1/tasks", timeout=10)

    @task(3)
    def create_task(self):
        payload = {
            "title": f"Task generated-{random.randint(1, 100000)}",
            "description": f"Load test task at {time.time()}",
        }
        with self.client.post("/api/v1/tasks", json=payload, catch_response=True) as resp:
            if resp.status_code != 201 and resp.status_code != 200:
                resp.failure(f"Expected 201, got {resp.status_code}: {resp.text}")

    @task(2)
    def compute(self):
        n = random.randint(100000, 500000)
        self.client.get(f"/api/v1/compute?n={n}", timeout=30, name="/api/v1/compute")

    @task(2)
    def get_task_by_id(self):
        task_id = random.randint(1, 50)
        self.client.get(f"/api/v1/tasks/{task_id}", timeout=10)

    @task(1)
    def health_check(self):
        self.client.get("/health", timeout=5)

    @task(1)
    def update_task(self):
        task_id = random.randint(1, 50)
        payload = {"completed": True}
        self.client.put(f"/api/v1/tasks/{task_id}", json=payload, timeout=10)

    @task(1)
    def delete_task(self):
        task_id = random.randint(1, 50)
        self.client.delete(f"/api/v1/tasks/{task_id}", timeout=10)


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print(f"Load test starting at {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Target: {environment.host}")
