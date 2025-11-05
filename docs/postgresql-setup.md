# PostgreSQL Database Setup and Connection Guide

## Overview

The platform infrastructure provides a shared PostgreSQL database service that domain teams can use for data persistence. The database service is configured to support multiple databases for different domains while maintaining proper isolation and shared infrastructure management.

## Database Configuration

### Available Databases

The PostgreSQL service creates the following databases by default:
- `products_db` - For the Products domain team
- `ratings_db` - For the Ratings domain team  
- `platform_db` - For platform-level data and configuration

### Connection Parameters

**Host**: `postgres` (within Docker network) or `localhost` (from host machine)
**Port**: `5432` (default, configurable via `POSTGRES_PORT`)
**Username**: `platform_user` (configurable via `POSTGRES_USER`)
**Password**: `platform_password` (configurable via `POSTGRES_PASSWORD`)

### Environment Variables

The following environment variables control the PostgreSQL configuration:

```bash
# Database credentials
POSTGRES_USER=platform_user
POSTGRES_PASSWORD=platform_password
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# Multiple database configuration
POSTGRES_MULTIPLE_DATABASES=products_db,ratings_db,platform_db
```

## Docker Network Configuration

### Service-to-Service Connections

When connecting from other Docker services within the same Docker Compose network, use the service hostname:

```yaml
# Example service configuration
services:
  your-service:
    image: your-app:latest
    environment:
      DATABASE_URL: postgresql://platform_user:platform_password@postgres:5432/products_db
    depends_on:
      postgres:
        condition: service_healthy
```

### Connection String Examples

**Products Service Connection**:
```
postgresql://platform_user:platform_password@postgres:5432/products_db
```

**Ratings Service Connection**:
```
postgresql://platform_user:platform_password@postgres:5432/ratings_db
```

**Platform Service Connection**:
```
postgresql://platform_user:platform_password@postgres:5432/platform_db
```

### Host Machine Connections

For development tools or applications running on the host machine:

```bash
# Connection string for host machine access
postgresql://platform_user:platform_password@localhost:5432/products_db

# Using psql from host machine
psql -h localhost -p 5432 -U platform_user -d products_db
```

## Database Creation and Migration Workflows

### Adding New Databases

To add a new database for a domain team:

1. **Update Environment Configuration**:
   ```bash
   # Add your new database to the POSTGRES_MULTIPLE_DATABASES variable
   POSTGRES_MULTIPLE_DATABASES=products_db,ratings_db,platform_db,your_new_db
   ```

2. **Restart PostgreSQL Service**:
   ```bash
   docker-compose down postgres
   docker-compose up -d postgres
   ```

3. **Verify Database Creation**:
   ```bash
   # Connect and list databases
   docker-compose exec postgres psql -U platform_user -c "\l"
   ```

### Schema Migration Best Practices

#### 1. Migration Scripts Organization

Create migration scripts in your service repository:
```
your-service/
├── migrations/
│   ├── 001_initial_schema.sql
│   ├── 002_add_user_table.sql
│   └── 003_add_indexes.sql
└── scripts/
    └── run-migrations.sh
```

#### 2. Migration Script Template

```sql
-- Migration: 001_initial_schema.sql
-- Description: Create initial database schema
-- Date: 2024-01-01

BEGIN;

-- Create your tables
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Insert any seed data if needed
INSERT INTO users (email) VALUES ('admin@example.com') ON CONFLICT DO NOTHING;

COMMIT;
```

#### 3. Running Migrations

**Option 1: Using Docker Exec**
```bash
# Copy migration file to container
docker cp ./migrations/001_initial_schema.sql postgres:/tmp/

# Execute migration
docker-compose exec postgres psql -U platform_user -d products_db -f /tmp/001_initial_schema.sql
```

**Option 2: Using Volume Mount**
```yaml
# Add to your service in docker-compose.yml
services:
  your-service:
    volumes:
      - ./migrations:/app/migrations:ro
    command: |
      sh -c "
        # Wait for database to be ready
        until pg_isready -h postgres -p 5432 -U platform_user; do sleep 1; done
        
        # Run migrations
        for migration in /app/migrations/*.sql; do
          psql postgresql://platform_user:platform_password@postgres:5432/products_db -f $$migration
        done
        
        # Start your application
        exec your-app
      "
```

#### 4. Migration Tracking

Create a migrations tracking table:
```sql
-- Create migration tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Track applied migration
INSERT INTO schema_migrations (version) VALUES ('001_initial_schema') ON CONFLICT DO NOTHING;
```

