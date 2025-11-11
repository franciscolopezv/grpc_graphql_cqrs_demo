# Local Development Setup Guide

This guide explains how to set up the platform infrastructure and individual services for local development across multiple repositories.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                 Docker Network: platform-infrastructure         │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐ │
│  │ Platform Infra  │    │ Products Repo   │    │ Ratings Repo│ │
│  │ (This Repo)     │    │                 │    │             │ │
│  │                 │    │                 │    │             │ │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────┐ │ │
│  │ │ PostgreSQL  │ │    │ │ Products    │ │    │ │ Ratings │ │ │
│  │ │ :5432       │ │◄───┼─│ Service     │ │    │ │ Service │ │ │
│  │ └─────────────┘ │    │ │ :8081       │ │    │ │ :8082   │ │ │
│  │                 │    │ └─────────────┘ │    │ └─────────┘ │ │
│  │ ┌─────────────┐ │    └─────────────────┘    └─────────────┘ │
│  │ │ Kafka       │ │                                           │
│  │ │ :29092      │ │◄──────────────────────────────────────────┤
│  │ └─────────────┘ │                                           │
│  │                 │                                           │
│  │ ┌─────────────┐ │                                           │
│  │ │ GraphQL     │ │◄──────────────────────────────────────────┤
│  │ │ Gateway     │ │                                           │
│  │ │ :4000       │ │                                           │
│  │ └─────────────┘ │                                           │
│  └─────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### 1. Setup Platform Infrastructure (This Repository)

```bash
# Clone the platform infrastructure repository
git clone <platform-infrastructure-repo>
cd platform-infrastructure

# Create the shared Docker network
./scripts/setup-network.sh

# Start the platform services
docker compose up -d

# Verify services are running
docker compose ps
```

### 2. Setup Individual Services (Other Repositories)

For each service repository (Products, Ratings, etc.):

```bash
# Clone the service repository
git clone <service-repo>
cd <service-repo>

# Copy the docker-compose template
curl -o docker-compose.yml https://raw.githubusercontent.com/your-org/platform-infrastructure/main/docs/examples/service-docker-compose-template.yml

# Customize the docker-compose.yml for your service
# (Update service name, ports, environment variables)

# Start your service
docker compose up -d

# Register with GraphQL Gateway (if GraphQL service)
cd ../platform-infrastructure
./scripts/register-service.sh your-service http://your-service:8080
```

## 📋 Detailed Setup Instructions

### Platform Infrastructure Setup

1. **Create Shared Network**
   ```bash
   ./scripts/setup-network.sh
   ```
   This creates a Docker network named `platform-infrastructure` that all services will use.

2. **Configure Environment**
   ```bash
   cp .env.template .env
   # Edit .env with your local configuration
   ```

3. **Start Infrastructure Services**
   ```bash
   docker compose up -d
   ```

4. **Verify Setup**
   ```bash
   # Check all services are healthy
   docker compose ps
   
   # Test GraphQL Gateway
   curl http://localhost:4000/health
   
   # Test PostgreSQL
   docker exec postgres pg_isready -U postgres
   
   # Test Kafka
   docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092
   ```

### Service Repository Setup

#### 1. Create docker-compose.yml

```yaml
version: '3.8'

services:
  your-service:
    build: .
    container_name: your-service
    hostname: your-service
    ports:
      - "8080:8080"
    environment:
      # Database connection
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/your_db
      
      # Kafka connection
      KAFKA_BROKERS: kafka:29092
      
      # Service configuration
      PORT: 8080
      NODE_ENV: development
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

# Use shared network
networks:
  default:
    name: platform-infrastructure
    external: true
```

#### 2. Update Service Configuration

Ensure your service connects to shared infrastructure:

```javascript
// Database connection
const DATABASE_URL = process.env.DATABASE_URL || 'postgresql://postgres:postgres@postgres:5432/your_db';

// Kafka connection
const kafka = require('kafkajs').kafka({
  clientId: 'your-service',
  brokers: ['kafka:29092']
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'your-service',
    timestamp: new Date().toISOString()
  });
});
```

#### 3. GraphQL Federation (if applicable)

For GraphQL services, implement Federation support:

