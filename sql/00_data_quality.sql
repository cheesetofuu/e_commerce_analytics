/* =====================================================================
   DATA QUALITY GATE
   ---------------------------------------------------------------------
   Stakeholder : Business Analyst
   Scope       : Trust the numbers before reporting them: integrity checks, then the business brief reconciled with the data.
   Schema      : e_commerce (XómDataset, SQL Server). Dialect: T-SQL.
   How to read : each `-- @output <name>` marker starts one statement;
                 its result is the sheet <name> in results/00_data_quality.xlsx.
   Run         : whole file in SSMS / DBeaver / VS Code (mssql), or
                 python scripts/run_queries_local.py (SQLite, no server).
   ===================================================================== */


/* =====================================================================
   DATA QUALITY GATE 1 - STRUCTURAL INTEGRITY
   ---------------------------------------------------------------------
   Schema  : e_commerce (XómDataset, SQL Server)
   Owner   : Business Analyst
   Purpose : Verify row counts, key integrity, value ranges and table
             grain BEFORE any business number is reported. Every
             downstream query in this repo relies on these checks.
   Dialect : T-SQL. Also runs on SQLite via scripts/run_queries_local.py
             (the script maps DATEDIFF(day, ...) and TOP (n) only).
   ===================================================================== */


-- @output dq_01a_row_counts
-- Row count vs. distinct primary key per table (should be equal).
SELECT 'customer'   AS table_name, COUNT(*) AS row_count, COUNT(DISTINCT customer_id)  AS distinct_key FROM e_commerce.customer
UNION ALL
SELECT 'ecom_sales', COUNT(*), COUNT(DISTINCT row_id)       FROM e_commerce.ecom_sales
UNION ALL
SELECT 'product',    COUNT(*), COUNT(DISTINCT product_code) FROM e_commerce.product
UNION ALL
SELECT 'region',     COUNT(*), COUNT(DISTINCT region_code)  FROM e_commerce.region;


-- @output dq_01b_orphan_foreign_keys
-- Fact rows whose key has no match in the dimension table.
-- The dataset declares no physical FKs, so integrity must be tested by hand.
SELECT 'customer_id' AS fk_column,
       COUNT(*)                     AS orphan_rows,
       COUNT(DISTINCT s.customer_id) AS orphan_keys
FROM e_commerce.ecom_sales s
LEFT JOIN e_commerce.customer c ON c.customer_id = s.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'product_code',
       COUNT(*),
       COUNT(DISTINCT s.product_code)
FROM e_commerce.ecom_sales s
LEFT JOIN e_commerce.product p ON p.product_code = s.product_code
WHERE p.product_code IS NULL
UNION ALL
SELECT 'region_code',
       COUNT(*),
       COUNT(DISTINCT s.region_code)
FROM e_commerce.ecom_sales s
LEFT JOIN e_commerce.region r ON r.region_code = s.region_code
WHERE r.region_code IS NULL;


-- @output dq_01c_sales_value_ranges
-- Date window, value ranges and impossible values in the fact table.
SELECT MIN(order_date)                                   AS first_order_date,
       MAX(order_date)                                   AS last_order_date,
       COUNT(DISTINCT YEAR(order_date) * 100 + MONTH(order_date)) AS distinct_months,
       COUNT(*)                                          AS line_items,
       COUNT(DISTINCT order_id)                          AS orders,
       MIN(quantity)  AS min_qty,      MAX(quantity)  AS max_qty,
       MIN(sales)     AS min_sales,    MAX(sales)     AS max_sales,
       MIN(discount)  AS min_discount, MAX(discount)  AS max_discount,
       MIN(profit)    AS min_profit,   MAX(profit)    AS max_profit,
       SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END)                   AS loss_lines,
       SUM(CASE WHEN sales <= 0 OR quantity <= 0 THEN 1 ELSE 0 END)  AS non_positive_sales_or_qty,
       SUM(CASE WHEN discount < 0 OR discount > 1 THEN 1 ELSE 0 END) AS discount_out_of_range
FROM e_commerce.ecom_sales;


-- @output dq_01d_duplicates_and_grain
-- Is (order_id, product_code) unique? Does an order belong to exactly
-- one customer / region / date / segment? Defines the grain used later.
WITH order_grain AS (
    SELECT order_id,
           COUNT(DISTINCT customer_id) AS n_customers,
           COUNT(DISTINCT region_code) AS n_regions,
           COUNT(DISTINCT order_date)  AS n_dates,
           COUNT(DISTINCT segment)     AS n_segments
    FROM e_commerce.ecom_sales
    GROUP BY order_id
),
line_dups AS (
    SELECT order_id, product_code, COUNT(*) AS n
    FROM e_commerce.ecom_sales
    GROUP BY order_id, product_code
    HAVING COUNT(*) > 1
)
SELECT
    (SELECT COUNT(*)            FROM line_dups)                          AS duplicated_order_product_pairs,
    (SELECT SUM(n) - COUNT(*)   FROM line_dups)                          AS extra_rows_from_duplicates,
    (SELECT COUNT(*) FROM order_grain WHERE n_customers > 1)             AS orders_with_multiple_customers,
    (SELECT COUNT(*) FROM order_grain WHERE n_regions   > 1)             AS orders_with_multiple_region_codes,
    (SELECT COUNT(*) FROM order_grain WHERE n_dates     > 1)             AS orders_with_multiple_dates,
    (SELECT COUNT(*) FROM order_grain WHERE n_segments  > 1)             AS orders_with_multiple_segments;


