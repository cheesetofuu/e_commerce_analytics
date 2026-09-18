/* =====================================================================
   FINANCE - P&L
   ---------------------------------------------------------------------
   Stakeholder : Head of Finance
   Scope       : Q1 total revenue & profit, Q2 revenue by segment, Q7 loss orders by segment. Pain point #2: segment profitability.
   Schema      : e_commerce (XómDataset, SQL Server). Dialect: T-SQL.
   How to read : each `-- @output <name>` marker starts one statement;
                 its result is the sheet <name> in results/01_finance_pnl.xlsx.
   Run         : whole file in SSMS / DBeaver / VS Code (mssql), or
                 python scripts/run_queries_local.py (SQLite, no server).
   ===================================================================== */


/* =====================================================================
   FINANCE 01 - TOTAL REVENUE AND PROFIT                  (brief Q1)
   ---------------------------------------------------------------------
   Stakeholder : Head of Finance ("CEO needs two numbers in 10 minutes")
   Question    : What is total revenue and total profit to date?
   Definitions : revenue = SUM(sales)  - transaction value per line
                 profit  = SUM(profit) - gross margin AFTER discount,
                           before logistics and operating costs
                 (state this definition when handing over the number:
                 "profit" means something different to every department)
   ===================================================================== */


-- @output fin_01_total_revenue_and_profit
-- Q1: the two numbers the CEO asked for, with margin, order count and date window.
SELECT ROUND(SUM(sales), 2)                                AS total_revenue,
       ROUND(SUM(profit), 2)                               AS total_profit,
       ROUND(100.0 * SUM(profit) / SUM(sales), 2)         AS gross_margin_pct,
       COUNT(DISTINCT order_id)                           AS orders,
       COUNT(*)                                           AS line_items,
       COUNT(DISTINCT customer_id)                        AS customers,
       ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2)    AS avg_order_value,
       MIN(order_date)                                    AS first_order_date,
       MAX(order_date)                                    AS last_order_date
FROM e_commerce.ecom_sales;


-- @output fin_01b_pnl_by_year
-- Same two numbers broken down by year, with growth vs. prior year.
WITH yearly AS (
    SELECT YEAR(order_date)            AS order_year,
           SUM(sales)                  AS revenue,
           SUM(profit)                 AS profit,
           COUNT(DISTINCT order_id)    AS orders,
           COUNT(DISTINCT customer_id) AS active_customers
    FROM e_commerce.ecom_sales
    GROUP BY YEAR(order_date)
)
SELECT order_year,
       ROUND(revenue, 2)                                              AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_year))
             / LAG(revenue) OVER (ORDER BY order_year), 2)            AS revenue_growth_pct,
       ROUND(profit, 2)                                               AS profit,
       ROUND(100.0 * (profit - LAG(profit) OVER (ORDER BY order_year))
             / LAG(profit) OVER (ORDER BY order_year), 2)             AS profit_growth_pct,
       ROUND(100.0 * profit / revenue, 2)                             AS gross_margin_pct,
       orders,
       active_customers,
       ROUND(revenue / orders, 2)                                     AS avg_order_value
FROM yearly
ORDER BY order_year;


/* =====================================================================
   FINANCE 02 - P&L BY SEGMENT                            (brief Q2)
   ---------------------------------------------------------------------
   Stakeholder : Head of Finance / C-suite
   Pain point  : "C-suite suspects Corporate is the cash cow, but the CFO
                 has never built a P&L by segment."
   Question    : Revenue by segment - extended to profit, margin, order
                 economics and discount depth so the cash-cow claim can
                 actually be tested.
   Note        : segment is stored on the order line; every customer has
                 exactly one segment (checked in dq_01e).
   ===================================================================== */


-- @output fin_02_pnl_by_segment
-- Q2: revenue by segment, extended to profit, margin, AOV and discount depth.
SELECT segment,
       ROUND(SUM(sales), 2)                                       AS revenue,
       ROUND(100.0 * SUM(sales)  / SUM(SUM(sales))  OVER (), 2)   AS revenue_share_pct,
       ROUND(SUM(profit), 2)                                      AS profit,
       ROUND(100.0 * SUM(profit) / SUM(SUM(profit)) OVER (), 2)   AS profit_share_pct,
       ROUND(100.0 * SUM(profit) / SUM(sales), 2)                 AS gross_margin_pct,
       COUNT(DISTINCT order_id)                                   AS orders,
       COUNT(DISTINCT customer_id)                                AS customers,
       ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2)            AS avg_order_value,
       ROUND(SUM(sales) / COUNT(DISTINCT customer_id), 2)         AS revenue_per_customer,
       ROUND(1.0 * COUNT(DISTINCT order_id)
             / COUNT(DISTINCT customer_id), 2)                    AS orders_per_customer,
       ROUND(100.0 * AVG(discount), 2)                            AS avg_line_discount_pct
