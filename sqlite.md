# SQLite3 Useful Commands

This document contains commonly used **SQLite3 commands** for inspecting and troubleshooting SQLite databases inside Linux, Docker containers, or servers.

---

# 1. Find SQLite Database Files

To search the entire system for SQLite database files:

```bash
find / -name "*.db" 2>/dev/null
```

To also search for other common SQLite extensions:

```bash
find / -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) 2>/dev/null
```

---

# 2. Open a SQLite Database

```bash
sqlite3 database.db
```

Example:

```bash
sqlite3 app.db
```

---

# 3. Show Connected Databases

Inside the SQLite terminal:

```sql
.databases
```

Example output:

```
0 main /data/app.db
```

---

# 4. List All Tables

```sql
.tables
```

---

# 5. Show Table Schema

```sql
.schema table_name
```

Example:

```sql
.schema users
```

---

# 6. Show All Database Schema

```sql
.schema
```

---

# 7. Show Table Columns

```sql
PRAGMA table_info(table_name);
```

Example:

```sql
PRAGMA table_info(users);
```

---

# 8. Select Data From a Table

```sql
SELECT * FROM table_name;
```

Example:

```sql
SELECT * FROM users;
```

Limit results:

```sql
SELECT * FROM users LIMIT 10;
```

---

# 9. Better Output Formatting

Enable headers and column formatting:

```sql
.headers on
.mode column
```

---

# 10. Check Database Integrity

Verify database health:

```sql
PRAGMA integrity_check;
```

Expected output:

```
ok
```

Quick check (faster):

```sql
PRAGMA quick_check;
```

---

# 11. Show SQLite Version

```sql
SELECT sqlite_version();
```

---

# 12. Show Database File Info

```sql
.dbinfo
```

---

# 13. Exit SQLite

```sql
.exit
```

or

```sql
.quit
```

---

# 14. Check Database File Size

Outside SQLite:

```bash
ls -lh database.db
```

---

# 15. Check Last Modification Time

```bash
stat database.db
```

---

# 16. Check Write-Ahead Log (WAL) Files

SQLite may create additional files during write operations:

```
database.db
database.db-wal
database.db-shm
```

Check using:

```bash
ls -lh
```

---

# 17. Run Integrity Check From Shell

Without entering SQLite:

```bash
sqlite3 database.db "PRAGMA integrity_check;"
```

---

# Notes

* SQLite does **not maintain internal logs like MySQL or PostgreSQL**.
* Errors typically appear in **application logs or container logs**.
* SQLite automatically creates a new database file if the specified file does not exist.

---

# Example Debug Workflow

```bash
find / -name "*.db" 2>/dev/null
sqlite3 database.db
.databases
.tables
PRAGMA integrity_check;
```
