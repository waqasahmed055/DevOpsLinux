#!/usr/bin/env bash
# restart_services.sh - stop all services at once, wait 30s, then start them one-by-one
# Run from any location; this script will cd into /degreeworks.

set -u

BASE_DIR="/degreeworks"
services=(APIServices Composer Controller RespDashboard TransferEquiv TransferEquivAdmin TransitUI)

cd "$BASE_DIR" || { echo "ERROR: cannot cd to $BASE_DIR"; exit 1; }

echo "Stopping all services (stop scripts dispatched in parallel)..."
pids=()
for svc in "${services[@]}"; do
  stop_sh="./${svc}/stop_${svc}.sh"
  if [ -x "$stop_sh" ]; then
    echo "  -> Dispatching $stop_sh"
    "$stop_sh" &                      # run in background so all stop at "first moment"
    pids+=($!)
  else
    echo "  WARNING: $stop_sh not found or not executable"
  fi
done

# wait for all background stop scripts to finish
if [ "${#pids[@]}" -gt 0 ]; then
  echo "Waiting for stop scripts to finish..."
  for pid in "${pids[@]}"; do
    wait "$pid" || echo "  Warning: stop script (pid $pid) exited non-zero"
  done
fi

echo "All stop scripts finished. Sleeping 30 seconds..."
sleep 30

echo "Starting services one-by-one..."
for svc in "${services[@]}"; do
  start_sh="./${svc}/start_${svc}.sh"
  if [ -x "$start_sh" ]; then
    echo "  -> Starting $svc via $start_sh"
    "$start_sh" || echo "  Warning: $start_sh returned non-zero"
  else
    echo "  WARNING: $start_sh not found or not executable"
  fi
done

echo
echo "Processes for dwadmin:"
ps -ef | grep dwadmin | grep -v grep || true
