```
# Find PIDs and kill them
for port in {9901..9910}; do 
  pid=$(sudo netstat -tulpn | grep ":$port " | awk '{print $7}' | cut -d'/' -f1)
  if [ -n "$pid" ]; then
    sudo kill -9 $pid
    echo "Killed process $pid on port $port"
  fi
done

```
