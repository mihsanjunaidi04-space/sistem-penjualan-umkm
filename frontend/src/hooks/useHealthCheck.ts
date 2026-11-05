import { useEffect, useState } from 'react'
import { healthService } from '../services/healthService'
import type { HealthResponse } from '../types/health'

export const useHealthCheck = () => {
  const [data, setData] = useState<HealthResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchHealth = async () => {
    setLoading(true)
    setError(null)

    try {
      const response = await healthService.getHealth()
      setData(response)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Gagal memeriksa health backend.'
      setError(message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void fetchHealth()
  }, [])

  return {
    data,
    loading,
    error,
    status: data?.data?.status ?? 'checking',
    refresh: fetchHealth,
  }
}
