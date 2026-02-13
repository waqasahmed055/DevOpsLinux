FLUSH PRIVILEGES;

UPDATE mysql.user
SET authentication_string = PASSWORD('NewStrongP@ssw0rd')
WHERE User = 'root' AND Host = 'localhost';

FLUSH PRIVILEGES;
EXIT;

