```
echo | openssl s_client -connect itsreadyltest.uncw.edu:443 -showcerts 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > selfsigned.crt
openssl x509 -in selfsigned.crt -text -noout
openssl s_client -connect itsreadyltest.uncw.edu:443 -CAfile selfsigned.crt -servername itsreadyltest.uncw.edu
