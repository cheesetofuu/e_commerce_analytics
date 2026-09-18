# Data quality report — Xóm E-Com (`e_commerce` schema)

Every number in this repo was gated on the checks below before it was used.
Source queries: `sql/00_data_quality.sql`. Results: `results/00_data_quality.xlsx` (one sheet per check; ids such as `dq_02a` are sheet names).

## 1. Scope of the data

| Table | Rows | Key | Grain |
|---|---:|---|---|
| `ecom_sales` | 51,290 | `row_id` (unique) | one order **line** (order × product) |
| `customer` | 17,415 | `customer_id` (unique) | one customer |
| `region` | 3,828 | `region_code` (unique) | one **city** (city → state → country → region → market) |
| `product` | 28,356 | `product_code` (unique) | one SKU (only 3,578 ever sold) |

Order window: **2020-01-01 → 2023-12-31**, 48 consecutive months, 25,728 distinct orders,
17,415 customers (every customer in the customer table has at least one order).

Totals reconcile exactly with the answer published on the dataset page for Q1:
revenue **6,517,674** and profit **1,065,413.58** (sheet `fin_01` in `results/01_finance_pnl.xlsx`).

## 2. Integrity checks (`dq_01_*`)

| Check | Result | Handling |
|---|---|---|
| `sales.customer_id` → `customer` | 0 orphans | join freely |
| `sales.region_code` → `region` | 2 orphan lines (1 code, $486 revenue) | INNER JOIN in geographic queries; loss is immaterial and stated |
| `sales.product_code` → `product` | 2 orphan lines (the 2 malformed codes below, $90 revenue) | LEFT JOIN with an explicit `Unknown` bucket where category is used |
| Malformed product codes | 2 lines (`PPP000010`, `PPP000002`) | left as-is, cannot be matched |
| Value ranges | qty 1–20, sales 2–3,940, discount 0–0.85, profit −1,746 to 1,820; no zero/negative sales or quantity | no cleaning needed |
| Loss lines | 11,041 lines (21.5%) with profit < 0 | analysed, not removed — they are the discount story |
| Duplicate `(order_id, product_code)` | 102 pairs (102 extra rows) with different qty / discount | kept: they look like split lines, not duplicates; `row_id` stays the grain |
| Orders spanning >1 customer / >1 city | 11 / 26 orders | `order_id` is not a perfectly clean key; order-level queries group by `(order_id, segment)` and DQ reports it |
| Customers with >1 segment | 0 | segment can be treated as a customer attribute |
| Missing gender | 124 customers | kept as `Unknown` so counts reconcile |
| Catalog SKUs never sold | 24,780 of 28,356 (87%) | informational — the catalog is far wider than the range that sells |

## 3. The product dimension: complete, but its category labels carry no information

A first export of `product` was truncated at 1,154 rows (`P000001`–`P001154`); the dataset page lists
28.4K rows. The re-export in `data/` has **28,356 rows**, contiguous codes, no duplicates, and matches
**100% of sales lines** (only the 2 malformed codes remain unmatched). That closed the coverage problem.

It exposed a second one. Product names are recognisable (shampoos, nail polish, eyeshadow, jewellery,
vitamins), but the `category` / `subcategory` labels do not follow the names: earrings are labelled
*Hair care*, an eyeshadow *Body care*, an overnight face mask *Home and Accessories*. `dq_02f` tests this
directly — group products by an unambiguous keyword in the name and compare the label split inside
the group with the catalog-wide split:

| Name keyword group | Body care | Home & Acc. | Make up | Hair care | Face care |
|---|---:|---:|---:|---:|---:|
| whole catalog | 40.7% | 20.8% | 17.4% | 14.4% | 6.6% |
| jewellery (2,114) | 40.7% | 20.7% | 17.1% | 14.4% | 7.1% |
| shampoo / conditioner (2,111) | 41.6% | 20.5% | 18.1% | 13.3% | 6.4% |
| nail polish (2,570) | 38.1% | 23.7% | 18.8% | 13.1% | 6.3% |
| colour cosmetics (2,785) | 40.7% | 21.3% | 16.6% | 14.2% | 7.2% |

Every group reproduces the overall distribution to within a point or two: the label is statistically
independent of the product. Consequences:

* Product-level results (`mer_01`, `mer_02` rows, `mer_03`) are sound — they aggregate on `product_code`
  and only borrow the name from the catalog.
* Category-level results (`mkt_01`, `mer_02` grouping, `crm_03`) are kept because the brief asks for them,
  but any difference between categories is noise by construction, and the queries say so in their headers.
  Reassuringly, the results are flat: average discount 14.1–14.6% in every category, and Consumer and
  Corporate have identical category mixes to within ±1 point.
* A real category strategy needs a name-based classification (e.g. the keyword rules in `dq_02f`
  extended to the full catalog), which is out of scope here.

## 4. The business brief vs. the data (`dq_02_*`)

The context page describes the company in round numbers. Several of them do not match the tables:

| Brief says | Data says | Source |
|---|---|---|
| ~$2.3M revenue / year | $1.63M / year on average (2020–2023); 2023 alone is $2.19M | `dq_02a`, `fin_01b` |
| ~20% gross margin | 16.3% overall; 18.0–18.5% in 2020–2022, **12.8% in 2023** | `dq_02a`, `fin_01b` |
| Segments Consumer 60% / Corporate 25% / **Home Office** 15% | Consumer 52% / Corporate 30% / **Self-Employed** 18% of lines; by revenue Corporate is 59% | `dq_02b` |
| 4 markets: US, EMEA, APAC, LATAM | 5 markets: Asia Pacific, Europe, USCA, LATAM, **Africa** | `dq_02c` |
| 140+ countries | 164 countries with orders — consistent | `dq_02a` |
| ~1,900 SKUs in Office / Furniture / Technology | 28,356 catalog rows in cosmetics & jewellery categories (Body care, Make up, Hair care, Face care, Home and Accessories); 3,578 distinct codes actually sold; labels unrelated to names (§3) | `dq_02d`, `dq_02f` |
| — | `order_id` embeds a year that is exactly **8 years before** `order_date` for all 51,290 lines: the dates were shifted when the dataset was built. Month-of-year seasonality is preserved; weekday effects are not meaningful | `dq_02e` |

The analysis therefore uses the **data's** segment and market names, and states its own definitions
(§5) rather than the brief's.

## 5. Definitions used throughout

| Term | Definition |
|---|---|
| Revenue | `SUM(sales)` — transaction value per line, assumed net of discount (consistent with the source dataset's convention) |
| Profit / gross margin | `SUM(profit)` — gross margin **after discount, before logistics and operating cost** (the dataset page says the same) |
| Order | distinct `order_id` (25,728) |
| Loss order | order whose summed line profit is < 0 |
| Anchor date | 2023-12-31, the last order date — all recency measures use this, not today's date |
| VIP | top 5% of customers by lifetime revenue (`NTILE(20) = 1`, 871 customers, threshold ≈ $1,411) |
| At risk | no order in the 365 days before the anchor date (median gap between repeat orders is ~300 days) |
| RFM scores | R and M by quintile; F by fixed thresholds because 69% of customers have exactly one order |
