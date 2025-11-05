# Platform Infrastructure

This repository contains the Docker Compose configuration for the platform infrastructure that supports GraphQL Federation architecture with shared services.

## Services

- **GraphQL Gateway (Apollo Router)**: Port 4000 - Composes subgraphs into a unified supergraph
- **Kafka**: Port 9092 - Message bus for inter-service communication
- **Zookeeper**: Port 2181 - Kafka coordination service
- **PostgreSQL**: Port 5432 - Shared database service

## Quick Start

1. Copy environment template:
   ```bash
   cp .env.template .env
   ```

2. Start all services:
   ```bash
   docker-compose up -d
   ```

3. Check service health:
   ```bash
   docker-compose ps
   ```

## Configuration

All services are configured via environment variables in the `.env` file. Key configurations:

- `PRODUCTS_SERVICE_URL`: URL for Products subgraph service
- `RATINGS_SERVICE_URL`: URL for Ratings subgraph service
- `POSTGRES_MULTIPLE_DATABASES`: Comma-separated list of databases to create
- `GRAPHQL_GATEWAY_PORT`: Port for GraphQL Gateway

## Data Persistence

The following volumes are created for data persistence:
- `postgres-data`: PostgreSQL database files
- `kafka-data`: Kafka message logs
- `zookeeper-data`: Zookeeper data files
- `zookeeper-logs`: Zookeeper transaction logs

## Health Checks

All services include health checks that verify:
- PostgreSQL: Database connectivity
- Kafka: Broker API availability
- Zookeeper: Client port accessibility
- GraphQL Gateway: Health endpoint response

## Network

Services communicate via the `platform-infrastructure` Docker network, allowing domain services to connect using service names as hostnames.