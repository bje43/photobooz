# Photobooz

A NestJS-based health monitoring service for photobooths. This service receives health pings from photobooths, tracks their status, and sends notifications to Slack.

## Project Structure

```
photobooz/
├── server/          # NestJS backend
│   ├── src/        # Source code
│   ├── prisma/     # Database schema and migrations
│   └── package.json # Server dependencies and scripts
├── client/          # React frontend
│   └── package.json # Client dependencies and scripts
└── package.json     # Root workspace coordination
```

## Features

- REST API endpoint for health pings from photobooths
- API key authentication
- PostgreSQL database with Prisma ORM for tracking photobooth health
- Slack integration for notifications
- Automatic alerting for stale photobooths (no health update in configured time)
- React client ready for dashboard development

## Setup

### Prerequisites

- Node.js 24.x (LTS) - Use `nvm use` to switch to the correct version
- PostgreSQL database (see [Local Database Setup](#local-database-setup) below)
- npm 10+

### Installation

1. Switch to the correct Node.js version (if using nvm):
```bash
nvm use
```

2. Install all dependencies (root, server, and client):
```bash
npm run install:all
```

Or install separately:
```bash
npm install              # Root dependencies (concurrently)
cd server && npm install # Server dependencies
cd ../client && npm install # Client dependencies
```

2. Set up environment variables:
```bash
cp .env.example .env
```

Edit `.env` and set:
- `DATABASE_URL` - PostgreSQL connection string (see [Local Database Setup](#local-database-setup) below)
- `API_KEY` - Secret API key for authenticating health pings from photobooths
- `JWT_SECRET` - Secret key for JWT token signing (use a strong random string)
- `SLACK_BOT_TOKEN` - (Optional) Slack bot token for sending alerts (obtain from https://api.slack.com/apps)
- `STALE_THRESHOLD_MINUTES` - (Optional) Minutes before alerting on stale booths (default: 15)
- `PORT` - (Optional) Port to run the server on (default: 3000)
- `CLIENT_URL` - (Optional) React client URL for CORS (default: http://localhost:5173)

3. Set up the database:
```bash
npm run prisma:migrate
```

4. Seed the database with default admin user:
```bash
npm run prisma:seed
```
This creates a default admin user (username: `admin`, password: `admin`). **Change the password immediately after first login!**

5. Generate Prisma client (runs automatically on server install, but you can run manually):
```bash
npm run prisma:generate
```

5. Start the development server:
```bash
npm run start:dev
```

Or start both server and client together:
```bash
npm run dev
```

### React Client Setup (Optional)

The project includes a React client in the `client/` directory. To set it up:

1. Install client dependencies:
```bash
npm run client:install
```

2. Start both backend and frontend together:
```bash
npm run dev
```

Or run them separately:
- Backend: `npm run start:dev` (runs on http://localhost:3000)
- Client: `npm run client:dev` (runs on http://localhost:5173)

The Vite dev server is configured to proxy `/api/*` requests to the backend, so you can make API calls using `/api/health/ping` from the React app.

## Local Database Setup

You have several options for setting up a local PostgreSQL database:

### Option 1: Docker (Recommended - Easiest)

1. Make sure Docker is installed and running
2. Run PostgreSQL in a container:
```bash
docker run --name photobooz-db \
  -e POSTGRES_USER=photobooz \
  -e POSTGRES_PASSWORD=photobooz \
  -e POSTGRES_DB=photobooz \
  -p 5432:5432 \
  -d postgres:15
```

3. Your `DATABASE_URL` in `.env` should be:
```
DATABASE_URL="postgresql://photobooz:photobooz@localhost:5432/photobooz?schema=public"
```

4. To stop the database:
```bash
docker stop photobooz-db
```

5. To start it again:
```bash
docker start photobooz-db
```

### Option 2: Homebrew (macOS)

1. Install PostgreSQL:
```bash
brew install postgresql@15
brew services start postgresql@15
```

2. Create the database:
```bash
createdb photobooz
```

3. Your `DATABASE_URL` in `.env` should be:
```
DATABASE_URL="postgresql://$(whoami)@localhost:5432/photobooz?schema=public"
```

Or if you set a password:
```
DATABASE_URL="postgresql://your_username:your_password@localhost:5432/photobooz?schema=public"
```

### Option 3: PostgreSQL.app (macOS - GUI)

1. Download and install [PostgreSQL.app](https://postgresapp.com/)
2. Open the app and click "Initialize" to create a new server
3. Click on a server, then "Open psql"
4. Create the database:
```sql
CREATE DATABASE photobooz;
```

5. Your `DATABASE_URL` in `.env` should be:
```
DATABASE_URL="postgresql://$(whoami)@localhost:5432/photobooz?schema=public"
```

### Option 4: Linux (apt)

1. Install PostgreSQL:
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
```

2. Start the service:
```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

3. Switch to the postgres user and create database:
```bash
sudo -u postgres psql
```

Then in the psql prompt:
```sql
CREATE DATABASE photobooz;
CREATE USER photobooz WITH PASSWORD 'photobooz';
GRANT ALL PRIVILEGES ON DATABASE photobooz TO photobooz;
\q
```

4. Your `DATABASE_URL` in `.env` should be:
```
DATABASE_URL="postgresql://photobooz:photobooz@localhost:5432/photobooz?schema=public"
```

### After Database Setup

Once your database is running and `DATABASE_URL` is set in `.env`, run migrations:

```bash
npm run prisma:migrate
```

This will create all the necessary tables in your database.

## API Usage

### Health Ping Endpoint

Send a POST request to `/health/ping` with an API key header:

```bash
curl -X POST http://localhost:3000/health/ping \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{
    "boothId": "booth-001",
    "name": "Main Event Booth",
    "status": "healthy",
    "message": "All systems operational",
    "metadata": {
      "temperature": "72F",
      "uptime": "5 days"
    }
  }'
```

**Request Body:**
- `boothId` (required): Unique identifier for the photobooth
- `name` (optional): Human-readable name for the booth
- `status` (required): Status string (e.g., "healthy", "warning", "error")
- `message` (optional): Additional status message
- `metadata` (optional): JSON object with additional data

**Response:**
```json
{
  "success": true,
  "message": "Health ping processed",
  "timestamp": "2024-01-01T12:00:00.000Z"
}
```

### Triggering Slack Alerts

Slack alerts are automatically sent when a health ping has an `error` or `warning` status. Here's an example that will trigger a Slack alert:

```bash
curl -X POST http://localhost:3000/health/ping \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{
    "boothId": "booth-001",
    "name": "Main Event Booth",
    "status": "error",
    "message": "Printer jammed (queue stale: 5.2 minutes)",
    "metadata": {
      "printer": {
        "connected": true,
        "jammed": true,
        "name": "HiTi P525 (Copy 1)",
        "queueCount": 1,
        "oldestJobAgeMinutes": 5.2
      },
      "monitor": {
        "connected": true
      },
      "mode": "Normal",
      "timezone": "America/New_York",
      "timezoneOffset": -5
    }
  }'
```

**Note:** Make sure you have configured:
- `SLACK_BOT_TOKEN` - Your Slack bot token (obtain from https://api.slack.com/apps)
- The bot must have the `chat:write` scope and be invited to the `health-alerts` channel

## Heroku Deployment

1. Create a Heroku app:
```bash
heroku create your-app-name
```

2. Add PostgreSQL addon:
```bash
heroku addons:create heroku-postgresql:mini
```

3. Set environment variables (you can do this via Heroku's web dashboard or CLI):
   - Via CLI:
   ```bash
   heroku config:set API_KEY=your-secret-api-key
   heroku config:set SLACK_BOT_TOKEN=xoxb-your-slack-bot-token
   heroku config:set STALE_THRESHOLD_MINUTES=15
   ```
   - Via Heroku Dashboard: Go to Settings → Config Vars and add:
     - `API_KEY` - Your secret API key
     - `SLACK_BOT_TOKEN` - Your Slack bot token (optional, for Slack alerts)
     - `STALE_THRESHOLD_MINUTES` - Minutes before alerting (optional, default: 15)

4. Deploy:
```bash
git push heroku main
```

**Note:** Heroku will automatically:
- Install root dependencies (`npm install`)
- Run `postinstall` script which installs server dependencies and generates Prisma client
- Run migrations during the release phase
- Start the server with `npm run start:prod`

The `DATABASE_URL` is automatically set by Heroku when you add the PostgreSQL addon.

## Database Schema

- **Photobooth**: Stores photobooth information and last ping time
- **HealthLog**: Stores individual health ping logs with status and metadata

## Monitoring

The service automatically checks for stale photobooths every 5 minutes. If a photobooth hasn't sent a health ping within the configured threshold (default 15 minutes), an alert is sent to Slack.

## Development

### Backend Scripts
- `npm run start:dev` - Start development server with hot reload
- `npm run build` - Build for production
- `npm run start:prod` - Start production server
- `npm run prisma:studio` - Open Prisma Studio to view database
- `npm run lint` - Run ESLint
- `npm run format` - Format code with Prettier

### Client Scripts
- `npm run client:dev` - Start React development server
- `npm run client:build` - Build React app for production
- `npm run client:install` - Install client dependencies

### Combined
- `npm run dev` - Run both backend and frontend together