FROM e_commerce.ecom_sales
GROUP BY segment
ORDER BY revenue DESC;


-- @output fin_02b_segment_pnl_by_year
-- Is any segment growing faster or losing margin over time?
WITH seg_year AS (
    SELECT segment,
           YEAR(order_date)         AS order_year,
           SUM(sales)               AS revenue,
           SUM(profit)              AS profit,
           COUNT(DISTINCT order_id) AS orders
    FROM e_commerce.ecom_sales
    GROUP BY segment, YEAR(order_date)
)
SELECT segment,
       order_year,
       ROUND(revenue, 2)                                                    AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (PARTITION BY segment ORDER BY order_year))
             / LAG(revenue) OVER (PARTITION BY segment ORDER BY order_year), 2) AS revenue_growth_pct,
       ROUND(profit, 2)                                                     AS profit,
       ROUND(100.0 * profit / revenue, 2)                                   AS gross_margin_pct,
       orders
FROM seg_year
ORDER BY segment, order_year;


/* =====================================================================
   FINANCE 03 - LOSS-MAKING ORDERS BY SEGMENT             (brief Q7)
   ---------------------------------------------------------------------
   Stakeholder : Head of Finance
   Question    : How many orders lose money in each segment, and how much?
   Grain       : ORDER level (SUM of line profit per order_id) - an order
                 with one loss line and two profitable lines is still a
                 profitable order. Line-level view is given as a second
                 result because it links directly to discount policy.
   ===================================================================== */


-- @output fin_03_loss_orders_by_segment
-- Q7: orders whose summed profit is negative, per segment, and what they cost.
WITH order_pnl AS (
    SELECT order_id,
           segment,
           SUM(sales)    AS order_sales,
           SUM(profit)   AS order_profit,
           MAX(discount) AS max_line_discount
    FROM e_commerce.ecom_sales
    GROUP BY order_id, segment
)
SELECT segment,
       COUNT(*)                                                         AS orders,
       SUM(CASE WHEN order_profit < 0 THEN 1 ELSE 0 END)                AS loss_orders,
       ROUND(100.0 * SUM(CASE WHEN order_profit < 0 THEN 1 ELSE 0 END)
             / COUNT(*), 2)                                             AS loss_order_rate_pct,
       ROUND(SUM(CASE WHEN order_profit < 0 THEN order_profit ELSE 0 END), 2)  AS total_loss,
       ROUND(SUM(CASE WHEN order_profit >= 0 THEN order_profit ELSE 0 END), 2) AS total_gain,
       ROUND(SUM(order_profit), 2)                                      AS net_profit,
       ROUND(100.0 * ABS(SUM(CASE WHEN order_profit < 0 THEN order_profit ELSE 0 END))
             / SUM(CASE WHEN order_profit >= 0 THEN order_profit ELSE 0 END), 2) AS loss_as_pct_of_gain,
       ROUND(100.0 * AVG(CASE WHEN order_profit < 0 THEN max_line_discount END), 2)  AS avg_max_discount_loss_orders_pct,
       ROUND(100.0 * AVG(CASE WHEN order_profit >= 0 THEN max_line_discount END), 2) AS avg_max_discount_profitable_orders_pct
FROM order_pnl
GROUP BY segment
ORDER BY loss_order_rate_pct DESC;


-- @output fin_03b_loss_lines_by_segment
-- Line-level view: loss lines almost always carry a discount.
SELECT segment,
       COUNT(*)                                                         AS line_items,
       SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END)                      AS loss_lines,
       ROUND(100.0 * SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS loss_line_rate_pct,
       SUM(CASE WHEN profit < 0 AND discount > 0 THEN 1 ELSE 0 END)     AS loss_lines_with_discount,
       SUM(CASE WHEN profit < 0 AND discount = 0 THEN 1 ELSE 0 END)     AS loss_lines_without_discount,
       ROUND(100.0 * AVG(CASE WHEN profit < 0  THEN discount END), 2)   AS avg_discount_on_loss_lines_pct,
       ROUND(100.0 * AVG(CASE WHEN profit >= 0 THEN discount END), 2)   AS avg_discount_on_profitable_lines_pct,
       ROUND(SUM(CASE WHEN profit < 0 THEN profit ELSE 0 END), 2)       AS total_line_loss
FROM e_commerce.ecom_sales
GROUP BY segment
ORDER BY loss_line_rate_pct DESC;
