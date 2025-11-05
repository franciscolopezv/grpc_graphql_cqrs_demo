# Platform Infrastructure Integration Tests

This directory contains integration tests for the platform infrastructure components, including Docker Compose orchestration and GraphQL Gateway functionality.

## Test Structure

- `basic-setup.test.js` - Basic test infrastructure validation
- `docker-compose.test.js` - Full Docker Compose orchestration tests (comprehensive)
- `docker-compose-simple.test.js` - Simplified Docker Compose tests (core services only)
- `graphql-gateway.test.js` - Full GraphQL Gateway tests (with infrastructure)
- `graphql-gateway-simple.test.js` - Mock-based GraphQL Gateway tests (fast)

## Requirements

- Node.js 16+
- Docker and Docker Compose
- npm or yarn

## Installation

```bash
npm install
```

## Running Tests

### All Tests
```bash
npm test
```

### Specific Test Categories
```bash
# Basic setup validation
npm test -- --testPathPattern=basic-setup

# Docker Compose tests (simplified, faster)
npm test -- --testPathPattern=docker-compose-simple

# GraphQL Gateway tests (mock-based, fast)
npm test -- --testPathPattern=graphql-gateway-simple

# Full Docker Compose tests (slower, requires Docker)
npm test -- --testPathPattern=docker-compose

# Full GraphQL Gateway tests (requires infrastructure)
npm test -- --testPathPattern=graphql-gateway
```

### Individual Tests
```bash
# Run a specific test
npm test -- --testNamePattern="should start PostgreSQL, Kafka, and Zookeeper services"
```

## Test Categories

### 1. Basic Setup Tests
- Validates test infrastructure is working
- Checks Docker availability
- Verifies configuration files

### 2. Docker Compose Orchestration Tests
- **Requirements Tested**: 4.1, 4.3
- Service startup and dependency resolution
- Persistent volume configuration
- Health check validation
- Service restart handling

### 3. GraphQL Gateway Functionality Tests
- **Requirements Tested**: 1.2, 1.3, 1.4, 1.5
- Schema composition from subgraph services
- Query routing to appropriate services
- Response consolidation from multiple subgraphs
- Error handling for unavailable services

## Mock Services

The GraphQL Gateway tests use mock Express.js servers that simulate:

### Products Service (Port 8081)
- GraphQL schema with Product type
- Federation directives (@key)
- Health check endpoint
- Sample product data

### Ratings Service (Port 8082)
- GraphQL schema with Product ratings extension
- Federation directives for entity extension
- Rating statistics and distribution data
- Health check endpoint

## Test Configuration

Test configuration is defined in `setup.js`:

```javascript
global.testConfig = {
  services: {
    postgres: { host: 'localhost', port: 5432, ... },
    kafka: { brokers: ['localhost:9092'], ... },
    graphqlGateway: { url: 'http://localhost:4000', ... }
  },
  timeouts: {
    serviceStart: 60000,
    healthCheck: 30000,
    connection: 10000
  }
}
```

## Utilities

### waitFor(condition, timeout, interval)
Waits for a condition to be met within a timeout period.

### execCommand(command, options)
Executes shell commands with error handling.

## Notes

- Tests use `--runInBand` to avoid conflicts between parallel Docker operations
- Each test suite cleans up Docker containers and volumes after execution
- Mock services are created and destroyed for each test suite
- Timeouts are configured for CI/CD environments where services may start slowly

## Troubleshooting

### Docker Issues
- Ensure Docker daemon is running
- Check available disk space for volumes
- Verify port availability (4000, 5432, 9092, 2181, 8081, 8082)

### Test Timeouts
- Increase timeout values in `setup.js` for slower environments
- Use simplified tests (`*-simple.test.js`) for faster feedback

### Network Issues
- Ensure no other services are using the required ports
- Check firewall settings for local connections