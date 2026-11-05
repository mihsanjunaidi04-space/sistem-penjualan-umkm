import { AuthProvider } from './app/AuthProvider'
import { AppRouter } from './app/AppRouter'

function App() {
  return (
    <AuthProvider>
      <AppRouter />
    </AuthProvider>
  )
}

export default App
