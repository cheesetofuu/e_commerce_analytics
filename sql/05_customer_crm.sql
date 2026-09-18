/* =====================================================================
   CUSTOMER / CRM
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth / CRM
   Scope       : Q4 customers by gender x occupation, Q8 VIP churn risk, Q9 cross-sell Consumer vs Corporate, Q14 RFM. Pain point #4: customer LTV gap.
   Schema      : e_commerce (XómDataset, SQL Server). Dialect: T-SQL.
   How to read : each `-- @output <name>` marker starts one statement;
                 its result is the sheet <name> in results/05_customer_crm.xlsx.
   Run         : whole file in SSMS / DBeaver / VS Code (mssql), or
                 python scripts/run_queries_local.py (SQLite, no server).
   ===================================================================== */


/* =====================================================================
   CUSTOMER 01 - CUSTOMER COUNT BY GENDER x OCCUPATION      (brief Q4)
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth / CRM
   Question    : Who are our customers? (demographic profile)
   Note        : gender is NULL for a small number of customers (dq_01e);
                 they are kept as 'Unknown' rather than dropped so the
                 totals reconcile with the customer table.
   ===================================================================== */


-- @output crm_01_customers_by_gender_occupation
-- Q4: customer count per gender x occupation (long format).
SELECT COALESCE(gender, 'Unknown')                                  AS gender,
       occupation,
       COUNT(*)                                                     AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)            AS share_of_customers_pct
FROM e_commerce.customer
GROUP BY COALESCE(gender, 'Unknown'), occupation
ORDER BY occupation, COALESCE(gender, 'Unknown');


-- @output crm_01b_occupation_by_gender_pivot
-- Same numbers pivoted: one row per occupation, one column per gender.
SELECT occupation,
       SUM(CASE WHEN gender = 'F'      THEN 1 ELSE 0 END)           AS female,
       SUM(CASE WHEN gender = 'M'      THEN 1 ELSE 0 END)           AS male,
       SUM(CASE WHEN gender IS NULL    THEN 1 ELSE 0 END)           AS unknown_gender,
       COUNT(*)                                                     AS total_customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)            AS share_of_customers_pct
FROM e_commerce.customer
GROUP BY occupation
ORDER BY total_customers DESC;


-- @output crm_01c_customer_value_by_occupation
-- Does the demographic profile translate into value? (customer x sales)
WITH cust_value AS (
    SELECT c.occupation,
           COALESCE(c.gender, 'Unknown') AS gender,
           c.customer_id,
           SUM(s.sales)                  AS revenue,
           SUM(s.profit)                 AS profit,
           COUNT(DISTINCT s.order_id)    AS orders
    FROM e_commerce.customer c
    JOIN e_commerce.ecom_sales s ON s.customer_id = c.customer_id
    GROUP BY c.occupation, COALESCE(c.gender, 'Unknown'), c.customer_id
)
SELECT occupation,
       gender,
       COUNT(*)                                        AS customers,
       ROUND(SUM(revenue), 2)                          AS revenue,
       ROUND(SUM(revenue) / COUNT(*), 2)               AS revenue_per_customer,
       ROUND(100.0 * SUM(profit) / SUM(revenue), 2)    AS gross_margin_pct,
       ROUND(1.0 * SUM(orders) / COUNT(*), 2)          AS orders_per_customer
FROM cust_value
GROUP BY occupation, gender
ORDER BY revenue_per_customer DESC;


/* =====================================================================
   CUSTOMER 02 - VIP CUSTOMERS AT RISK OF CHURN             (brief Q8)
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth (retention / win-back)
   Definitions : VIP      = top 5% of customers by lifetime revenue
                            (NTILE(20) over revenue = vigintile 1)
                 at risk  = no order in the 365 days before the anchor
                            date. The anchor is the last order date in
                            the data (2023-12-31), NOT today's date.
                 Why 365? The median gap between two orders of a repeat
                 customer is ~300 days (crm_05), so 180 days would flag
                 customers who are simply on their normal cycle.
   ===================================================================== */


