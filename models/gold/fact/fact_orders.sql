-- Order-item fact. Grain: one row per (order_id, order_item_id, store_id).
-- employee_id removed: it has no relationship to an order and fanned the fact out.
SELECT
    order_id,
    order_item_id,
    product_id,
    store_id,
    customer_id,
    total_amount,
    quantity,
    unit_price,
    line_amount
FROM
    {{ ref('obt_b') }}
