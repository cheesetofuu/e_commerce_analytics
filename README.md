# E-Commerce — SQL analytics case study

A stakeholder-driven analysis of a multi-market B2C e-commerce dataset on a SQL Server).
The dataset ships with 15 "ad-hoc requests" ordered by SQL difficulty; this repo reorganises them
by the **business function that asked**, adds the data-quality gate and the extra queries needed to
actually answer the company's four stated pain points, and delivers results and a written
recommendation — not just code.

| | |
|---|---|
| Data | 51,290 order lines · 25,728 orders · 17,415 customers · 28,356 catalog SKUs · 164 countries · 2020–2023 |
| Stack | T-SQL (SQL Server) · Python/pandas for reproduction and cross-validation |
| Deliverables | `sql/` one T-SQL file per domain · `results/` one Excel workbook per domain, one sheet per query · `reports/` data-quality report and business insights |

**Start here:** [`reports/02_business_insights.md`](reports/02_business_insights.md) (findings and recommendations)
→ [`reports/01_data_quality_report.md`](reports/01_data_quality_report.md) (what was checked and what to trust)
→ `sql/` (the queries) → `results/` (their output).

## The 15 requests, regrouped by stakeholder

| Domain / stakeholder | Pain point addressed | Requests | Extra queries added |
|---|---|---|---|
| `00_data_quality` — Business Analyst | trust the numbers first | — | integrity checks, brief-vs-data reconciliation, category-label test |
| `01_finance_pnl` — Head of Finance | #2 segment profitability | Q1 total revenue & profit · Q2 revenue by segment · Q7 loss orders by segment | yearly P&L, segment P&L by year |
| `02_pricing_discount` — CMO | #1 discount cannibalisation | Q5 average discount by category | discount-band profitability, exact-level break-even, discount by segment, discount mix vs. base margin by year |
| `03_merchandising` — Head of Merchandising | assortment & bundles | Q3 top-10 products · Q12 top-3 profit products per category · Q15 products bought together | top-10 by revenue, bottom-3 loss products, basket-size distribution |
| `04_market_growth` — Head of Growth | #3 geographic expansion | Q6 margin by market · Q10 top-15 countries · Q11 YoY growth by month · Q13 customers across regions | margin by region vs. company average, country growth trend, YoY by market |
| `05_customer_crm` — Head of Growth / CRM | #4 customer LTV gap | Q4 customers by gender × occupation · Q8 VIP churn risk · Q9 cross-sell Consumer vs Corporate · Q14 RFM segmentation | customer value by demographic, basket depth by segment, repeat rate by cohort, inter-purchase interval |

There is one SQL file per domain. Inside it, every question has its own header (stakeholder, question,
definitions, caveats) and every statement is preceded by a `-- @output <name>` marker; the result of
that statement is the sheet `<short id>` (e.g. `fin_02b`) in the domain's workbook `results/<domain>.xlsx`.
Each workbook opens on an `INDEX` sheet that links every sheet to its full output name and description.

## Repository layout

```
├── data/                        the four raw CSV exports (customer, ecom_sales, product, region)
├── sql/
│   ├── 00_data_quality.sql      dq_01 integrity checks · dq_02 brief-vs-data reconciliation & category-label test
│   ├── 01_finance_pnl.sql       fin_01 totals & yearly P&L · fin_02 segment P&L · fin_03 loss orders
│   ├── 02_pricing_discount.sql  mkt_01 discount by category · mkt_02 discount bands, break-even, mix by year
│   ├── 03_merchandising.sql     mer_01 top products · mer_02 top/bottom per category · mer_03 market basket
│   ├── 04_market_growth.sql     gro_01 market margin · gro_02 countries · gro_03 YoY · gro_04 geographic span
│   └── 05_customer_crm.sql      crm_01 demographics · crm_02 VIP churn · crm_03 cross-sell · crm_04 RFM · crm_05 cohorts
├── results/                     one workbook per SQL file, one sheet per @output (48 sheets); _index.md lists them all
│   ├── 00_data_quality.xlsx
│   ├── 01_finance_pnl.xlsx
│   ├── 02_pricing_discount.xlsx
│   ├── 03_merchandising.xlsx
│   ├── 04_market_growth.xlsx
│   └── 05_customer_crm.xlsx
├── reports/
│   ├── 01_data_quality_report.md
│   └── 02_business_insights.md
└── scripts/
    ├── run_queries_local.py     rebuilds results/ from data/ with SQLite (no SQL Server needed)
    └── validate_results.py      recomputes the headline numbers in pandas and compares them with results/
```

## How to run

**On SQL Server (XómDataset credentials):** open any file in `sql/` in SSMS, DBeaver or VS Code (mssql
extension), connect, run. Files contain plain T-SQL — one result grid per `-- @output` statement, in the same
order as the sheets in the matching workbook.

**Locally, without SQL Server:**

```bash
pip install pandas openpyxl
python scripts/run_queries_local.py --data data --sql sql --out results   # ~15 s, 6 workbooks / 48 sheets
python scripts/validate_results.py --data data --results results        # 26 independent checks
```

The runner loads the CSVs into SQLite (attached as schema `e_commerce`), registers `YEAR`, `MONTH` and
`DATEDIFF`, and rewrites only two constructs (`DATEDIFF(day, …)`, outer `TOP (n)` → `LIMIT`). Everything
else — CTEs, window functions, `NTILE`, `LAG`, `FIRST_VALUE`, conditional aggregation — is identical in
both dialects, so the T-SQL file is the single source of truth. Totals reconcile to the cent with the
answer published on the dataset page for Q1.

## Headline findings

* Revenue grew ~24% a year to $2.19M in 2023, but 2023 profit fell 12% (margin 18.0% → 12.8%) — and the
  discount mix did **not** change; margin at a given discount level did. That is a cost question, not a marketing one.
* Discounts above 20% (22% of lines) lost $288k over four years; every level ≥ 35% is loss-making, 30% is break-even.
  Not a single undiscounted line loses money.
* Corporate is 59% of revenue at the **lowest** margin, because all segments receive the same discount policy.
* Europe: 9% average discount, 22% margin, +46% growth. Asia Pacific: 18% discount, margin down to 7% in 2023.
* 69% of customers buy once; 42% of the top-5% VIPs have been silent for over a year ($849k lifetime revenue).

Full detail and the prioritised recommendations: [`reports/02_business_insights.md`](reports/02_business_insights.md).

## Known data caveats (short version)

* The product table is complete (28,356 rows, 100% of sales lines match), but its `category` labels are
  statistically independent of the product names — earrings labelled *Hair care*, eyeshadow *Body care*.
  Product-level results are sound; category-level results are reported but carry no signal
  (`reports/01_data_quality_report.md`, §3, query `dq_02f`).
* The dataset's description (segments, markets, categories, revenue, margin) differs from the tables in
  several places; the analysis uses what the data says (§4 of the same report).
* `profit` is gross margin after discount, before logistics and operating cost.
