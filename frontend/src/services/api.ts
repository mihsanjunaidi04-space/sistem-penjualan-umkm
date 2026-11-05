import axios from 'axios'

const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000',
  timeout: 8000,
  headers: {
    'Content-Type': 'application/json',
  },
})

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('umkm_token')

  if (token) {
    config.headers = config.headers ?? {}
    config.headers.Authorization = `Bearer ${token}`
  }

  return config
})

api.interceptors.response.use(
  (response) => response.data,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('umkm_token')
      localStorage.removeItem('umkm_user')
      window.dispatchEvent(new Event('auth:unauthorized'))
    }

    const payload = error.response?.data
    const message =
      payload?.error?.message ??
      payload?.message ??
      'Terjadi kesalahan saat memproses permintaan.'

    return Promise.reject(new Error(message))
  },
)

export default api
