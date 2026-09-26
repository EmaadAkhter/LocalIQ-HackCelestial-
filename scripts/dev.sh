#!/bin/bash
# Development script to run frontend and backend together

echo "Starting LocalIQ development servers..."

# Start backend in background
cd backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000 &
BACKEND_PID=$!

# Start frontend
cd ../frontend
npm run dev &
FRONTEND_PID=$!

# Wait for both processes
wait $BACKEND_PID $FRONTEND_PID