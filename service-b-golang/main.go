package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"go.elastic.co/apm/module/apmhttp/v2"
)

type Product struct {
	ID    int     `json:"id"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

type ProductsResponse struct {
	Service     string    `json:"service"`
	Language    string    `json:"language"`
	Hostname    string    `json:"hostname"`
	Environment string    `json:"environment"`
	DatabaseURL string    `json:"databaseUrl"`
	Products    []Product `json:"products"`
	Timestamp   time.Time `json:"timestamp"`
}

type HealthResponse struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
}

func main() {
	port := getEnv("PORT", "8080")
	serviceName := getEnv("SERVICE_NAME", "service-b-golang")
	appEnv := getEnv("APP_ENV", "development")
	dbURL := getEnv("DATABASE_URL", "postgres://localhost:5432/defaultdb")

	hostname, _ := os.Hostname()

	http.Handle("/api/v1/golang/products", apmhttp.Wrap(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		resp := ProductsResponse{
			Service:     serviceName,
			Language:    "Golang",
			Hostname:    hostname,
			Environment: appEnv,
			DatabaseURL: dbURL,
			Products: []Product{
				{ID: 101, Name: "Kubernetes Handbook", Price: 29.99},
				{ID: 102, Name: "Podman Essentials", Price: 19.99},
				{ID: 103, Name: "Microservices Architecture Guide", Price: 39.99},
			},
			Timestamp: time.Now(),
		}
		json.NewEncoder(w).Encode(resp)
	})))

	http.HandleFunc("/api/v1/golang/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(HealthResponse{Status: "HEALTHY", Timestamp: time.Now()})
	})

	http.HandleFunc("/api/v1/golang/readyz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(HealthResponse{Status: "READY", Timestamp: time.Now()})
	})

	addr := fmt.Sprintf(":%s", port)
	log.Printf("[%s] Server listening on %s in %s mode...\n", serviceName, addr, appEnv)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}
