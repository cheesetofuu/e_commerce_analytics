/* =====================================================================
   MARKET GROWTH
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth
   Scope       : Q6 margin by market, Q10 top-15 countries, Q11 YoY growth by month, Q13 customers across regions. Pain point #3: geographic expansion.
   Schema      : e_commerce (XómDataset, SQL Server). Dialect: T-SQL.
   How to read : each `-- @output <name>` marker starts one statement;
                 its result is the sheet <name> in results/04_market_growth.xlsx.
   Run         : whole file in SSMS / DBeaver / VS Code (mssql), or
                 python scripts/run_queries_local.py (SQLite, no server).
   ===================================================================== */


/* =====================================================================
   GROWTH 01 - PROFIT MARGIN BY MARKET                     (brief Q6)
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth (geographic expansion)
   Question    : Which markets earn the best margin, and which regions
                 drag the company average down?
   Geography   : region table -> market (5) > region (23) > country > city
                 Every country maps to exactly one market (checked).
   ===================================================================== */


-- @output gro_01_profit_margin_by_market
-- Q6: revenue, profit, margin and discount depth per market.
SELECT r.market,
       COUNT(DISTINCT r.country)                                   AS countries,
       ROUND(SUM(s.sales), 2)                                      AS revenue,
       ROUND(100.0 * SUM(s.sales) / SUM(SUM(s.sales)) OVER (), 2)   AS revenue_share_pct,
       ROUND(SUM(s.profit), 2)                                     AS profit,
       ROUND(100.0 * SUM(s.profit) / SUM(SUM(s.profit)) OVER (), 2) AS profit_share_pct,
       ROUND(100.0 * SUM(s.profit) / SUM(s.sales), 2)              AS gross_margin_pct,
       ROUND(100.0 * AVG(s.discount), 2)                           AS avg_line_discount_pct,
       COUNT(DISTINCT s.order_id)                                  AS orders,
       COUNT(DISTINCT s.customer_id)                               AS customers,
       ROUND(SUM(s.sales) / COUNT(DISTINCT s.order_id), 2)         AS avg_order_value
FROM e_commerce.ecom_sales s
JOIN e_commerce.region r ON r.region_code = s.region_code
GROUP BY r.market
ORDER BY gross_margin_pct DESC;


-- @output gro_01b_margin_by_region_vs_company_average
-- Sub-regions with material revenue (HAVING >= $100k), flagged against the
-- company-wide margin so Growth can see where expansion would dilute margin.
WITH company AS (
    SELECT SUM(profit) / SUM(sales) AS company_margin
    FROM e_commerce.ecom_sales
)
SELECT r.market,
       r.region,
       COUNT(DISTINCT r.country)                          AS countries,
       ROUND(SUM(s.sales), 2)                             AS revenue,
       ROUND(SUM(s.profit), 2)                            AS profit,
       ROUND(100.0 * SUM(s.profit) / SUM(s.sales), 2)     AS gross_margin_pct,
       ROUND(100.0 * c.company_margin, 2)                 AS company_margin_pct,
       CASE WHEN SUM(s.profit) / SUM(s.sales) < c.company_margin
            THEN 'below company average' ELSE 'at or above average' END AS margin_flag,
       ROUND(100.0 * AVG(s.discount), 2)                  AS avg_line_discount_pct
FROM e_commerce.ecom_sales s
JOIN e_commerce.region r ON r.region_code = s.region_code
CROSS JOIN company c
GROUP BY r.market, r.region, c.company_margin
HAVING SUM(s.sales) >= 100000
ORDER BY gross_margin_pct ASC;


/* =====================================================================
   GROWTH 02 - TOP 15 COUNTRIES BY REVENUE                (brief Q10)
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth
   Question    : Which countries carry the business, and are they still
                 growing or already saturating?
   ===================================================================== */


-- @output gro_02_top15_countries_by_revenue
-- Q10: fifteen largest countries by revenue, with margin and customer counts.
SELECT TOP (15)
       r.country,
       r.market,
       ROUND(SUM(s.sales), 2)                                      AS revenue,
       ROUND(100.0 * SUM(s.sales) / SUM(SUM(s.sales)) OVER (), 2)   AS revenue_share_pct,
       ROUND(SUM(s.profit), 2)                                     AS profit,
       ROUND(100.0 * SUM(s.profit) / SUM(s.sales), 2)              AS gross_margin_pct,
       COUNT(DISTINCT s.order_id)                                  AS orders,
       COUNT(DISTINCT s.customer_id)                               AS customers,
       COUNT(DISTINCT r.city)                                      AS cities_with_orders,
       ROUND(SUM(s.sales) / COUNT(DISTINCT s.customer_id), 2)      AS revenue_per_customer
FROM e_commerce.ecom_sales s
JOIN e_commerce.region r ON r.region_code = s.region_code
GROUP BY r.country, r.market
ORDER BY revenue DESC;


