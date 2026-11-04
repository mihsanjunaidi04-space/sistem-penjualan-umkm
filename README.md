# Sistem Informasi Penjualan UMKM

Backend: Ruby on Rails 8.1.4 API-only | Database: SQLite | Testing: RSpec

## Tech Stack

- **Backend**: Ruby on Rails 8.1.4 (API-only)
- **Database**: SQLite 3 (development & test)
- **Web Server**: Puma
- **Testing**: RSpec Rails 6.1.5
- **Ruby**: 4.0.7

## Prerequisites

- Ruby 4.0.7+
- Bundler
- Git

## Setup

### 1. Clone repository
```bash
git clone <repository-url>
cd sistem-penjualan-umkm
```

### 2. Install dependencies
```bash
bundle install
```

### 3. Create databases
```bash
rails db:create
```

### 4. Run development server
```bash
rails s
```
Server starts on `http://localhost:3000`

### 5. Health check
```bash
curl http://localhost:3000/health
```

Expected response:
```json
{
  "success": true,
  "data": { "status": "ok" },
  "message": "Health check passed"
}
```

## Running Tests

### Run all tests
```bash
rspec
```

### Run specific test file
```bash
rspec spec/requests/health_check_spec.rb
```

### Run tests with progress formatter
```bash
rspec --format progress
```

## Database

- **Development**: `db/development.sqlite3`
- **Test**: `db/test.sqlite3`
- **Production**: See `config/database.yml` (not validated for M1)

Database files are excluded from Git (see `.gitignore`).

## API Documentation

See `docs/API_DOCUMENTATION.md` for endpoint specifications.

## Security

- CORS configured for development origin: `http://localhost:5173` (future frontend)
- Parameter filtering excludes sensitive data from logs (password, token, etc)
- Database credentials managed via environment variables

## Architecture Decision

- **Authentication**: JWT Bearer Token (to be implemented M4)
- **CORS**: Allowlist only (no wildcard)
- **Database**: SQLite for development/test; production database not validated in M1

## Environment

Configuration follows Rails 8 conventions:
- Development: verbose logging, eager loading disabled
- Test: minimal logging, transactional database cleanup
- Production: not configured for M1

## Git & Secrets

- `.env` file excluded from Git (create from `.env.example` if needed)
- `config/master.key` excluded from Git
- Database files (`db/*.sqlite3*`) excluded from Git

## Milestone

This is **M1 — Backend Foundation**. See `docs/DEVELOPMENT_PLAN.md` for full project roadmap.

Frontend (React + Vite) will be added in M3.
