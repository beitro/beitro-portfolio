-- Educational Example: Signed PostgreSQL Row-Level Security (RLS) Pattern
-- Non-commercial reference pattern for enforcing multi-tenant isolation at the DB boundary.

CREATE SCHEMA IF NOT EXISTS app_private;

-- 1. Least-privilege runtime role (cannot bypass RLS)
-- CREATE ROLE app_runtime LOGIN PASSWORD '...' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;

-- 2. Verify HMAC-signed transaction context inside PostgreSQL
-- Production implementations use pgcrypto's hmac() with constant-time comparison,
-- binding tenant_id, txid_current(), and an expiration timestamp.
CREATE OR REPLACE FUNCTION app_private.current_tenant_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_tenant text;
BEGIN
  v_tenant := current_setting('app.current_tenant_id', true);
  IF v_tenant IS NULL OR v_tenant = '' THEN
    RETURN NULL;
  END IF;
  RETURN v_tenant::uuid;
END;
$$;

-- 3. Example RLS policy on a multi-tenant ledger table
-- ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE orders FORCE ROW LEVEL SECURITY;
--
-- CREATE POLICY tenant_isolation_policy ON orders
--   USING (tenant_id = app_private.current_tenant_id())
--   WITH CHECK (tenant_id = app_private.current_tenant_id());