-- @output dq_01e_code_format_and_nulls
-- Malformed codes, missing demographics, segment consistency.
SELECT
    (SELECT COUNT(*) FROM e_commerce.ecom_sales WHERE product_code NOT LIKE 'P______')   AS malformed_product_codes,
    (SELECT COUNT(*) FROM e_commerce.customer   WHERE gender IS NULL)                    AS customers_missing_gender,
    (SELECT COUNT(*) FROM (SELECT customer_id
                           FROM e_commerce.ecom_sales
                           GROUP BY customer_id
                           HAVING COUNT(DISTINCT segment) > 1) x)                        AS customers_with_multiple_segments,
    (SELECT COUNT(*) FROM e_commerce.customer c
     WHERE NOT EXISTS (SELECT 1 FROM e_commerce.ecom_sales s
                       WHERE s.customer_id = c.customer_id))                             AS customers_without_orders,
    (SELECT COUNT(*) FROM e_commerce.product p
     WHERE NOT EXISTS (SELECT 1 FROM e_commerce.ecom_sales s
                       WHERE s.product_code = p.product_code))                           AS catalog_products_never_sold;


/* =====================================================================
   DATA QUALITY GATE 2 - RECONCILE THE BUSINESS BRIEF WITH THE DATA
   ---------------------------------------------------------------------
   The dataset page describes Xóm E-Com as: ~$2.3M revenue/year, ~20%
   gross margin, 3 categories (Office / Furniture / Technology), ~1,900
   SKUs, 3 segments (Consumer 60% / Corporate 25% / Home Office 15%),
   4 markets (US / EMEA / APAC / LATAM), 140+ countries.
   Before quoting any of those numbers to a stakeholder, test them.
   ===================================================================== */


-- @output dq_02a_brief_vs_data
-- One row per claim in the brief, with what the data actually says.
-- (CAST ... AS DECIMAL keeps SQL Server from printing long decimal scales inside CONCAT.)
SELECT 'Average annual revenue' AS metric,
       '~$2.3M / year'          AS brief_says,
       CONCAT('$', CAST(ROUND(SUM(sales) / 1000000.0 / COUNT(DISTINCT YEAR(order_date)), 2) AS DECIMAL(10,2)),
              'M / year averaged over ', COUNT(DISTINCT YEAR(order_date)), ' years (',
              MIN(YEAR(order_date)), '-', MAX(YEAR(order_date)), ')') AS data_says
FROM e_commerce.ecom_sales
UNION ALL
SELECT 'Gross margin (profit / sales)',
       '~20%',
       CONCAT(CAST(ROUND(100.0 * SUM(profit) / SUM(sales), 1) AS DECIMAL(10,1)), '%')
FROM e_commerce.ecom_sales
UNION ALL
SELECT 'Customer segments',
       'Consumer 60% / Corporate 25% / Home Office 15%',
       CONCAT(COUNT(DISTINCT segment), ' segments - names and shares in dq_02b')
FROM e_commerce.ecom_sales
UNION ALL
SELECT 'Markets',
       '4 (US, EMEA, APAC, LATAM)',
       CONCAT(COUNT(DISTINCT r.market), ' markets - names in dq_02c')
FROM e_commerce.ecom_sales s
JOIN e_commerce.region r ON r.region_code = s.region_code
UNION ALL
SELECT 'Countries with at least one order',
       'more than 140',
       CONCAT(COUNT(DISTINCT r.country), ' countries')
FROM e_commerce.ecom_sales s
JOIN e_commerce.region r ON r.region_code = s.region_code
UNION ALL
SELECT 'Product catalog size',
       '~1,900 SKUs in Office Supplies / Furniture / Technology',
       CONCAT(COUNT(*), ' rows in product table - categories in dq_02d')
FROM e_commerce.product
UNION ALL
SELECT 'Distinct product codes actually sold',
       '~1,900',
       CONCAT(COUNT(DISTINCT product_code), ' product codes in ecom_sales')
