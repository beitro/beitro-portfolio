# Architecture Case Study: Multi-Tenant POS, Offline-First Sync & FEFO Inventory

This document summarizes the non-commercial system analysis and architectural decisions behind **Gastro Cashier** (`https://gastro-cashier.vercel.app/`). Production source code, credentials, and tenant data remain private.

---

## 1. Security Boundary: Signed PostgreSQL Row-Level Security (RLS)
**Challenge:** Application-layer `WHERE tenant_id = $1` filters are vulnerable to human error if a single query omits the filter.  
**Decision:** Enforce tenant and outlet isolation directly inside PostgreSQL:
- The API runs under a dedicated unprivileged role (`NOSUPERUSER`, `NOBYPASSRLS`).
- Before executing tenant-scoped queries, the API signs a transaction-scoped context payload (`tenant_id`, `outlet_id`, `txid_current()`, `jti`, `exp`) with HMAC-SHA256.
- PostgreSQL RLS policies verify the signature inside a `SECURITY DEFINER` function before returning or mutating rows.
- **Graceful Fallback (ADR-001):** Rate-limiting tables (`auth_rate_limits`) wrap context checks with safe fallbacks so authentication remains resilient even if a secondary environment context is locked.

---

## 2. Offline-First Resilience (ADR-003)
**Challenge:** Restaurant Wi-Fi frequently drops during lunch/dinner rushes, stalling order entry.  
**Decision:**
1. **Local Cache:** Store active menu, table layout, and session snapshots in browser `IndexedDB`.
2. **Sync Queue:** When `navigator.onLine` is false or a `fetch` fails due to network loss, enqueue `ORDER` / `SETTLE` actions locally with unique **idempotency keys**.
3. **Auto-Flush:** Register `online` event listeners + a 30-second fallback check to flush queued actions sequentially once connectivity returns, refreshing the live snapshot afterward.

---

## 3. Atomic FEFO Inventory Ledger
**Challenge:** Concurrent cashiers selling items that share raw ingredients can cause race conditions or negative stock.  
**Decision:**
- Lock target inventory items in deterministic order (`SELECT ... FOR UPDATE`) inside a SQL transaction (`BEGIN` / `COMMIT`).
- Consume ingredient lots using **First-Expired-First-Out (FEFO)** ordering (`expiry_date ASC NULLS LAST, received_at ASC`).
- Record immutable ledger entries (`balance_after`, `weighted_average_cost`) and lot consumption links so order cancellations can atomically restore exact stock balances.

---

## 4. Verification & Quality Gates
- **Type Safety & Build:** Strict TypeScript (`tsc --noEmit`) + Vite production bundle.
- **E2E API & Concurrency Tests:** Automated scripts verifying stock = 1 race conditions (`201` vs `409`), idempotency replay, and cancel-restock flows.
- **Load Simulation:** 100-customer concurrent simulation covering dual cashiers, KDS kitchen routing, and stock depletion.
- **Release Exposure Audit:** Static artifact verification on `dist/` ensuring zero leaked source maps or credential markers.
