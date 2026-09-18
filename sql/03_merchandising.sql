/* =====================================================================
   MERCHANDISING
   ---------------------------------------------------------------------
   Stakeholder : Head of Merchandising
   Scope       : Q3 top-10 products, Q12 top-3 profit products per category, Q15 products bought together.
   Schema      : e_commerce (XómDataset, SQL Server). Dialect: T-SQL.
   How to read : each `-- @output <name>` marker starts one statement;
                 its result is the sheet <name> in results/03_merchandising.xlsx.
   Run         : whole file in SSMS / DBeaver / VS Code (mssql), or
                 python scripts/run_queries_local.py (SQLite, no server).
   ===================================================================== */


/* =====================================================================
   MERCHANDISING 01 - TOP 10 BEST-SELLING PRODUCTS         (brief Q3)
   ---------------------------------------------------------------------
   Stakeholder : Head of Merchandising
   Question    : Which products sell the most units? (plus: do the
                 volume leaders actually make money?)
   Method      : aggregate on product_code from the fact table, then
                 LEFT JOIN the catalog only to attach names, so the ranking
                 never depends on catalog coverage (2 malformed codes get a
                 placeholder name). Category is shown for reference only -
                 see dq_02f on how little the label says about the product.
   ===================================================================== */


-- @output mer_01_top10_products_by_units
-- Q3: ten best-selling products by units, with the margin they actually earn.
SELECT TOP (10)
       s.product_code,
       COALESCE(p.product,  '(name not in product table)') AS product_name,
       COALESCE(p.category, 'Unknown')                     AS category,
       SUM(s.quantity)                                     AS units_sold,
       COUNT(DISTINCT s.order_id)                          AS orders,
       ROUND(SUM(s.sales), 2)                              AS revenue,
       ROUND(SUM(s.profit), 2)                             AS profit,
       ROUND(100.0 * SUM(s.profit) / SUM(s.sales), 2)      AS gross_margin_pct,
       ROUND(100.0 * AVG(s.discount), 2)                   AS avg_discount_pct
FROM e_commerce.ecom_sales s
LEFT JOIN e_commerce.product p ON p.product_code = s.product_code
GROUP BY s.product_code, p.product, p.category
ORDER BY units_sold DESC, revenue DESC;


-- @output mer_01b_top10_products_by_revenue
-- Same view ranked by revenue: volume leaders and value leaders differ.
SELECT TOP (10)
       s.product_code,
       COALESCE(p.product,  '(name not in product table)') AS product_name,
       COALESCE(p.category, 'Unknown')                     AS category,
       ROUND(SUM(s.sales), 2)                              AS revenue,
       ROUND(SUM(s.profit), 2)                             AS profit,
       ROUND(100.0 * SUM(s.profit) / SUM(s.sales), 2)      AS gross_margin_pct,
       SUM(s.quantity)                                     AS units_sold,
       COUNT(DISTINCT s.order_id)                          AS orders,
       ROUND(100.0 * AVG(s.discount), 2)                   AS avg_discount_pct
FROM e_commerce.ecom_sales s
LEFT JOIN e_commerce.product p ON p.product_code = s.product_code
GROUP BY s.product_code, p.product, p.category
ORDER BY revenue DESC;


/* =====================================================================
   MERCHANDISING 02 - TOP 3 MOST PROFITABLE PRODUCTS PER CATEGORY (Q12)
   ---------------------------------------------------------------------
   Stakeholder : Head of Merchandising
   Question    : Within each category, which three products generate the
                 most profit? (and which three destroy the most?)
   Method      : ROW_NUMBER() OVER (PARTITION BY category ORDER BY profit)
   Caveat      : INNER JOIN on the catalog (100% of lines match apart from
                 2 malformed codes). dq_02f shows the category label is not
                 related to the product name, so "top per category" is a
                 SQL exercise here rather than a merchandising insight -
                 the product-level numbers themselves are sound.
   ===================================================================== */


-- @output mer_02_top3_profit_products_per_category
-- Q12: three most profitable products inside each category (ROW_NUMBER per partition).
WITH product_pnl AS (
    SELECT p.category,
           s.product_code,
           p.product        AS product_name,
           SUM(s.profit)    AS profit,
           SUM(s.sales)     AS revenue,
           SUM(s.quantity)  AS units_sold,
           COUNT(DISTINCT s.order_id) AS orders
    FROM e_commerce.ecom_sales s
    JOIN e_commerce.product p ON p.product_code = s.product_code
    GROUP BY p.category, s.product_code, p.product
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY profit DESC, revenue DESC) AS rank_in_category
    FROM product_pnl
)
SELECT category,
       rank_in_category,
       product_code,
       product_name,
       ROUND(profit, 2)                          AS profit,
       ROUND(revenue, 2)                         AS revenue,
       ROUND(100.0 * profit / revenue, 2)        AS gross_margin_pct,
       units_sold,
       orders
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;


