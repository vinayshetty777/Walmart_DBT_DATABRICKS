# Walmart metric views

Unity Catalog metric views over the `walmart.gold` layer, deployed as a Databricks Asset Bundle.

## Layout

```
databricks.yml                         bundle + deploy job (base views -> metric views)
src/base_views/base_views.sql          order-item fact + current-row (SCD2) dimension views
src/metric_views/sales_order_metrics.sql   metric view definition (YAML)
```

## Grain

- One row per **order item** (`order_item_id`). Each item belongs to exactly one order and one product, customer and store.
- An order (`order_id`) can contain several items.
- `walmart.gold.fact_orders` repeats each item once per employee of its store. The base view `v_fact_order_items` removes that fan-out. Sum revenue only from the base view, never from `fact_orders` directly.

## SCD2 convention

Current rows in the gold dimensions have `dbt_valid_to = '9999-12-31'`, not NULL. All joins use the `*_current` views.

## Deploy

```bash
databricks bundle validate --profile Vinay_chayapathi
databricks bundle deploy --profile Vinay_chayapathi
databricks bundle run deploy_walmart_metric_views --profile Vinay_chayapathi
```

To use a different warehouse: `--var warehouse_id=<id>`.

## Changing a definition

Edit the SQL under `src/`, commit, and run the job again. `CREATE OR REPLACE` makes the job idempotent.
