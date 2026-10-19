-- Create roles if they do not exist.
SELECT 'CREATE ROLE admin_user LOGIN'
WHERE NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = 'admin_user'
)\gexec

SELECT 'CREATE ROLE app_user LOGIN'
WHERE NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = 'app_user'
)\gexec

SELECT 'CREATE ROLE analyst_user LOGIN'
WHERE NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = 'analyst_user'
)\gexec

-- Set passwords supplied through psql variables.
ALTER ROLE admin_user PASSWORD :'admin_pass';
ALTER ROLE app_user PASSWORD :'app_pass';
ALTER ROLE analyst_user PASSWORD :'analyst_pass';

-- Application roles must not have administrative privileges.
ALTER ROLE admin_user NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER ROLE app_user NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER ROLE analyst_user NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

-- Reset permissions for these roles on current objects.
REVOKE ALL PRIVILEGES ON SCHEMA public FROM app_user, analyst_user, admin_user;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM app_user, analyst_user, admin_user;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM app_user, analyst_user, admin_user;
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public FROM app_user, analyst_user, admin_user;

-- Administrator: manage objects and data in public.
GRANT ALL PRIVILEGES ON SCHEMA public TO admin_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO admin_user;

-- Application: read and modify data, but no schema administration.
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- Analyst: read-only access.
GRANT USAGE ON SCHEMA public TO analyst_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO analyst_user;
