@echo off
cd /d "C:\OneDrive\OneDrivePersonal\OneDrive\Claude\dba\audit"
sqlplus -s / as sysdba @run_security_audit.sql