### Database Backup and Recovery

#### Creating Backups

```bash
# Backup specific database
docker-compose exec postgres pg_dump -U platform_user products_db > products_db_backup.sql

# Backup all databases
docker-compose exec postgres pg_dumpall -U platform_user > all_databases_backup.sql
```

#### Restoring from Backup

```bash
# Restore specific database
docker-compose exec -T postgres psql -U platform_user products_db < products_db_backup.sql

# Restore all databases
docker-compose exec -T postgres psql -U platform_user < all_databases_backup.sql
```

## Connection Pooling

The PostgreSQL service supports connection pooling. For production deployments, consider using a connection pooler like PgBouncer:

```yaml
# Example PgBouncer configuration (optional)
services:
  pgbouncer:
    image: pgbouncer/pgbouncer:latest
    environment:
      DATABASES_HOST: postgres
      DATABASES_PORT: 5432
      DATABASES_USER: platform_user
      DATABASES_PASSWORD: platform_password
      DATABASES_DBNAME: products_db
      POOL_MODE: transaction
      MAX_CLIENT_CONN: 100
      DEFAULT_POOL_SIZE: 20
    ports:
      - "6432:6432"
    depends_on:
      postgres:
        condition: service_healthy
```

## Health Checks and Monitoring

### Database Health Check

The PostgreSQL service includes a health check that verifies the database is ready to accept connections:

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U platform_user"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### Monitoring Database Status

```bash
# Check service health
docker-compose ps postgres

# View database logs
docker-compose logs postgres

# Connect and check database status
docker-compose exec postgres psql -U platform_user -c "SELECT version();"

# List all databases
docker-compose exec postgres psql -U platform_user -c "\l"

# Check active connections
docker-compose exec postgres psql -U platform_user -c "SELECT * FROM pg_stat_activity;"
```

## Security Considerations

### 1. Password Management

- Use strong passwords in production environments
- Store credentials in environment variables, not in code
- Consider using Docker secrets for sensitive data in production

### 2. Network Security

- The PostgreSQL service is only accessible within the Docker network by default
- External access is only available through the exposed port (5432)
- Use firewall rules to restrict access in production environments

### 3. Database Permissions

- Each domain team should only access their designated database
- Consider creating separate database users for each domain in production
- Implement proper role-based access control (RBAC)

## Troubleshooting

### Common Issues

#### 1. Connection Refused
```bash
# Check if PostgreSQL service is running
docker-compose ps postgres

# Check service logs
docker-compose logs postgres

# Restart the service
docker-compose restart postgres
```

#### 2. Authentication Failed
```bash
# Verify environment variables
docker-compose exec postgres env | grep POSTGRES

# Check user exists
docker-compose exec postgres psql -U platform_user -c "\du"
```

#### 3. Database Does Not Exist
```bash
# List available databases
docker-compose exec postgres psql -U platform_user -c "\l"

# Recreate databases
docker-compose down postgres
docker-compose up -d postgres
```

#### 4. Permission Denied
```bash
# Check database permissions
docker-compose exec postgres psql -U platform_user -d products_db -c "\dp"

# Grant necessary permissions
docker-compose exec postgres psql -U platform_user -c "GRANT ALL PRIVILEGES ON DATABASE products_db TO platform_user;"
```

## Performance Optimization

### 1. Configuration Tuning

For production environments, consider tuning PostgreSQL configuration:

```yaml
# Add to postgres service environment
environment:
  POSTGRES_SHARED_PRELOAD_LIBRARIES: pg_stat_statements
  POSTGRES_MAX_CONNECTIONS: 200
  POSTGRES_SHARED_BUFFERS: 256MB
  POSTGRES_EFFECTIVE_CACHE_SIZE: 1GB
  POSTGRES_WORK_MEM: 4MB
```

### 2. Index Optimization

- Create appropriate indexes for your queries
- Monitor query performance using `EXPLAIN ANALYZE`
- Use `pg_stat_statements` extension for query analysis

### 3. Connection Management

- Use connection pooling for high-traffic applications
- Monitor connection counts and adjust pool sizes accordingly
- Close connections properly in application code

## Support and Resources

### Getting Help

1. **Check Service Status**: `docker-compose ps postgres`
2. **View Logs**: `docker-compose logs postgres`
3. **Database Console**: `docker-compose exec postgres psql -U platform_user`

### Additional Resources

- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/)
- [Docker PostgreSQL Image Documentation](https://hub.docker.com/_/postgres)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)