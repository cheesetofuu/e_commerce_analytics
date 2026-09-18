/* =====================================================================
   PRICING & DISCOUNT
   ---------------------------------------------------------------------
   Stakeholder : CMO
   Scope       : Q5 average discount by category, plus the discount-band analysis that answers pain point #1: does discount eat profit?
   Schema      : e_commerce (XómDataset, SQL Server). Dialect: T-SQL.
   How to read : each `-- @output <name>` marker starts one statement;
                 its result is the sheet <name> in results/02_pricing_discount.xlsx.
   Run         : whole file in SSMS / DBeaver / VS Code (mssql), or
                 python scripts/run_queries_local.py (SQLite, no server).
   ===================================================================== */


/* =====================================================================
   PRICING 01 - AVERAGE DISCOUNT BY CATEGORY               (brief Q5)
   ---------------------------------------------------------------------
   Stakeholder : CMO
   Question    : Which categories are discounted most heavily, and is the
                 discount paid back in margin?
   Caveat      : dq_02f shows the category label is independent of the
                 product name in this dataset, so differences between
                 categories are expected to be noise. Lines whose code has
                 no catalog row (2 malformed codes) are kept in an explicit
                 'Unknown' bucket so totals still reconcile to fin_01.
   ===================================================================== */


-- @output mkt_01_avg_discount_by_category
-- Q5: average discount and resulting margin per catalog category.
SELECT COALESCE(p.category, 'Unknown (code not in product table)')          AS category,
       COUNT(*)                                                             AS line_items,
       ROUND(100.0 * AVG(s.discount), 2)                                    AS avg_discount_pct,
       ROUND(100.0 * SUM(CASE WHEN s.discount > 0 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                                 AS discounted_lines_pct,
       ROUND(100.0 * AVG(CASE WHEN s.discount > 0 THEN s.discount END), 2)  AS avg_discount_when_discounted_pct,
       ROUND(SUM(s.sales), 2)                                               AS revenue,
       ROUND(SUM(s.profit), 2)                                              AS profit,
       ROUND(100.0 * SUM(s.profit) / SUM(s.sales), 2)                       AS gross_margin_pct
FROM e_commerce.ecom_sales s
LEFT JOIN e_commerce.product p ON p.product_code = s.product_code
GROUP BY COALESCE(p.category, 'Unknown (code not in product table)')
ORDER BY avg_discount_pct DESC;


-- @output mkt_01b_avg_discount_by_subcategory
-- Matched lines only (INNER JOIN): subcategories ranked by discount depth.
SELECT p.category,
       p.subcategory,
       COUNT(*)                                            AS line_items,
       ROUND(100.0 * AVG(s.discount), 2)                   AS avg_discount_pct,
       ROUND(SUM(s.sales), 2)                              AS revenue,
       ROUND(100.0 * SUM(s.profit) / SUM(s.sales), 2)      AS gross_margin_pct
FROM e_commerce.ecom_sales s
JOIN e_commerce.product p ON p.product_code = s.product_code
GROUP BY p.category, p.subcategory
ORDER BY avg_discount_pct DESC;


/* =====================================================================
   PRICING 02 - DOES DISCOUNT EAT PROFIT?          (pain point #1, extra)
   ---------------------------------------------------------------------
   Stakeholder : CMO + Head of Finance
   Pain point  : "Marketing runs 20-80% discounts to drive volume but
                 nobody measures whether the discount eats into profit."
   Method      : bucket every order line by discount depth and compare
                 volume share vs. profit share, margin and loss rate.
                 Category is NOT needed, so this uses the fact table only
                 and is unaffected by the product-catalog coverage issue.
   ===================================================================== */


-- @output mkt_02_discount_band_profitability
-- Volume share vs. profit share per discount band: where the discount stops paying back.
WITH banded AS (
    SELECT s.*,
           CASE WHEN discount = 0    THEN '0. No discount'
                WHEN discount <= 0.20 THEN '1. 1-20%'
                WHEN discount <= 0.40 THEN '2. 21-40%'
                WHEN discount <= 0.60 THEN '3. 41-60%'
                ELSE                       '4. 61-85%'
           END AS discount_band
    FROM e_commerce.ecom_sales s
)
SELECT discount_band,
       COUNT(*)                                                       AS line_items,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)              AS share_of_lines_pct,
       SUM(quantity)                                                  AS units,
       ROUND(SUM(sales), 2)                                           AS revenue,
       ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (), 2)          AS share_of_revenue_pct,
       ROUND(SUM(profit), 2)                                          AS profit,
       ROUND(100.0 * SUM(profit) / SUM(SUM(profit)) OVER (), 2)        AS share_of_profit_pct,
       ROUND(100.0 * SUM(profit) / SUM(sales), 2)                     AS gross_margin_pct,
       ROUND(100.0 * SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                           AS loss_line_rate_pct,
       ROUND(AVG(profit), 2)                                          AS avg_profit_per_line
FROM banded
GROUP BY discount_band
ORDER BY discount_band;


-- @output mkt_02b_margin_by_exact_discount_level
-- Every distinct discount level used: where exactly does margin turn negative?
SELECT ROUND(100.0 * discount, 0)                                     AS discount_pct,
       COUNT(*)                                                       AS line_items,
       ROUND(SUM(sales), 2)                                           AS revenue,
       ROUND(SUM(profit), 2)                                          AS profit,
       ROUND(100.0 * SUM(profit) / SUM(sales), 2)                     AS gross_margin_pct,
       ROUND(100.0 * SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                           AS loss_line_rate_pct
FROM e_commerce.ecom_sales
GROUP BY discount
ORDER BY discount;


-- @output mkt_02c_discount_band_by_segment
-- Which segment receives the deep discounts, and what does it cost?
WITH banded AS (
    SELECT s.*,
           CASE WHEN discount = 0    THEN '0. No discount'
                WHEN discount <= 0.20 THEN '1. 1-20%'
                WHEN discount <= 0.40 THEN '2. 21-40%'
                WHEN discount <= 0.60 THEN '3. 41-60%'
                ELSE                       '4. 61-85%'
           END AS discount_band
    FROM e_commerce.ecom_sales s
)
SELECT segment,
       discount_band,
       COUNT(*)                                                       AS line_items,
       ROUND(100.0 * COUNT(*)
             / SUM(COUNT(*)) OVER (PARTITION BY segment), 2)          AS share_of_segment_lines_pct,
       ROUND(SUM(sales), 2)                                           AS revenue,
       ROUND(SUM(profit), 2)                                          AS profit,
       ROUND(100.0 * SUM(profit) / SUM(sales), 2)                     AS gross_margin_pct
FROM banded
GROUP BY segment, discount_band
ORDER BY segment, discount_band;


-- @output mkt_02d_discount_mix_vs_base_margin_by_year
-- Is the 2023 profit drop caused by deeper discounting (mix) or by lower
-- margin at the same discount level (unit economics / cost)? Compare the
-- discount mix per year with margin on undiscounted vs. discounted lines.
SELECT YEAR(order_date)                                                  AS order_year,
       COUNT(*)                                                          AS line_items,
       ROUND(100.0 * AVG(discount), 2)                                   AS avg_line_discount_pct,
       ROUND(100.0 * SUM(CASE WHEN discount > 0 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                              AS discounted_lines_pct,
       ROUND(100.0 * SUM(CASE WHEN discount > 0.20 THEN sales ELSE 0 END)
             / SUM(sales), 2)                                            AS revenue_share_discount_over_20_pct,
       ROUND(100.0 * SUM(CASE WHEN discount = 0 THEN profit ELSE 0 END)
             / SUM(CASE WHEN discount = 0 THEN sales ELSE 0 END), 2)     AS margin_on_undiscounted_lines_pct,
       ROUND(100.0 * SUM(CASE WHEN discount > 0 THEN profit ELSE 0 END)
             / SUM(CASE WHEN discount > 0 THEN sales ELSE 0 END), 2)     AS margin_on_discounted_lines_pct,
       ROUND(100.0 * SUM(profit) / SUM(sales), 2)                        AS total_gross_margin_pct
FROM e_commerce.ecom_sales
GROUP BY YEAR(order_date)
ORDER BY order_year;