-- @output crm_02_vip_churn_risk_summary
-- Q8: how many top-5% customers have gone quiet for over a year, and the revenue at stake.
WITH params AS (
    SELECT MAX(order_date) AS anchor_date FROM e_commerce.ecom_sales
),
cust AS (
    SELECT customer_id,
           segment,
           SUM(sales)               AS lifetime_revenue,
           SUM(profit)              AS lifetime_profit,
           COUNT(DISTINCT order_id) AS orders,
           MAX(order_date)          AS last_order_date
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, segment
),
scored AS (
    SELECT c.*,
           NTILE(20) OVER (ORDER BY c.lifetime_revenue DESC)      AS revenue_vigintile,
           DATEDIFF(day, c.last_order_date, p.anchor_date)        AS days_since_last_order
    FROM cust c
    CROSS JOIN params p
)
SELECT COUNT(*)                                                                    AS vip_customers,
       ROUND(MIN(lifetime_revenue), 2)                                             AS vip_revenue_threshold,
       ROUND(SUM(lifetime_revenue), 2)                                             AS vip_lifetime_revenue,
       ROUND(100.0 * SUM(lifetime_revenue)
             / (SELECT SUM(sales) FROM e_commerce.ecom_sales), 2)                 AS vip_share_of_total_revenue_pct,
       SUM(CASE WHEN days_since_last_order > 365 THEN 1 ELSE 0 END)                AS vip_at_risk_365d,
       ROUND(100.0 * SUM(CASE WHEN days_since_last_order > 365 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                                        AS vip_at_risk_pct,
       ROUND(SUM(CASE WHEN days_since_last_order > 365 THEN lifetime_revenue ELSE 0 END), 2) AS revenue_at_risk,
       SUM(CASE WHEN days_since_last_order > 180 THEN 1 ELSE 0 END)                AS vip_inactive_180d_for_reference
FROM scored
WHERE revenue_vigintile = 1;


-- @output crm_02b_vip_churn_risk_list
-- Action list for the win-back campaign, most valuable first.
WITH params AS (
    SELECT MAX(order_date) AS anchor_date FROM e_commerce.ecom_sales
),
cust AS (
    SELECT customer_id,
           segment,
           SUM(sales)               AS lifetime_revenue,
           SUM(profit)              AS lifetime_profit,
           COUNT(DISTINCT order_id) AS orders,
           MIN(order_date)          AS first_order_date,
           MAX(order_date)          AS last_order_date
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, segment
),
scored AS (
    SELECT c.*,
           NTILE(20) OVER (ORDER BY c.lifetime_revenue DESC)      AS revenue_vigintile,
           RANK()    OVER (ORDER BY c.lifetime_revenue DESC)      AS revenue_rank,
           DATEDIFF(day, c.last_order_date, p.anchor_date)        AS days_since_last_order
    FROM cust c
    CROSS JOIN params p
)
SELECT sc.revenue_rank,
       sc.customer_id,
       CONCAT(cu.first_name, ' ', cu.last_name)   AS customer_name,
       sc.segment,
       ROUND(sc.lifetime_revenue, 2)              AS lifetime_revenue,
       ROUND(sc.lifetime_profit, 2)               AS lifetime_profit,
       sc.orders,
       sc.first_order_date,
       sc.last_order_date,
       sc.days_since_last_order
FROM scored sc
JOIN e_commerce.customer cu ON cu.customer_id = sc.customer_id
WHERE sc.revenue_vigintile = 1
  AND sc.days_since_last_order > 365
ORDER BY sc.lifetime_revenue DESC;


/* =====================================================================
   CUSTOMER 03 - CROSS-SELL: CONSUMER vs CORPORATE           (brief Q9)
   ---------------------------------------------------------------------
   Stakeholder : CMO / Head of Growth
   Question    : Do Consumer and Corporate customers buy different
                 categories, and does either segment buy broader baskets?
   Two views   : (a) category mix - share of each segment's revenue by
                     category (conditional aggregation = pivot)
                 (b) basket depth per segment - lines, distinct products
                     and value per order (fact table only, no catalog)
   Caveat      : (a) uses the catalog's category label, which dq_02f shows
                 is independent of the product name - identical mixes
                 across segments are therefore expected. (b) needs no
                 catalog and is the view to trust.
   ===================================================================== */


-- @output crm_03_category_mix_consumer_vs_corporate
-- Q9: share of each segment revenue by category, side by side (conditional aggregation).
WITH seg_cat AS (
    SELECT s.segment,
           COALESCE(p.category, 'Unknown (code not in product table)') AS category,
           SUM(s.sales)               AS revenue,
           COUNT(DISTINCT s.order_id) AS orders
    FROM e_commerce.ecom_sales s
    LEFT JOIN e_commerce.product p ON p.product_code = s.product_code
    WHERE s.segment IN ('Consumer', 'Corporate')
    GROUP BY s.segment, COALESCE(p.category, 'Unknown (code not in product table)')
),
seg_total AS (
    SELECT segment, SUM(revenue) AS segment_revenue
    FROM seg_cat
    GROUP BY segment
),
pivoted AS (
    SELECT sc.category,
           SUM(CASE WHEN sc.segment = 'Consumer'  THEN sc.revenue ELSE 0 END)                       AS consumer_revenue,
           SUM(CASE WHEN sc.segment = 'Consumer'  THEN 100.0 * sc.revenue / st.segment_revenue END) AS consumer_share_pct,
           SUM(CASE WHEN sc.segment = 'Corporate' THEN sc.revenue ELSE 0 END)                       AS corporate_revenue,
           SUM(CASE WHEN sc.segment = 'Corporate' THEN 100.0 * sc.revenue / st.segment_revenue END) AS corporate_share_pct
    FROM seg_cat sc
    JOIN seg_total st ON st.segment = sc.segment
    GROUP BY sc.category
)
SELECT category,
       ROUND(consumer_revenue, 2)                        AS consumer_revenue,
       ROUND(consumer_share_pct, 2)                      AS consumer_share_pct,
       ROUND(corporate_revenue, 2)                       AS corporate_revenue,
       ROUND(corporate_share_pct, 2)                     AS corporate_share_pct,
       ROUND(corporate_share_pct - consumer_share_pct, 2) AS corporate_minus_consumer_pts
FROM pivoted
ORDER BY consumer_revenue DESC;


-- @output crm_03b_basket_depth_by_segment
-- Cross-sell measured without the catalog: how deep is the basket?
WITH basket AS (
    SELECT order_id,
           segment,
           COUNT(*)                     AS lines,
           COUNT(DISTINCT product_code) AS distinct_products,
           SUM(quantity)                AS units,
           SUM(sales)                   AS order_value,
           SUM(profit)                  AS order_profit
    FROM e_commerce.ecom_sales
    GROUP BY order_id, segment
)
SELECT segment,
       COUNT(*)                                                          AS orders,
       ROUND(AVG(1.0 * distinct_products), 2)                            AS avg_products_per_order,
       ROUND(AVG(1.0 * units), 2)                                        AS avg_units_per_order,
       ROUND(100.0 * SUM(CASE WHEN distinct_products >= 2 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                              AS multi_product_orders_pct,
       ROUND(100.0 * SUM(CASE WHEN distinct_products >= 3 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                              AS orders_with_3_plus_products_pct,
       ROUND(AVG(order_value), 2)                                        AS avg_order_value,
       ROUND(100.0 * SUM(order_profit) / SUM(order_value), 2)            AS gross_margin_pct
FROM basket
GROUP BY segment
ORDER BY avg_products_per_order DESC;


/* =====================================================================
   CUSTOMER 04 - RFM SEGMENTATION                          (brief Q14)
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth / CRM (pain point #4: LTV gap)
   Definitions : anchor date = last order date in the data (2023-12-31)
                 Recency   = days from customer's last order to anchor
                 Frequency = number of distinct orders
                 Monetary  = lifetime revenue (SUM sales)
   Scoring     : R and M -> NTILE(5) quintiles (5 = best)
                 F -> fixed thresholds, NOT NTILE: ~69% of customers have
                      exactly one order, so NTILE would split identical
                      values across quintiles arbitrarily.
                      1 order=1, 2=2, 3=3, 4=4, 5+=5
   Segments    : rule-based CASE on (R, F, M); rules evaluated top-down.
   ===================================================================== */


-- @output crm_04_rfm_segment_summary
-- Q14: customers, revenue and averages per RFM segment.
WITH params AS (
    SELECT MAX(order_date) AS anchor_date FROM e_commerce.ecom_sales
),
cust AS (
    SELECT customer_id,
           segment                  AS business_segment,
           MAX(order_date)          AS last_order_date,
           COUNT(DISTINCT order_id) AS frequency,
           SUM(sales)               AS monetary,
           SUM(profit)              AS lifetime_profit
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, segment
),
rfm_raw AS (
    SELECT c.*,
           DATEDIFF(day, c.last_order_date, p.anchor_date) AS recency_days
    FROM cust c
    CROSS JOIN params p
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC, customer_id) AS r_score,   -- most recent -> 5
           CASE WHEN frequency >= 5 THEN 5
                WHEN frequency  = 4 THEN 4
                WHEN frequency  = 3 THEN 3
                WHEN frequency  = 2 THEN 2
                ELSE 1 END                                         AS f_score,
           NTILE(5) OVER (ORDER BY monetary ASC, customer_id)      AS m_score    -- biggest spender -> 5
    FROM rfm_raw
),
labelled AS (
    SELECT *,
           CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '1. Champions'
                WHEN r_score >= 3 AND f_score >= 3                  THEN '2. Loyal'
                WHEN r_score >= 4 AND f_score  = 2                  THEN '3. Potential loyalist'
                WHEN r_score >= 4 AND f_score  = 1                  THEN '4. New / recent one-timer'
                WHEN r_score  = 3 AND f_score <= 2                  THEN '5. Promising'
                WHEN r_score <= 2 AND (f_score >= 3 OR m_score >= 4) THEN '6. At risk (valuable, lapsed)'
                ELSE                                                     '7. Hibernating'
           END AS rfm_segment
    FROM scored
)
SELECT rfm_segment,
       COUNT(*)                                                     AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)            AS share_of_customers_pct,
       ROUND(SUM(monetary), 2)                                      AS revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2)  AS share_of_revenue_pct,
       ROUND(AVG(1.0 * recency_days), 0)                            AS avg_recency_days,
       ROUND(AVG(1.0 * frequency), 2)                               AS avg_orders,
       ROUND(AVG(monetary), 2)                                      AS avg_lifetime_revenue,
       ROUND(100.0 * SUM(lifetime_profit) / SUM(monetary), 2)       AS gross_margin_pct
FROM labelled
GROUP BY rfm_segment
ORDER BY rfm_segment;


-- @output crm_04b_rfm_customer_scores
-- Customer-level scores (input for CRM lists / Tableau).
WITH params AS (
    SELECT MAX(order_date) AS anchor_date FROM e_commerce.ecom_sales
),
cust AS (
    SELECT customer_id,
           segment                  AS business_segment,
           MAX(order_date)          AS last_order_date,
           COUNT(DISTINCT order_id) AS frequency,
           SUM(sales)               AS monetary
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, segment
),
rfm_raw AS (
    SELECT c.*,
           DATEDIFF(day, c.last_order_date, p.anchor_date) AS recency_days
    FROM cust c
    CROSS JOIN params p
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC, customer_id) AS r_score,
           CASE WHEN frequency >= 5 THEN 5
                WHEN frequency  = 4 THEN 4
                WHEN frequency  = 3 THEN 3
                WHEN frequency  = 2 THEN 2
                ELSE 1 END                                         AS f_score,
           NTILE(5) OVER (ORDER BY monetary ASC, customer_id)      AS m_score
    FROM rfm_raw
)
SELECT customer_id,
       business_segment,
       last_order_date,
       recency_days,
       frequency,
       ROUND(monetary, 2) AS monetary,
       r_score,
       f_score,
       m_score,
       CONCAT(r_score, f_score, m_score) AS rfm_code,
       CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '1. Champions'
            WHEN r_score >= 3 AND f_score >= 3                  THEN '2. Loyal'
            WHEN r_score >= 4 AND f_score  = 2                  THEN '3. Potential loyalist'
            WHEN r_score >= 4 AND f_score  = 1                  THEN '4. New / recent one-timer'
            WHEN r_score  = 3 AND f_score <= 2                  THEN '5. Promising'
            WHEN r_score <= 2 AND (f_score >= 3 OR m_score >= 4) THEN '6. At risk (valuable, lapsed)'
            ELSE                                                     '7. Hibernating'
       END AS rfm_segment
FROM scored
ORDER BY monetary DESC;


/* =====================================================================
   CUSTOMER 05 - REPEAT RATE BY FIRST-PURCHASE COHORT (pain point #4, extra)
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth
   Pain point  : "Most customers buy once and disappear."
   Method      : cohort = year of the customer's first order; measure how
                 many ever came back, how long it took, and what a repeat
                 customer is worth vs. a one-time buyer.
   Caution     : recent cohorts are right-censored - a 2023 customer has
                 had less than a year to return, so compare cohorts using
                 the 12-month repeat rate, not the lifetime one.
   ===================================================================== */


-- @output crm_05_repeat_rate_by_cohort
-- Repeat behaviour by first-purchase year: lifetime and 12-month repeat rate, value of repeaters.
WITH orders AS (
    SELECT customer_id,
           order_id,
           MIN(order_date) AS order_date,
           SUM(sales)      AS order_value
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, order_id
),
first_order AS (
    SELECT customer_id,
           MIN(order_date)          AS first_order_date,
           COUNT(*)                 AS lifetime_orders,
           SUM(order_value)         AS lifetime_revenue
    FROM orders
    GROUP BY customer_id
),
second_order AS (
    SELECT o.customer_id,
           MIN(o.order_date) AS second_order_date
    FROM orders o
    JOIN first_order f ON f.customer_id = o.customer_id
    WHERE o.order_date > f.first_order_date
    GROUP BY o.customer_id
)
SELECT YEAR(f.first_order_date)                                            AS cohort_year,
       COUNT(*)                                                            AS new_customers,
       SUM(CASE WHEN f.lifetime_orders > 1 THEN 1 ELSE 0 END)              AS ever_repeated,
       ROUND(100.0 * SUM(CASE WHEN f.lifetime_orders > 1 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                                AS lifetime_repeat_rate_pct,
       SUM(CASE WHEN DATEDIFF(day, f.first_order_date, s.second_order_date) <= 365
                THEN 1 ELSE 0 END)                                         AS repeated_within_12m,
       ROUND(100.0 * SUM(CASE WHEN DATEDIFF(day, f.first_order_date, s.second_order_date) <= 365
                              THEN 1 ELSE 0 END) / COUNT(*), 2)            AS repeat_rate_12m_pct,
       ROUND(AVG(CASE WHEN s.second_order_date IS NOT NULL
                      THEN 1.0 * DATEDIFF(day, f.first_order_date, s.second_order_date) END), 0)
                                                                           AS avg_days_to_second_order,
       ROUND(AVG(CASE WHEN f.lifetime_orders = 1 THEN f.lifetime_revenue END), 2) AS avg_revenue_one_time_buyer,
       ROUND(AVG(CASE WHEN f.lifetime_orders > 1 THEN f.lifetime_revenue END), 2) AS avg_revenue_repeat_buyer
FROM first_order f
LEFT JOIN second_order s ON s.customer_id = f.customer_id
GROUP BY YEAR(f.first_order_date)
ORDER BY cohort_year;


-- @output crm_05b_inter_purchase_interval
-- Distribution of the gap between consecutive orders (basis for the
-- 365-day churn threshold used in crm_02).
WITH orders AS (
    SELECT customer_id,
           order_id,
           MIN(order_date) AS order_date
    FROM e_commerce.ecom_sales
    GROUP BY customer_id, order_id
),
gaps AS (
    SELECT customer_id,
           DATEDIFF(day,
                    LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date, order_id),
                    order_date) AS gap_days
    FROM orders
),
bucketed AS (
    SELECT CASE WHEN gap_days <= 90  THEN '1. 0-90 days'
                WHEN gap_days <= 180 THEN '2. 91-180 days'
                WHEN gap_days <= 365 THEN '3. 181-365 days'
                WHEN gap_days <= 730 THEN '4. 1-2 years'
                ELSE                      '5. over 2 years' END AS gap_bucket
    FROM gaps
    WHERE gap_days IS NOT NULL          -- first order of each customer has no gap
)
SELECT gap_bucket,
       COUNT(*)                                                      AS repeat_orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)             AS share_pct,
       ROUND(100.0 * SUM(COUNT(*)) OVER (ORDER BY gap_bucket ROWS UNBOUNDED PRECEDING)
             / SUM(COUNT(*)) OVER (), 2)                              AS cumulative_share_pct
FROM bucketed
GROUP BY gap_bucket
ORDER BY gap_bucket;
