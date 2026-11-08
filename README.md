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
