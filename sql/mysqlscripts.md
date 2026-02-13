UPDATE mysql.user 
SET Password = PASSWORD('NewStrongP@ssw0rd')
WHERE User = 'root' AND Host = 'localhost';

FLUSH PRIVILEGES;