-- @output gro_02b_top15_countries_growth_trend
-- Same 15 countries: revenue per year and last-year growth.
WITH country_year AS (
    SELECT r.country,
           r.market,
           YEAR(s.order_date) AS order_year,
           SUM(s.sales)       AS revenue
    FROM e_commerce.ecom_sales s
    JOIN e_commerce.region r ON r.region_code = s.region_code
    GROUP BY r.country, r.market, YEAR(s.order_date)
),
country_total AS (
    SELECT country, SUM(revenue) AS total_revenue
    FROM country_year
    GROUP BY country
),
top15 AS (
    SELECT country
    FROM (SELECT country, ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS rn
          FROM country_total) x
    WHERE rn <= 15
)
SELECT cy.country,
       cy.market,
       ROUND(SUM(CASE WHEN order_year = 2020 THEN revenue ELSE 0 END), 2) AS revenue_2020,
       ROUND(SUM(CASE WHEN order_year = 2021 THEN revenue ELSE 0 END), 2) AS revenue_2021,
       ROUND(SUM(CASE WHEN order_year = 2022 THEN revenue ELSE 0 END), 2) AS revenue_2022,
       ROUND(SUM(CASE WHEN order_year = 2023 THEN revenue ELSE 0 END), 2) AS revenue_2023,
       ROUND(100.0 * (SUM(CASE WHEN order_year = 2023 THEN revenue ELSE 0 END)
                      - SUM(CASE WHEN order_year = 2022 THEN revenue ELSE 0 END))
             / NULLIF(SUM(CASE WHEN order_year = 2022 THEN revenue ELSE 0 END), 0), 2) AS growth_2023_vs_2022_pct,
       ROUND(100.0 * (SUM(CASE WHEN order_year = 2023 THEN revenue ELSE 0 END)
                      - SUM(CASE WHEN order_year = 2020 THEN revenue ELSE 0 END))
             / NULLIF(SUM(CASE WHEN order_year = 2020 THEN revenue ELSE 0 END), 0), 2) AS growth_2023_vs_2020_pct
FROM country_year cy
JOIN top15 t ON t.country = cy.country
GROUP BY cy.country, cy.market
ORDER BY revenue_2023 DESC;


/* =====================================================================
   GROWTH 03 - YEAR-OVER-YEAR REVENUE GROWTH BY MONTH     (brief Q11)
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth
   Question    : Month by month, how does revenue compare with the same
                 month one year earlier? Where is growth slowing?
   Method      : CTE of monthly totals, then LAG(revenue, 12).
                 LAG(…, 12) assumes every month is present - dq_01c
                 confirms 48 distinct months for 2020-2023, so no gaps.
   Caution     : dq_02e shows order dates were shifted by a fixed number
                 of years, so month-of-year seasonality is preserved but
                 weekday effects are not meaningful.
   ===================================================================== */


-- @output gro_03_yoy_revenue_growth_by_month
-- Q11: monthly revenue vs. the same month one year earlier (LAG 12).
WITH monthly AS (
    SELECT YEAR(order_date)         AS order_year,
           MONTH(order_date)        AS order_month,
           SUM(sales)               AS revenue,
           SUM(profit)              AS profit,
           COUNT(DISTINCT order_id) AS orders
    FROM e_commerce.ecom_sales
    GROUP BY YEAR(order_date), MONTH(order_date)
),
with_prior AS (
    SELECT *,
           LAG(revenue, 12) OVER (ORDER BY order_year, order_month) AS revenue_same_month_prior_year,
           LAG(orders,  12) OVER (ORDER BY order_year, order_month) AS orders_same_month_prior_year
    FROM monthly
)
SELECT order_year,
       order_month,
       ROUND(revenue, 2)                                              AS revenue,
       ROUND(revenue_same_month_prior_year, 2)                        AS revenue_same_month_prior_year,
       ROUND(100.0 * (revenue - revenue_same_month_prior_year)
             / NULLIF(revenue_same_month_prior_year, 0), 2)           AS yoy_revenue_growth_pct,
       orders,
       ROUND(100.0 * (orders - orders_same_month_prior_year)
             / NULLIF(orders_same_month_prior_year, 0), 2)            AS yoy_order_growth_pct,
       ROUND(100.0 * profit / revenue, 2)                             AS gross_margin_pct
FROM with_prior
ORDER BY order_year, order_month;


-- @output gro_03b_yoy_revenue_growth_by_market
-- Annual growth per market: which markets are growing, which are flattening?
WITH market_year AS (
    SELECT r.market,
           YEAR(s.order_date) AS order_year,
           SUM(s.sales)       AS revenue,
           SUM(s.profit)      AS profit
    FROM e_commerce.ecom_sales s
    JOIN e_commerce.region r ON r.region_code = s.region_code
    GROUP BY r.market, YEAR(s.order_date)
)
SELECT market,
       order_year,
       ROUND(revenue, 2)                                                       AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (PARTITION BY market ORDER BY order_year))
             / LAG(revenue) OVER (PARTITION BY market ORDER BY order_year), 2) AS yoy_revenue_growth_pct,
       ROUND(100.0 * profit / revenue, 2)                                      AS gross_margin_pct
FROM market_year
ORDER BY market, order_year;


