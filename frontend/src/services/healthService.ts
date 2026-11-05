import api from './api'
import type { HealthResponse } from '../types/health'

export const healthService = {
  getHealth: async (): Promise<HealthResponse> => {
    const { data } = await api.get<HealthResponse>('/health')
    return data
  },
}
