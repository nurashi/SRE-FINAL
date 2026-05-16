FROM golang:1.23-alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /build/server .

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata

RUN adduser -D -s /bin/sh appuser

USER appuser
WORKDIR /app

COPY --from=builder /build/server .

EXPOSE 8080

ENTRYPOINT ["./server"]
