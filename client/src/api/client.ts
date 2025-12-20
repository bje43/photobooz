import axios from 'axios';

// In production, use relative path '/api' since server serves the client
// In development, Vite proxy handles '/api' -> 'http://localhost:3000'
// VITE_API_URL can be set to override (e.g., for testing against different servers)
const API_BASE_URL = import.meta.env.VITE_API_URL || '/api';

const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Add auth token to requests
apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Handle 401 errors (unauthorized)
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

export interface HealthPing {
  boothId: string;
  name?: string;
  status: string;
  message?: string;
  metadata?: Record<string, any>;
}

export interface OperatingHours {
  enabled: boolean;
  schedule: Array<{
    day: number; // 0 = Sunday, 1 = Monday, etc.
    start: string; // "HH:mm" format
    end: string; // "HH:mm" format
  }>;
}

export interface Booth {
  id: string;
  boothId: string;
  name: string | null;
  status: string;
  mode: string;
  timezone: string | null;
  operatingHours: OperatingHours;
  lastPing: string;
  minutesSinceLastPing: number;
  isWithinOperatingHours: boolean;
  message: string | null;
}

export const authApi = {
  login: async (username: string, password: string) => {
    const response = await apiClient.post('/auth/login', { username, password });
    return response.data;
  },
};

export const boothsApi = {
  getAll: async (): Promise<Booth[]> => {
    const response = await apiClient.get('/booths');
    return response.data;
  },
  create: async (boothId: string, name?: string) => {
    const response = await apiClient.post('/booths', { boothId, name });
    return response.data;
  },
  update: async (id: string, name: string) => {
    const response = await apiClient.put(`/booths/${id}`, { name });
    return response.data;
  },
  updateOperatingHours: async (id: string, operatingHours: OperatingHours) => {
    const response = await apiClient.put(`/booths/${id}/operating-hours`, {
      operatingHours,
    });
    return response.data;
  },
};

export const healthApi = {
  ping: async (data: HealthPing) => {
    const response = await apiClient.post('/health/ping', data);
    return response.data;
  },
};

export default apiClient;

