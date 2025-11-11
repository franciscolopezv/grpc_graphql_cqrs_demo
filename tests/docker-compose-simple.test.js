// Simplified Docker Compose orchestration tests
// Tests Requirements: 4.1, 4.3 - Docker Compose configuration and service dependencies

const { Client } = require('pg');

describe('Docker Compose Basic Services', () => {
  beforeEach(async () => {
    // Ensure clean state before each test
    try {
      execCommand('docker compose -f docker-compose.yml down -v --remove-orphans');
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

  describe('Core Infrastructure Services', () => {
    test('should start PostgreSQL, Kafka, and Zookeeper services', async () => {
      // Start only the core services (exclude GraphQL Gateway for now)
      execCommand('docker compose -f docker-compose.yml up -d zookeeper kafka postgres');
      
      // Wait for services to be running
      await waitFor(async () => {
        try {
          const output = execCommand('docker compose -f docker-compose.yml ps --format json');
          const services = JSON.parse(`[${output.split('\n').join(',')}]`);
          
          const runningServices = services.filter(s => s.State === 'running');
          return runningServices.length >= 3; // zookeeper, kafka, postgres
        } catch (error) {
          return false;
        }
      }, testConfig.timeouts.serviceStart);
      
      // Verify services are running
      const output = execCommand('docker compose -f docker-compose.yml ps --format json');
      const services = JSON.parse(`[${output.split('\n').join(',')}]`);
      
      const serviceNames = services.map(s => s.Service);
      expect(serviceNames).toContain('zookeeper');
      expect(serviceNames).toContain('kafka');
      expect(serviceNames).toContain('postgres');
      
      services.forEach(service => {
        expect(service.State).toBe('running');
      });
    });

    test('should create persistent volumes for data storage', async () => {
      // Start core services
      execCommand('docker compose -f docker-compose.yml up -d zookeeper kafka postgres');
      
      // Wait for services to be running
      await waitFor(async () => {
        try {
          const output = execCommand('docker compose -f docker-compose.yml ps --format json');
          const services = JSON.parse(`[${output.split('\n').join(',')}]`);
          return services.filter(s => s.State === 'running').length >= 3;
        } catch (error) {
          return false;
        }
      });
      
      // Check that volumes are created
      const volumes = execCommand('docker volume ls --format "{{.Name}}"').split('\n').filter(v => v.trim());
      
      // Look for volumes with the project prefix
      const projectVolumes = volumes.filter(v => 
        v.includes('zookeeper-data') || 
        v.includes('kafka-data') || 
        v.includes('postgres-data')
      );
      
      expect(projectVolumes.length).toBeGreaterThanOrEqual(3);
    });

    test('should allow PostgreSQL connections and data persistence', async () => {
      // Start PostgreSQL
      execCommand('docker compose -f docker-compose.yml up -d postgres');
      
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
      }, testConfig.timeouts.serviceStart);
      
      // Test database connection and basic operations
      const client = new Client({
        host: testConfig.services.postgres.host,
        port: testConfig.services.postgres.port,
        user: testConfig.services.postgres.user,
        password: testConfig.services.postgres.password,
        database: 'products_db'
      });
      
      await client.connect();
      
      // Create test table and insert data
      await client.query('CREATE TABLE IF NOT EXISTS test_integration (id SERIAL PRIMARY KEY, name TEXT)');
      await client.query("INSERT INTO test_integration (name) VALUES ('test_value')");
      
      // Verify data was inserted
      const result = await client.query('SELECT name FROM test_integration WHERE name = $1', ['test_value']);
      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].name).toBe('test_value');
      
      await client.end();
    });

    test('should verify Kafka service is accessible', async () => {
      // Start Kafka and Zookeeper
      execCommand('docker compose -f docker-compose.yml up -d zookeeper kafka');
      
      // Wait for Kafka to be ready
      await waitFor(async () => {
        try {
          execCommand('docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092');
          return true;
        } catch (error) {
          return false;
        }
      }, testConfig.timeouts.serviceStart);
      
      // Verify Kafka is responding
      const kafkaCheck = execCommand('docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092');
      expect(kafkaCheck).toContain('broker');
    });
  });

  describe('Service Health Checks', () => {
    test('should report healthy status for core services', async () => {
      // Start core services
      execCommand('docker compose -f docker-compose.yml up -d zookeeper kafka postgres');
      
      // Wait for all services to be healthy
      await waitFor(async () => {
        try {
          // Check Zookeeper health
          execCommand('docker exec zookeeper nc -z localhost 2181');
          
          // Check Kafka health
          execCommand('docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092');
          
          // Check PostgreSQL health
          execCommand('docker exec postgres pg_isready -U postgres');
          
          return true;
        } catch (error) {
          return false;
        }
      }, testConfig.timeouts.serviceStart);
      
      // Verify individual health checks pass
      expect(() => execCommand('docker exec zookeeper nc -z localhost 2181')).not.toThrow();
      expect(() => execCommand('docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092')).not.toThrow();
      expect(() => execCommand('docker exec postgres pg_isready -U postgres')).not.toThrow();
    });
  });
});