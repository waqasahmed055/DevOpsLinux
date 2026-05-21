````
TOKEN="paste_actual_generated_token_here"

curl -k -X POST "https://yourdns/idp/addDBproperties" \
  -H "Authorization:$TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "DBHost":"your-oracle-host",
    "port":"1521",
    "SID":"",
    "ServiceName":"ORCL",
    "DBUsername":"oracleuser",
    "DBPassword":"oraclepassword"
  }'
````
