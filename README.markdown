# QID 38140 and QID 38143

This document provides detailed information on two vulnerabilities identified by Qualys: QID 38140 (SSL Server Supports Weak Encryption Vulnerability) and QID 38143 (SSL Server Allows Cleartext Communication Vulnerability). These vulnerabilities relate to insecure SSL/TLS configurations that can compromise the security of web communications. Below, we outline their descriptions, impacts, solutions, validation methods, and best practices for mitigation, drawing from recent security resources and documentation.

## What are QIDs?

QIDs (Qualys IDs) are unique identifiers assigned by Qualys, a leading vulnerability management platform, to specific security issues or vulnerabilities. They help organizations track and address risks in their systems, particularly in network and web server configurations.

## QID 38140: SSL Server Supports Weak Encryption Vulnerability

### Description
The SSL Server Supports Weak Encryption Vulnerability (QID 38140) occurs when a server supports SSL ciphers with weak encryption, typically those with key lengths less than 128 bits (e.g., 40-bit or 56-bit ciphers like RC4 or DES). These ciphers are considered insecure because they can be decrypted relatively easily by attackers using modern computing power.

### Impact
Weak ciphers compromise the confidentiality of data transmitted between the client and server. Attackers who intercept the communication can decrypt sensitive information, such as login credentials or personal data, leading to potential data breaches or unauthorized access.

### Solution
To mitigate this vulnerability, disable support for weak encryption ciphers and configure the server to use only strong ciphers (128 bits or higher). Below are example configurations for popular servers:

- **Apache**: Update the `httpd.conf` or `ssl.conf` file with the following directive to exclude weak ciphers:
  ```
  SSLCipherSuite ALL:!aNULL:!ADH:!eNULL:!LOW:!EXP:RC4+RSA:+HIGH:+MEDIUM
  ```
  If TLSv1.1 or TLSv1.2 is available, prefer these protocols:
  ```
  SSLProtocol TLSv1.1 TLSv1.2
  ```

- **Tomcat**: Configure the `server.xml` file to specify secure ciphers:
  ```
  sslProtocol="TLSv1.2" ciphers="TLS_RSA_WITH_AES_128_CBC_SHA,TLS_RSA_WITH_AES_256_CBC_SHA"
  ```

- **IIS**: Restrict weak ciphers through registry settings or use tools like IIS Crypto to configure secure cipher suites ([Microsoft Support](https://support.microsoft.com/en-us/kb/245030)).

For other servers, consult their documentation to disable ciphers classified as LOW (e.g., TLS_RSA_WITH_DES_CBC_SHA, TLS_DHE_RSA_EXPORT_WITH_DES40_CBC_SHA).

### Validation
To verify that weak ciphers are disabled, use the `sslyze` tool ([sslyze GitHub](https://github.com/nabla-c0d3/sslyze)). Run the following commands to check for weak ciphers:

- For HTTP (ports 443, 8443):
  ```
  sslyze --regular --hide_rejected_ciphers <Server IP>:<PORT> | grep bits | egrep -v '(128|256)'
  ```

- For SMTP (ports 25, 587):
  ```
  sslyze --regular --starttls=smtp --hide_rejected_ciphers <Server IP>:<PORT> | grep bits | egrep -v '(128|256)'
  ```

If the output lists ciphers with 112, 56, or 40 bits (e.g., TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA), the server is still vulnerable.

## QID 38143: SSL Server Allows Cleartext Communication Vulnerability

### Description
The SSL Server Allows Cleartext Communication Vulnerability (QID 38143) occurs when a server supports SSL ciphers that allow communication without encryption, known as null ciphers (e.g., ciphers containing "WITH_NULL" in their names). This means data is transmitted in cleartext, readable by anyone who can intercept the traffic.

### Impact
Since data is sent unencrypted, attackers who can sniff network traffic (e.g., on public Wi-Fi or compromised networks) can read sensitive information, such as passwords or credit card details, undermining the security of the SSL/TLS connection.

### Solution
Disable null ciphers to ensure all communications are encrypted. Below are example configurations:

- **Apache**: Update the `httpd.conf` or `ssl.conf` file to exclude null ciphers:
  ```
  SSLCipherSuite ALL:!aNULL:!eNULL:!NULL:!LOW:!EXP:RC4+RSA:+HIGH:+MEDIUM
  SSLProtocol -ALL +TLSv1.2
  ```

- **Axway Products**: In the administration interface, navigate to `[License Owner] > Administration > Access Points > HTTPS` and uncheck ciphers containing "WITH_NULL" ([Axway Support](https://support.axway.com/kb/176958/language/en)).

- **Other Servers**: Check the server’s documentation to disable null ciphers. For example, in Nginx, use:
  ```
  ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
  ssl_protocols TLSv1.2 TLSv1.3;
  ```

Note that some servers may allow cipher negotiation but abort communication if null ciphers are selected, which may not be exploitable but should still be addressed for compliance.

### Validation
To verify that null ciphers are disabled, use the `openssl` command:
```
openssl s_client -connect <Server IP>:<PORT> -cipher NULL
```
If the connection succeeds, the server supports null ciphers and is vulnerable. A failed connection indicates the vulnerability is resolved.

## Best Practices for SSL/TLS Security
To prevent vulnerabilities like QID 38140 and QID 38143 and maintain a secure SSL/TLS configuration, follow these best practices:

- **Use Modern Protocols**: Support only TLS 1.2 and TLS 1.3, as older protocols like SSLv2, SSLv3, and TLS 1.0/1.1 are deprecated and vulnerable ([OWASP TLS Guide](https://owasp.org/www-project-web-security-testing-guide/v41/4-Web_Application_Security_Testing/09-Testing_for_Weak_Cryptography/01-Testing_for_Weak_SSL_TLS_Ciphers_Insufficient_Transport_Layer_Protection)).
- **Regular Testing**: Use tools like [Qualys SSL Labs](https://www.ssllabs.com/ssltest/) to assess your server’s SSL/TLS configuration and achieve an A+ rating.
- **Stay Updated**: Monitor security advisories and update SSL/TLS libraries to patch known vulnerabilities ([SSL.com Best Practices](https://www.ssl.com/guide/ssl-best-practices/)).
- **Choose a Trusted CA**: Select a reputable Certificate Authority to ensure certificate trustworthiness ([SSL Dragon](https://www.ssldragon.com/blog/ssl-best-practices/)).
- **Implement Forward Secrecy**: Use ciphers that support Perfect Forward Secrecy (PFS) to protect past sessions if a private key is compromised ([SSLLabs Best Practices](https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices)).

## References

- https://success.qualys.com/support/s/article/000006111
- https://success.qualys.com/discussions/s/article/000006118
