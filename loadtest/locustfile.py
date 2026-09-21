from locust import HttpUser, task, between

class ClusterLoadTestUser(HttpUser):
    # Default target host points to NGINX Ingress on host machine via Podman network
    host = "http://host.containers.internal"
    wait_time = between(0.1, 0.5)

    @task(3)
    def test_nodejs_service(self):
        self.client.get("/api/v1/nodejs/info", name="1. Node.js - /info")

    @task(3)
    def test_golang_service(self):
        self.client.get("/api/v1/golang/products", name="2. Golang - /products")

    @task(2)
    def test_java_service(self):
        self.client.get("/api/v1/java/users", name="3. Java - /users")

    @task(2)
    def test_interservice_call(self):
        self.client.get("/api/v1/nodejs/call-golang", name="4. InterService - Node.js -> Go")

    @task(1)
    def test_health_checks(self):
        self.client.get("/api/v1/nodejs/healthz", name="5. Node.js - /healthz")
        self.client.get("/api/v1/golang/healthz", name="6. Golang - /healthz")
        self.client.get("/api/v1/java/healthz", name="7. Java - /healthz")
