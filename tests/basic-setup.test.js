// Basic setup tests to verify test infrastructure works
describe('Basic Setup', () => {
  test('should have test configuration available', () => {
    expect(global.testConfig).toBeDefined();
    expect(global.testConfig.services).toBeDefined();
    expect(global.testConfig.services.postgres).toBeDefined();
    expect(global.testConfig.services.kafka).toBeDefined();
    expect(global.testConfig.services.graphqlGateway).toBeDefined();
  });

  test('should have utility functions available', () => {
    expect(global.waitFor).toBeDefined();
    expect(global.execCommand).toBeDefined();
    expect(typeof global.waitFor).toBe('function');
    expect(typeof global.execCommand).toBe('function');
  });

  test('should be able to execute basic docker commands', () => {
    const result = execCommand('docker --version');
    expect(result).toContain('Docker version');
  });

  test('should be able to check docker compose configuration', () => {
    const result = execCommand('docker compose -f docker-compose.yml config --quiet');
    // Should not throw an error if config is valid
    expect(result).toBeDefined();
  });
});