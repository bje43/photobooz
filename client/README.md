# Photobooz Client

React client for the Photobooz photobooth monitoring service.

## Setup

1. Install dependencies:
```bash
npm install
```

2. Start the development server:
```bash
npm run dev
```

The client will run on `http://localhost:5173` and proxy API requests to `http://localhost:3000`.

## Building for Production

```bash
npm run build
```

The built files will be in the `dist/` directory.

## API Integration

The Vite dev server is configured to proxy `/api/*` requests to the backend at `http://localhost:3000`. 

Example API call:
```typescript
import axios from 'axios';

const response = await axios.post('/api/health/ping', {
  boothId: 'booth-001',
  status: 'healthy'
}, {
  headers: {
    'x-api-key': 'your-api-key'
  }
});
```