/* =====================================================================
   GROWTH 04 - CUSTOMERS BUYING ACROSS SEVERAL REGIONS    (brief Q13)
   ---------------------------------------------------------------------
   Stakeholder : Head of Growth
   Question    : Do customers order from more than one region? If so,
                 where do they start and where do they end up?
   Geography   : the region table has one row per CITY (region_code);
                 city -> state -> country -> region (23) -> market (5).
                 This query measures the span at every level so the
                 answer cannot be misread (a customer may ship to two
                 cities in one country - that is not "two markets").
   Method      : FIRST_VALUE() over order_date to get first and latest
                 delivery city per customer.
   ===================================================================== */


-- @output gro_04_customer_geographic_span_summary
-- Q13: how many customers order from more than one city / state / country / region / market.
WITH cust_geo AS (
    SELECT s.customer_id,
           COUNT(DISTINCT r.region_code) AS cities,
           COUNT(DISTINCT r.state)       AS states,
           COUNT(DISTINCT r.country)     AS countries,
           COUNT(DISTINCT r.region)      AS regions,
           COUNT(DISTINCT r.market)      AS markets,
           COUNT(DISTINCT s.order_id)    AS orders,
           SUM(s.sales)                  AS revenue
    FROM e_commerce.ecom_sales s
    JOIN e_commerce.region r ON r.region_code = s.region_code
    GROUP BY s.customer_id
)
SELECT 'city (region_code)' AS geography_level,
       SUM(CASE WHEN cities > 1 THEN 1 ELSE 0 END)                             AS customers_spanning_2_plus,
       ROUND(100.0 * SUM(CASE WHEN cities > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS share_of_all_customers_pct,
       ROUND(100.0 * SUM(CASE WHEN cities > 1 THEN 1 ELSE 0 END)
             / SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END), 2)                  AS share_of_repeat_customers_pct,
       ROUND(SUM(CASE WHEN cities > 1 THEN revenue ELSE 0 END), 2)             AS revenue_from_spanning_customers
FROM cust_geo
UNION ALL
SELECT 'state',
       SUM(CASE WHEN states > 1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN states > 1 THEN 1 ELSE 0 END) / COUNT(*), 2),
       ROUND(100.0 * SUM(CASE WHEN states > 1 THEN 1 ELSE 0 END)
             / SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END), 2),
       ROUND(SUM(CASE WHEN states > 1 THEN revenue ELSE 0 END), 2)
FROM cust_geo
UNION ALL
SELECT 'country',
       SUM(CASE WHEN countries > 1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN countries > 1 THEN 1 ELSE 0 END) / COUNT(*), 2),
       ROUND(100.0 * SUM(CASE WHEN countries > 1 THEN 1 ELSE 0 END)
             / SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END), 2),
       ROUND(SUM(CASE WHEN countries > 1 THEN revenue ELSE 0 END), 2)
FROM cust_geo
UNION ALL
SELECT 'region (23 sub-regions)',
       SUM(CASE WHEN regions > 1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN regions > 1 THEN 1 ELSE 0 END) / COUNT(*), 2),
       ROUND(100.0 * SUM(CASE WHEN regions > 1 THEN 1 ELSE 0 END)
             / SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END), 2),
       ROUND(SUM(CASE WHEN regions > 1 THEN revenue ELSE 0 END), 2)
FROM cust_geo
UNION ALL
SELECT 'market (5)',
       SUM(CASE WHEN markets > 1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN markets > 1 THEN 1 ELSE 0 END) / COUNT(*), 2),
       ROUND(100.0 * SUM(CASE WHEN markets > 1 THEN 1 ELSE 0 END)
             / SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END), 2),
       ROUND(SUM(CASE WHEN markets > 1 THEN revenue ELSE 0 END), 2)
FROM cust_geo;


-- @output gro_04b_multi_city_customers_first_vs_latest
-- Customers who ordered from 2+ cities: first delivery city vs. latest one.
WITH ordered AS (
    SELECT s.customer_id,
           s.order_id,
           s.order_date,
           s.sales,
           r.city,
           r.country,
           r.market,
           FIRST_VALUE(r.city) OVER (PARTITION BY s.customer_id
                                     ORDER BY s.order_date ASC,  s.order_id ASC)  AS first_city,
           FIRST_VALUE(r.city) OVER (PARTITION BY s.customer_id
                                     ORDER BY s.order_date DESC, s.order_id DESC) AS latest_city
    FROM e_commerce.ecom_sales s
    JOIN e_commerce.region r ON r.region_code = s.region_code
)
SELECT TOP (50)
       customer_id,
       MIN(country)                  AS country,      -- exact: dq shows one country per customer
       COUNT(DISTINCT country)       AS countries,
       MIN(market)                   AS market,
       COUNT(DISTINCT city)          AS cities,
       MIN(first_city)               AS first_city,
       MIN(latest_city)              AS latest_city,
       COUNT(DISTINCT order_id)      AS orders,
       ROUND(SUM(sales), 2)          AS revenue,
       MIN(order_date)               AS first_order_date,
       MAX(order_date)               AS latest_order_date
FROM ordered
GROUP BY customer_id
HAVING COUNT(DISTINCT city) > 1
ORDER BY cities DESC, revenue DESC;