```javascript
// Federation schema endpoint
app.get('/_service', (req, res) => {
  res.json({
    sdl: `
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"])
      
      type YourEntity @key(fields: "id") {
        id: ID!
        # Your fields here
      }
      
      type Query {
        # Your queries here
      }
    `
  });
});
```

## 🔧 Development Workflow

### Starting Everything

```bash
# 1. Start platform infrastructure
cd platform-infrastructure
docker compose up -d

# 2. Start individual services (in separate terminals)
cd ../products-service
docker compose up -d

cd ../ratings-service
docker compose up -d

# 3. Register GraphQL services (if needed)
cd ../platform-infrastructure
./scripts/register-service.sh products http://products-service:8081
./scripts/register-service.sh ratings http://ratings-service:8082
```

### Development with Hot Reload

For active development, you can mount source code:

```yaml
# In service docker-compose.yml
services:
  your-service:
    # ... other config
    volumes:
      - .:/app
      - /app/node_modules
    command: npm run dev  # Use development command
```

### Testing Service Communication

```bash
# Test database connectivity from service
docker exec your-service psql postgresql://postgres:postgres@postgres:5432/your_db -c "SELECT 1"

# Test Kafka connectivity
docker exec your-service kafka-console-producer --bootstrap-server kafka:29092 --topic test

# Test GraphQL Gateway
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __schema { types { name } } }"}'
```

## 🛠️ Useful Commands

### Network Management

```bash
# List all containers on the network
docker network inspect platform-infrastructure

# Test connectivity between services
docker run --rm --network platform-infrastructure alpine ping postgres
docker run --rm --network platform-infrastructure alpine ping kafka
docker run --rm --network platform-infrastructure alpine ping graphql-gateway

# Remove network (stops all containers)
./scripts/cleanup-network.sh
```

### Service Management

```bash
# View logs from all platform services
docker compose logs -f

# View logs from specific service
docker compose logs -f postgres
docker logs your-service

# Restart specific service
docker compose restart graphql-gateway
docker restart your-service

# Stop all services
docker compose down
```

### Database Management

```bash
# Connect to PostgreSQL
docker exec -it postgres psql -U postgres -d products_db

# Create new database for service
docker exec postgres createdb -U postgres your_service_db

# Run database migrations
docker exec your-service npm run migrate
```

### Kafka Management

```bash
# List Kafka topics
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list

# Create topic
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --create --topic your-topic

# Consume messages
docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic your-topic --from-beginning
```

## 🐛 Troubleshooting

### Common Issues

1. **Service can't connect to database**
   ```bash
   # Check if PostgreSQL is running
   docker compose ps postgres
   
   # Check network connectivity
   docker exec your-service ping postgres
   
   # Check database exists
   docker exec postgres psql -U postgres -l
   ```

2. **GraphQL Gateway can't reach service**
   ```bash
   # Check service health
   curl http://localhost:8080/health
   
   # Check network connectivity
   docker exec graphql-gateway wget -O- http://your-service:8080/health
   
   # Check service registration
   docker logs graphql-gateway
   ```

3. **Port conflicts**
   ```bash
   # Check what's using the port
   lsof -i :8080
   
   # Use different port in docker-compose.yml
   ports:
     - "8081:8080"  # External:Internal
   ```

### Network Issues

```bash
# Recreate network
./scripts/cleanup-network.sh
./scripts/setup-network.sh

# Check network configuration
docker network inspect platform-infrastructure

# Test DNS resolution
docker run --rm --network platform-infrastructure alpine nslookup postgres
```

## 📚 Best Practices

### Service Configuration

1. **Use environment variables** for all configuration
2. **Implement health checks** for all services
3. **Use consistent naming** for containers and hostnames
4. **Document service dependencies** in README

### Development Workflow

1. **Start platform infrastructure first**
2. **Use docker-compose for each service**
3. **Register GraphQL services** after startup
4. **Monitor logs** during development

### Network Security

1. **Use internal network** for service communication
2. **Expose only necessary ports** to host
3. **Use strong passwords** for shared services
4. **Implement proper authentication** between services

This setup enables true microservices development with shared infrastructure while maintaining service independence!