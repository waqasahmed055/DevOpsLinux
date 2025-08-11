#!/usr/bin/env bash
# restart_services.sh - stop all services, wait 30s, start them one-by-one, show dwadmin processes

services=(APIServices Composer Controller RespDashboard TransferEquiv TransferEquivAdmin TransitUI)

# stop all
for svc in "${services[@]}"; do
  echo "----> Stopping ${svc} ..."
  if [ -x "./${svc}/stop_${svc}.sh" ]; then
    "./${svc}/stop_${svc}.sh" || echo "Warning: stop_${svc}.sh returned non-zero"
  else
    echo "Warning: ./$(printf '%s' "$svc")/stop_${svc}.sh not found or not executable"
  fi
done

echo "Sleeping 30 seconds..."
sleep 30

# start sequentially
for svc in "${services[@]}"; do
  echo "----> Starting ${svc} ..."
  if [ -x "./${svc}/start_${svc}.sh" ]; then
    "./${svc}/start_${svc}.sh" || echo "Warning: start_${svc}.sh returned non-zero"
  else
    echo "Warning: ./$(printf '%s' "$svc")/start_${svc}.sh not found or not executable"
  fi
done

echo
echo "Processes for dwadmin:"
ps -ef | grep dwadmin | grep -v grep || true
