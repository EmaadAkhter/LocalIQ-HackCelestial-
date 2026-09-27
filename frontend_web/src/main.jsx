import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { MotionConfig } from 'motion/react';
import { LocalIQProvider } from './context/LocalIQContext';
import './index.css';
import App from './App.jsx';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <MotionConfig reducedMotion="user">
        <LocalIQProvider>
          <App />
        </LocalIQProvider>
      </MotionConfig>
    </BrowserRouter>
  </StrictMode>,
);
