# E-commerce profitability & customer analytics — SQL case study

A stakeholder-driven analysis of a multi-market B2C e-commerce dataset
(51,290 order lines · 25,728 orders · 17,415 customers · 164 countries · 2020–2023),
written in T-SQL for SQL Server and reproducible locally with Python.

The work is organised the way an analyst would receive it in a company: by the
function that asks the question — Finance, Pricing, Merchandising, Growth, CRM —
with a data-quality gate in front, a result workbook for every query, and a
written report that turns the numbers into prioritised recommendations.

| | |
|---|---|
| Stack | T-SQL (SQL Server) · Python / pandas for reproduction and cross-validation |
| Deliverables | `sql/` one query file per domain · `results/` one Excel workbook per domain, one sheet per query · `reports/` data-quality report and business insights |

**Start here:** [`reports/02_business_insights.md`](reports/02_business_insights.md) (findings and recommendations)
→ [`reports/01_data_quality_report.md`](reports/01_data_quality_report.md) (what was checked and what to trust)
→ `sql/` (the queries) → `results/` (their output).

## What the analysis covers

| Domain | Stakeholder | Business question |
|---|---|---|
| `00_data_quality` | Analyst | Can the numbers be trusted? Key integrity, value ranges, order grain, and a reconciliation of the business brief against the data |
| `01_finance_pnl` | Head of Finance | Total revenue and profit, P&L by year and by segment, loss-making orders — is Corporate really the cash cow? |
| `02_pricing_discount` | CMO | Does discounting eat profit? Margin by discount band and by exact discount level, break-even point, discount mix vs. base margin over time |
| `03_merchandising` | Head of Merchandising | Best-selling and most profitable products, biggest loss-makers, basket size, products bought together (market basket) |
| `04_market_growth` | Head of Growth | Margin by market and region, top countries and their growth trend, year-over-year growth by month, customers ordering across regions |
| `05_customer_crm` | Head of Growth / CRM | Customer demographics and value, VIP customers at churn risk, cross-sell by segment, RFM segmentation, repeat rate by cohort |

Techniques: CTEs, window functions (`ROW_NUMBER`, `NTILE`, `LAG`, `FIRST_VALUE`, running totals),
conditional aggregation (pivot), self-joins, cohort and RFM logic — 48 result sets in total.

Inside each SQL file every question has its own header (stakeholder, question, definitions, caveats),
and every statement is preceded by a `-- @output <name>` marker; its result is the sheet with that
short id (e.g. `fin_02b`) in the domain's workbook `results/<domain>.xlsx`. Each workbook opens on
an `INDEX` sheet linking every sheet to its full name and description.

## Repository layout

```
├── data/                        the four raw tables (customer, ecom_sales, product, region) as CSV
├── sql/
│   ├── 00_data_quality.sql      integrity checks · brief-vs-data reconciliation · category-label test
│   ├── 01_finance_pnl.sql       totals & yearly P&L · segment P&L · loss orders
│   ├── 02_pricing_discount.sql  discount by category · discount bands, break-even, mix by year
│   ├── 03_merchandising.sql     top products · top / bottom per category · market basket
│   ├── 04_market_growth.sql     market margin · countries · YoY growth · geographic span
│   └── 05_customer_crm.sql      demographics · VIP churn · cross-sell · RFM · cohorts
├── results/                     one workbook per SQL file, one sheet per query; _index.md lists them all
├── reports/
│   ├── 01_data_quality_report.md
│   └── 02_business_insights.md
└── scripts/
    ├── run_queries_local.py     rebuilds results/ from data/ with SQLite (no SQL Server needed)
    └── validate_results.py      recomputes the headline numbers in pandas and compares them with results/
```

## How to run

**On SQL Server:** open any file in `sql/` in SSMS, DBeaver or VS Code (mssql extension), connect
to a database holding the four tables in schema `e_commerce`, and run. One result grid per
`-- @output` statement, in the same order as the sheets in the matching workbook.

**Locally, without SQL Server:**

```bash
pip install pandas openpyxl
python scripts/run_queries_local.py --data data --sql sql --out results   # ~15 s, 6 workbooks / 48 sheets
python scripts/validate_results.py --data data --results results        # 26 independent checks
```

The runner loads the CSVs into SQLite (attached as schema `e_commerce`), registers `YEAR`, `MONTH`
and `DATEDIFF`, and rewrites only two constructs (`DATEDIFF(day, …)`, outer `TOP (n)` → `LIMIT`).
Everything else is identical in both dialects, so the T-SQL file is the single source of truth.

## Headline findings

* Revenue grew ~24% a year to $2.19M in 2023, but 2023 profit fell 12% (gross margin 18.0% → 12.8%) —
  and the discount mix did **not** change; margin at a given discount level did. That is a cost question,
  not a marketing one.
* Discounts above 20% (22% of lines) lost $288k over four years; every level ≥ 35% is loss-making,
  30% is break-even. Not a single undiscounted line loses money.
* Corporate is 59% of revenue at the **lowest** margin of the three segments, because every segment
  receives the same discount policy.
* Europe: 9% average discount, 22% margin, +46% growth. Asia Pacific: 18% discount, margin down to 7% in 2023.
* 69% of customers buy once; 42% of the top-5% customers have been silent for over a year ($849k lifetime revenue).

Full detail and nine prioritised recommendations with owners and expected impact:
[`reports/02_business_insights.md`](reports/02_business_insights.md).

## Data caveats (short version)

* `profit` is gross margin after discount, before logistics and operating cost.
* The product table's `category` labels are statistically independent of the product names
  (tested in `dq_02f`), so product-level results are sound while category-level results are reported
  without a merchandising signal.
* The dataset's own description (segments, markets, categories, revenue, margin) differs from the
  tables in several places; the analysis uses what the data says (`reports/01_data_quality_report.md`, §4).
* Order dates were shifted by a fixed number of years when the dataset was built: month-of-year
  seasonality holds, day-of-week effects do not.
