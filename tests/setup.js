// Global test setup for platform infrastructure integration tests
const { execSync } = require('child_process');
const path = require('path');

// Increase timeout for integration tests
jest.setTimeout(120000);

// Global test configuration
global.testConfig = {
  // Docker Compose configuration
  dockerCompose: {
    file: path.join(__dirname, '..', 'docker-compose.yml'),
    project: 'platform-infrastructure-test'
  },
  
  // Service endpoints
  services: {
    postgres: {
      host: 'localhost',
      port: 5432,
      user: 'platform_user',
      password: 'platform_password',
      databases: ['products_db', 'ratings_db', 'platform_db']
    },
    kafka: {
      brokers: ['localhost:9092'],
      topics: ['products_events', 'ratings_events']
    },
    graphqlGateway: {
      url: 'http://localhost:4000',
      healthUrl: 'http://localhost:4000/health'
    },
    zookeeper: {
      host: 'localhost',
      port: 2181
    }
  },
  
  // Test timeouts
  timeouts: {
    serviceStart: 60000,
    healthCheck: 30000,
    connection: 10000
  }
};

// Utility function to wait for a condition
global.waitFor = async (condition, timeout = 30000, interval = 1000) => {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      const result = await condition();
      if (result) return result;
    } catch (error) {
      // Continue waiting
    }
    await new Promise(resolve => setTimeout(resolve, interval));
  }
  throw new Error(`Condition not met within ${timeout}ms`);
};

// Utility function to execute shell commands
global.execCommand = (command, options = {}) => {
  try {
    return execSync(command, { 
      encoding: 'utf8', 
      stdio: 'pipe',
      ...options 
    }).trim();
  } catch (error) {
    throw new Error(`Command failed: ${command}\n${error.message}`);
  }
};

console.log('Integration test setup completed');