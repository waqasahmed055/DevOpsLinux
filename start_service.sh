#!/bin/bash

# DegreeWorks Services Startup Script
BASE_DIR="/degreeworks"

# Service names from your directory
SERVICES=(
    "APIServices"
    "Composer"
    "Controller"
    "RespDashboard"
    "TransferEquiv"
    "TransferEquivAdmin"
    "TransitUI"
)

echo "Starting DegreeWorks Services..."

for service in "${SERVICES[@]}"; do
    echo "Starting $service..."
    bash "$BASE_DIR/$service/start_${service}.sh"
    sleep 1
done

echo "All services started!"
