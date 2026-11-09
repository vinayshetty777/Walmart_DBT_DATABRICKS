# Walmart Retail Lakehouse Pipeline (Databricks)

An end-to-end data pipeline built on Databricks. It ingests retail data from a PostgreSQL (Lakebase) source, transforms it with dbt, serves it through metric views, and deploys dev and prod from code with a Databricks Asset Bundle.

## Architecture

```
Lakebase Postgres (6 source tables)
  -> Lakeflow Connect ingestion pipeline        query-based, incremental on updated_timestamp
  -> bronze (raw landing tables)
  -> dbt: silver (typed, incremental), silver_b (one big table), gold (facts, SCD2 dimensions)
  -> metric views: fact_order_items + dimensions + sales_order_metrics
  -> dashboard (dev)
```

Orchestration is a Lakeflow Job: ingestion, then dbt, then metric views and dashboard. Prod currently runs ingestion and dbt.

## What I built, step by step

1. **Modeled the data in dbt.** Silver tables are typed copies of the bronze tables. `obt_b` joins them into one wide order-item table. Gold holds `fact_orders` and SCD2 dimensions built with snapshots.
2. **Found and fixed a grain bug.** The wide table joined employees on store, so each order item repeated once per store employee. Revenue came out about 10x too high (189.4M instead of 18.9M). I removed the join upstream and added a dbt test that enforces the grain on `(order_id, order_item_id, store_id)`.
3. **Built metric views.** `fact_order_items` is a deduplicated table at order-item grain. Dimensions join through current-row views (SCD2 current rows are marked `dbt_valid_to = '9999-12-31'`). `sales_order_metrics` defines revenue, units, order counts, and ratios, and I reconciled the totals to raw SQL.
4. **Set up managed ingestion.** A Lakeflow Connect PostgreSQL pipeline reads the six source tables incrementally. I replaced an expiring OAuth token with a dedicated database role and password, which fixed scheduled runs that had been failing.
5. **Wired dbt into the job.** The job's dbt task runs `dbt deps` and `dbt build` straight from this GitHub repo. A committed `profiles.yml` supplies the connection, and the token is injected at run time.
6. **Packaged everything as a Databricks Asset Bundle.** `databricks.yml` defines dev and prod targets. The job and pipeline are generated from the live resources and bound, so deploys update them instead of creating copies.
7. **Separated environments.** Dev writes to `walmart`, prod to `walmart_prod`. Each target has its own pipeline reference, Lakebase connection, dbt output, and root path. Dev-only objects (metric views, dashboard) stay out of prod until they are parameterized.
8. **Deployed and verified.** Dev and prod both deploy with `databricks bundle deploy`. A prod run completed successfully, and the prod dimensions match dev row for row.

## Repository layout

- `databricks.yml`: bundle definition, variables, and dev and prod targets
- `resources/`: job and pipeline definitions
- `profiles.yml`: dbt connection profile (no secrets; token injected at run time)
- `docs/CICD.md`: setup record and the CI/CD plan
- `models/`, `snapshots/`, `tests/`: dbt project

## Status and next steps

- Dev: fully deployed.
- Prod: ingestion and dbt run successfully. Metric views and the dashboard are not yet in prod.
- Next: parameterize the metric-view SQL by catalog, create a prod dashboard, and automate deploys with CI (validate on pull request, deploy on merge, approval gate for prod).

---

# Walmart dbt Project (Databricks)

A dbt project that models Walmart-style retail data (customers, stores, products, employees, orders, and order items) on Databricks Unity Catalog.

Raw CSV files are loaded into the `walmart.bronze` schema. dbt then builds the silver, gold, and snapshot layers on top of it.

## Project layout

| Path | Purpose |
|---|---|
| `models/source/sources.yml` | Declares the `bronze` source tables used by the silver models |
| `models/silver_t/` | Incremental "typed" tables, one per bronze table (`customers_t`, `employees_t`, `orders_t`, `order_item_t`, `products_t`, `stores_t`) |
| `models/silver_b/obt_b.sql` | One wide table (OBT) that joins the silver tables. Grain: one row per order item |
| `models/gold/ephemeral/` | Ephemeral models that are compiled into downstream models and never materialized |
| `models/gold/fact/fact_orders.sql` | Order-item fact table built from `obt_b` |
| `snapshots/` | Timestamp-strategy snapshots for dimensions (customers, employees, orders, products, stores) into `gold` |
| `models/properties.yml` | Column tests for the silver models |
| `tests/test_dbt.sql` | Singular test: `obt_b` must not contain NULL keys |
| `macros/generate_custom_schema.sql` | Overrides schema naming so `+schema` values are used as given |

## Data flow

```
bronze (walmart.bronze)            raw tables loaded from CSV
  -> silver_t (incremental)        typed, filtered on updated_timestamp
  -> silver_b.obt_b                wide table joined from silver_t
  -> gold.fact_orders              order-item fact
  -> gold snapshots                dimension history (SCD type 2)
```

## Tests

- **Generic tests** (`models/properties.yml`):
  - `not_null` and `unique` on each silver primary key. These are set to `severity: warn`.
  - `dbt_utils.expression_is_true` with `>= 0` on numeric columns: `products_t.price`, `employees_t.salary`, `orders_t.total_amount`, and `order_item_t.quantity`, `unit_price`, `line_amount`. These use `error_if: ">0"`, so any negative value fails the run.
- **Singular test** (`tests/test_dbt.sql`): checks that `obt_b` has no NULL in its key columns. Severity is `warn`.

The `dbt_utils` package is declared in `packages.yml`.

## Setup

1. Install dbt with the Databricks adapter (`dbt-databricks`).
2. Add a `walmart-dbt-project` profile to `~/.dbt/profiles.yml` with the Databricks host, HTTP path, and an access token. Keep this file outside the repo.
3. Install the packages:
   ```
   dbt deps
   ```
4. Check the connection:
   ```
   dbt debug
   ```

## Common commands

```
dbt build --select silver_t              # build silver tables and their tests
dbt build --select obt_b                 # build the OBT
dbt test                                 # run all tests
dbt snapshot                             # update dimension snapshots
dbt docs generate && dbt docs serve      # browse lineage and docs
```

## Notes

- Do not commit credentials. `.env`, `target/`, and `dbt_packages/` are listed in `.gitignore`.
- `obt_b` joins employees on `store_id`, which repeats each order item once per employee at its store. The fact table (`fact_orders`) drops `employee_id` for this reason.
