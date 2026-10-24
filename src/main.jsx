import React from 'react'
import { createRoot } from 'react-dom/client'
import App from './web/WebApp'
import './web/styles.css'

createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