-- @output mer_02b_bottom3_loss_products_per_category
-- Mirror image: the three biggest loss-makers per category.
WITH product_pnl AS (
    SELECT p.category,
           s.product_code,
           p.product        AS product_name,
           SUM(s.profit)    AS profit,
           SUM(s.sales)     AS revenue,
           SUM(s.quantity)  AS units_sold,
           ROUND(100.0 * AVG(s.discount), 2) AS avg_discount_pct
    FROM e_commerce.ecom_sales s
    JOIN e_commerce.product p ON p.product_code = s.product_code
    GROUP BY p.category, s.product_code, p.product
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY profit ASC, revenue DESC) AS rank_in_category
    FROM product_pnl
)
SELECT category,
       rank_in_category,
       product_code,
       product_name,
       ROUND(profit, 2)                          AS profit,
       ROUND(revenue, 2)                         AS revenue,
       ROUND(100.0 * profit / revenue, 2)        AS gross_margin_pct,
       units_sold,
       avg_discount_pct
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;


/* =====================================================================
   MERCHANDISING 03 - PRODUCTS FREQUENTLY BOUGHT TOGETHER   (brief Q15)
   ---------------------------------------------------------------------
   Stakeholder : Head of Merchandising (bundles / cross-sell)
   Method      : market-basket via self-join on order_id
                 (a.product_code < b.product_code avoids double counting)
                 support    = orders containing both / all orders
                 confidence = orders containing both / orders containing A
                 lift       = support / (support(A) * support(B))
   Read first  : mer_03b (basket size) - if most orders contain a single
                 product, pair statistics are thin by construction.
   ===================================================================== */


-- @output mer_03_products_bought_together
-- Q15: product pairs most often in the same order, with support / confidence / lift.
WITH order_products AS (
    SELECT DISTINCT order_id, product_code
    FROM e_commerce.ecom_sales
),
product_orders AS (
    SELECT product_code, COUNT(*) AS n_orders
    FROM order_products
    GROUP BY product_code
),
pairs AS (
    SELECT a.product_code AS product_a,
           b.product_code AS product_b,
           COUNT(*)       AS orders_together
    FROM order_products a
    JOIN order_products b
      ON a.order_id = b.order_id
     AND a.product_code < b.product_code
    GROUP BY a.product_code, b.product_code
),
total AS (
    SELECT COUNT(DISTINCT order_id) AS n_orders FROM order_products
)
SELECT TOP (20)
       pr.product_a,
       COALESCE(pa.product, '(name not in product table)')          AS product_a_name,
       pr.product_b,
       COALESCE(pb.product, '(name not in product table)')          AS product_b_name,
       pr.orders_together,
       oa.n_orders                                                  AS orders_with_a,
       ob.n_orders                                                  AS orders_with_b,
       ROUND(100.0 * pr.orders_together / t.n_orders, 3)            AS support_pct,
       ROUND(100.0 * pr.orders_together / oa.n_orders, 1)           AS confidence_a_to_b_pct,
       ROUND(100.0 * pr.orders_together / ob.n_orders, 1)           AS confidence_b_to_a_pct,
       ROUND((1.0 * pr.orders_together * t.n_orders)
             / (1.0 * oa.n_orders * ob.n_orders), 1)                AS lift
FROM pairs pr
JOIN product_orders oa ON oa.product_code = pr.product_a
JOIN product_orders ob ON ob.product_code = pr.product_b
CROSS JOIN total t
LEFT JOIN e_commerce.product pa ON pa.product_code = pr.product_a
LEFT JOIN e_commerce.product pb ON pb.product_code = pr.product_b
ORDER BY pr.orders_together DESC, lift DESC, pr.product_a, pr.product_b;


-- @output mer_03b_basket_size_distribution
-- How many distinct products does an order contain?
WITH basket AS (
    SELECT order_id,
           COUNT(DISTINCT product_code) AS distinct_products,
           SUM(sales)                   AS order_value
    FROM e_commerce.ecom_sales
    GROUP BY order_id
)
SELECT CASE WHEN distinct_products >= 5 THEN '5+' 
            ELSE CONCAT(distinct_products, '') END               AS products_in_order,
       COUNT(*)                                                 AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)        AS share_of_orders_pct,
       ROUND(SUM(order_value), 2)                               AS revenue,
       ROUND(100.0 * SUM(order_value) / SUM(SUM(order_value)) OVER (), 2) AS share_of_revenue_pct,
       ROUND(AVG(order_value), 2)                               AS avg_order_value
FROM basket
GROUP BY CASE WHEN distinct_products >= 5 THEN '5+' 
              ELSE CONCAT(distinct_products, '') END
ORDER BY products_in_order;
