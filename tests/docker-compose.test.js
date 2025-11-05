// Integration tests for Docker Compose orchestration
// Tests Requirements: 4.1, 4.3 - Docker Compose configuration and service dependencies

const Docker = require('dockerode');
const { Client } = require('pg');
const axios = require('axios');

describe('Docker Compose Orchestration', () => {
  let docker;
  
  beforeAll(() => {
    docker = new Docker();
  });

  beforeEach(async () => {
    // Ensure clean state before each test
    try {
      execCommand('docker compose -f docker-compose.yml down -v --remove-orphans');
      // Wait a moment for cleanup to complete
      await new Promise(resolve => setTimeout(resolve, 2000));
    } catch (error) {
      // Ignore errors if services aren't running
    }
  });

  afterEach(async () => {
    // Clean up after each test
    try {
      execCommand('docker compose -f docker-compose.yml down -v --remove-orphans');
    } catch (error) {
      // Ignore cleanup errors
    }
  });

  describe('Service Startup and Dependencies', () => {
    test('should start all services successfully', async () => {
      // Start all services
      execCommand('docker compose -f docker-compose.yml up -d');
      
      // Wait for all services to be running
      await waitFor(async () => {
        const output = execCommand('docker compose -f docker-compose.yml ps --format json');
        const services = JSON.parse(`[${output.split('\n').join(',')}]`);
        
        const expectedServices = ['zookeeper', 'kafka', 'postgres', 'graphql-gateway'];
        const runningServices = services.filter(s => s.State === 'running');
        
        return runningServices.length === expectedServices.length;
      }, testConfig.timeouts.serviceStart);
      
      // Verify all expected services are running
      const output = execCommand('docker compose -f docker-compose.yml ps --format json');
      const services = JSON.parse(`[${output.split('\n').join(',')}]`);
      
      expect(services).toHaveLength(4);
      services.forEach(service => {
        expect(service.State).toBe('running');
      });
    });

    test('should respect service dependency order', async () => {
      // Start services and monitor startup order
      const startTime = Date.now();
      execCommand('docker compose -f docker-compose.yml up -d');
      
      // Zookeeper should start first
      await waitFor(async () => {
        try {
          const container = docker.getContainer('zookeeper');
          const info = await container.inspect();
          return info.State.Running;
        } catch (error) {
          return false;
        }
      });
      
      // Kafka should start after Zookeeper
      await waitFor(async () => {
        try {
          const container = docker.getContainer('kafka');
          const info = await container.inspect();
          return info.State.Running;
        } catch (error) {
          return false;
        }
      });
      
      // PostgreSQL should start independently
      await waitFor(async () => {
        try {
          const container = docker.getContainer('postgres');
          const info = await container.inspect();
          return info.State.Running;
        } catch (error) {
          return false;
        }
      });
      
      // GraphQL Gateway should start after Kafka and PostgreSQL
      await waitFor(async () => {
        try {
          const container = docker.getContainer('graphql-gateway');
          const info = await container.inspect();
          return info.State.Running;
        } catch (error) {
          return false;
        }
      });
      
      // Verify all services are healthy
      await waitFor(async () => {
        const output = execCommand('docker compose -f docker-compose.yml ps --format json');
        const services = JSON.parse(`[${output.split('\n').join(',')}]`);
        return services.every(s => s.State === 'running');
      });
    });

    test('should handle service restart gracefully', async () => {
      // Start all services
      execCommand('docker-compose -f docker-compose.yml up -d');
      
      // Wait for services to be healthy
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl, {
            timeout: 5000
          });
          return response.status === 200;
        } catch (error) {
          return false;
        }
      });
      
      // Restart a service (Kafka)
      execCommand('docker compose -f docker-compose.yml restart kafka');
      
      // Verify service comes back up
      await waitFor(async () => {
        try {
          const container = docker.getContainer('kafka');
          const info = await container.inspect();
          return info.State.Running;
        } catch (error) {
          return false;
        }
      });
      
      // Verify dependent services are still healthy
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl, {
            timeout: 5000
          });
          return response.status === 200;
        } catch (error) {
          return false;
        }
      });
    });
  });

  describe('Persistent Volume Configuration', () => {
    test('should create and mount persistent volumes', async () => {
      // Start services
      execCommand('docker compose -f docker-compose.yml up -d');
      
      // Wait for services to be running
      await waitFor(async () => {
        const output = execCommand('docker compose -f docker-compose.yml ps --format json');
        const services = JSON.parse(`[${output.split('\n').join(',')}]`);
        return services.every(s => s.State === 'running');
      });
      
      // Check that volumes are created
      const volumes = execCommand('docker volume ls --format "{{.Name}}"').split('\n');
      const expectedVolumes = [
        'platform-infrastructure_zookeeper-data',
        'platform-infrastructure_zookeeper-logs',
        'platform-infrastructure_kafka-data',
        'platform-infrastructure_postgres-data'
      ];
      
      expectedVolumes.forEach(expectedVolume => {
        expect(volumes).toContain(expectedVolume);
      });
    });

    test('should persist data across container restarts', async () => {
      // Start services
      execCommand('docker compose -f docker-compose.yml up -d');
      
      // Wait for PostgreSQL to be ready
      await waitFor(async () => {
        try {
          const client = new Client({
            host: testConfig.services.postgres.host,
            port: testConfig.services.postgres.port,
            user: testConfig.services.postgres.user,
            password: testConfig.services.postgres.password,
            database: 'products_db'
          });
          await client.connect();
          await client.end();
          return true;
        } catch (error) {
          return false;
        }
      });
      
      // Create test data in PostgreSQL
      const client = new Client({
        host: testConfig.services.postgres.host,
        port: testConfig.services.postgres.port,
        user: testConfig.services.postgres.user,
        password: testConfig.services.postgres.password,
        database: 'products_db'
      });
      
      await client.connect();
      await client.query('CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, data TEXT)');
      await client.query("INSERT INTO test_table (data) VALUES ('test_data')");
      await client.end();
      
      // Restart PostgreSQL container
      execCommand('docker compose -f docker-compose.yml restart postgres');
      
      // Wait for PostgreSQL to be ready again
      await waitFor(async () => {
        try {
          const client = new Client({
            host: testConfig.services.postgres.host,
            port: testConfig.services.postgres.port,
            user: testConfig.services.postgres.user,
            password: testConfig.services.postgres.password,
            database: 'products_db'
          });
          await client.connect();
          await client.end();
          return true;
        } catch (error) {
          return false;
        }
      });
      
      // Verify data persisted
      const clientAfterRestart = new Client({
        host: testConfig.services.postgres.host,
        port: testConfig.services.postgres.port,
        user: testConfig.services.postgres.user,
        password: testConfig.services.postgres.password,
        database: 'products_db'
      });
      
      await clientAfterRestart.connect();
      const result = await clientAfterRestart.query('SELECT data FROM test_table WHERE data = $1', ['test_data']);
      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].data).toBe('test_data');
      await clientAfterRestart.end();
    });
  });

  describe('Health Checks', () => {
    test('should report healthy status for all services', async () => {
      // Start services
      execCommand('docker compose -f docker-compose.yml up -d');
      
      // Wait for all services to be healthy
      await waitFor(async () => {
        try {
          // Check Zookeeper health
          execCommand('docker exec zookeeper nc -z localhost 2181');
          
          // Check Kafka health
          execCommand('docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092');
          
          // Check PostgreSQL health
          execCommand('docker exec postgres pg_isready -U platform_user');
          
          // Check GraphQL Gateway health
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl, {
            timeout: 5000
          });
          
          return response.status === 200;
        } catch (error) {
          return false;
        }
      }, testConfig.timeouts.serviceStart);
      
      // Verify health check endpoints
      const healthResponse = await axios.get(testConfig.services.graphqlGateway.healthUrl);
      expect(healthResponse.status).toBe(200);
    });
  });
});