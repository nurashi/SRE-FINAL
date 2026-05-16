package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/nurashi/sre-final/api"
	"github.com/nurashi/sre-final/repository"
	"github.com/nurashi/sre-final/service"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	reg := prometheus.NewRegistry()
	reg.MustRegister(collectRequestDuration, collectRequestsTotal, collectRequestsInFlight)

	repo := repository.NewTaskRepository()
	svc := service.NewTaskService(repo)
	router := api.NewRouter(svc)

	engine := router.Setup()
	engine.Use(MetricsMiddleware())

	engine.GET("/metrics", func(c *gin.Context) {
		h := promhttp.HandlerFor(reg, promhttp.HandlerOpts{Registry: reg})
		h.ServeHTTP(c.Writer, c.Request)
	})

	srv := &http.Server{
		Addr:         ":" + getPort(),
		Handler:      engine,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("Server starting on %s", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	log.Printf("Received signal %v, shutting down gracefully", sig)

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("Server forced to shutdown: %v", err)
	}

	log.Println("Server stopped")
}

func getPort() string {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	return port
}
