-- Grain check for walmart.walmart_metric_views.fact_order_items.
-- Expected: zero rows. Any row returned is a duplicate (order_id, order_item_id, store_id).
SELECT order_id, order_item_id, store_id, COUNT(*) AS n
FROM walmart.walmart_metric_views.fact_order_items
GROUP BY order_id, order_item_id, store_id
HAVING COUNT(*) > 1;