FROM e_commerce.ecom_sales
UNION ALL
SELECT 'Sales lines that match a product in the catalog',
       '100% (implied)',
       CONCAT(CAST(ROUND(100.0 * SUM(CASE WHEN p.product_code IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS DECIMAL(10,1)),
              '% of lines / ',
              CAST(ROUND(100.0 * SUM(CASE WHEN p.product_code IS NOT NULL THEN s.sales ELSE 0 END) / SUM(s.sales), 1) AS DECIMAL(10,1)),
              '% of revenue')
FROM e_commerce.ecom_sales s
LEFT JOIN e_commerce.product p ON p.product_code = s.product_code;


-- @output dq_02b_segment_names_and_shares
-- Segment names and volume shares (brief says Consumer / Corporate / Home Office = 60 / 25 / 15).
SELECT segment,
       COUNT(*)                                                   AS line_items,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS share_of_lines_pct,
       COUNT(DISTINCT order_id)                                   AS orders,
       ROUND(100.0 * COUNT(DISTINCT order_id)
             / SUM(COUNT(DISTINCT order_id)) OVER (), 1)          AS share_of_orders_pct,
       ROUND(SUM(sales), 2)                                       AS revenue,
       ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (), 1)      AS share_of_revenue_pct
FROM e_commerce.ecom_sales
GROUP BY segment
ORDER BY revenue DESC;


-- @output dq_02c_market_names_and_shares
-- Market names in the region table (brief says US / EMEA / APAC / LATAM).
SELECT r.market,
       COUNT(DISTINCT r.country)                                  AS countries_with_orders,
       ROUND(SUM(s.sales), 2)                                     AS revenue,
       ROUND(100.0 * SUM(s.sales) / SUM(SUM(s.sales)) OVER (), 1)  AS share_of_revenue_pct
FROM e_commerce.ecom_sales s
JOIN e_commerce.region r ON r.region_code = s.region_code
GROUP BY r.market
ORDER BY revenue DESC;


-- @output dq_02d_product_categories_in_catalog
-- Categories present in the product table (brief says Office Supplies / Furniture / Technology).
SELECT p.category,
       COUNT(DISTINCT p.subcategory) AS subcategories,
       COUNT(*)                      AS catalog_skus,
       (SELECT COUNT(*) FROM e_commerce.ecom_sales s
        JOIN e_commerce.product p2 ON p2.product_code = s.product_code
        WHERE p2.category = p.category) AS sales_lines_matched
FROM e_commerce.product p
GROUP BY p.category
ORDER BY catalog_skus DESC;


-- @output dq_02e_order_id_vs_order_date
-- order_id embeds a year (format 'XX-YYYY-...', verified for all rows).
-- Compare it with order_date: a constant offset means the dates were
-- shifted when the dataset was built (relevant for seasonality claims).
SELECT YEAR(order_date) - CAST(SUBSTRING(order_id, 4, 4) AS INT) AS years_between_id_and_date,
       COUNT(*) AS line_items
FROM e_commerce.ecom_sales
GROUP BY YEAR(order_date) - CAST(SUBSTRING(order_id, 4, 4) AS INT)
ORDER BY line_items DESC;


-- @output dq_02f_category_label_vs_product_name
-- Do category labels describe the product? Group products by an obvious
-- keyword in the name and look at how the labels are distributed. If the
-- distribution inside each keyword group equals the catalog-wide split,
-- the label is independent of the product (i.e. assigned at random).
WITH keyworded AS (
    SELECT product_code,
           category,
           CASE WHEN product LIKE '%Earring%'  OR product LIKE '%Necklace%'
                  OR product LIKE '%Bracelet%' OR product LIKE '%Anklet%'
                  OR product LIKE '%Ring%'     OR product LIKE '%Stud%'      THEN 'jewellery'
                WHEN product LIKE '%Shampoo%'  OR product LIKE '%Conditioner%' THEN 'shampoo / conditioner'
                WHEN product LIKE '%Nail%'     OR product LIKE '%Polish%'
                  OR product LIKE '%Lacquer%'                                THEN 'nail polish'
                WHEN product LIKE '%Eyeshadow%' OR product LIKE '%Lipstick%'
                  OR product LIKE '%Lip Color%' OR product LIKE '%Foundation%'
                  OR product LIKE '%Mascara%'                                THEN 'colour cosmetics'
                WHEN product LIKE '%Vitamin%'  OR product LIKE '%Gummies%'
                  OR product LIKE '%Supplement%'                             THEN 'vitamins / supplements'
                ELSE 'other'
           END AS name_keyword_group
    FROM e_commerce.product
)
SELECT name_keyword_group,
       category,
       COUNT(*)                                                                      AS products,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY name_keyword_group), 1) AS share_within_group_pct,
       (SELECT ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM e_commerce.product), 1)
        FROM e_commerce.product p2 WHERE p2.category = k.category)                    AS share_in_whole_catalog_pct
FROM keyworded k
GROUP BY name_keyword_group, category
ORDER BY name_keyword_group, category;
