# Xóm E-Com — business insights & recommendations

Scope: 51,290 order lines, 25,728 orders, 17,415 customers, 164 countries, Jan 2020 – Dec 2023.
Every figure below is produced by a query in `sql/` and can be read in the matching sheet of the domain
workbook in `results/` (sheet ids in brackets, e.g. *fin_01b* is a sheet in `01_finance_pnl.xlsx`). Data caveats are in `reports/01_data_quality_report.md`.

## Executive summary

1. **Revenue grows ~24% a year, but 2023 profit fell 12%.** Revenue 2023: $2.19M (+23.8%); profit $280k (−12.2%); gross margin dropped from 18.0% to 12.8%. *(fin_01b)*
2. **The margin drop is not a discount-mix problem.** Discount depth and frequency were flat in 2023 (42.7% of lines discounted, avg 14.3%, same as every prior year). What changed is the margin at a given discount level: undiscounted lines earned 33% in 2020–2022 and 27.7% in 2023; discounted lines went from −1.4% to −5.9%. That points at cost of goods or fulfilment cost, not at marketing. *(mkt_02d)*
3. **Deep discounts do eat profit — structurally, every year.** Lines discounted above 20% are 22% of lines and 22.6% of revenue, and lost **$288k** over four years (27% of all profit earned). Every discount level ≥ 35% is loss-making; ≥ 55% is loss-making on 100% of lines. Undiscounted lines alone produced 107% of total profit. In 2023 the deep-discount lines lost $111k — 40% of that year's profit. *(mkt_02, mkt_02b)*
4. **Corporate is the revenue cash cow, not the margin cash cow.** Corporate = 30% of orders but 59% of revenue and 57% of profit, with an average order of $497 (3× Consumer). Its gross margin (15.8%) is the lowest of the three segments, because every segment receives the same discount treatment (~14% average, ~21.5% loss orders each). *(fin_02, fin_03, mkt_02c)*
5. **Margin is a geography of discount policy.** Europe: 9% average discount, 22.3% margin, 31% of profit on 23% of revenue, and the fastest growth in 2023 (+46%). Asia Pacific: 18% average discount, 12.5% margin, sliding to 7.2% in 2023 while being the largest market (28% of revenue). Two sub-regions are loss-making outright: Western Africa (−15.6%, 43% average discount) and Western Asia (−5.3%, 35%). Turkey (−29%), Nigeria (−38%) and Indonesia (0%) sit in the top-15 revenue countries and earn nothing. *(gro_01, gro_01b, gro_02, gro_03b)*
6. **69% of customers never come back**, and the ones who do take a long time: only 16–19% of a cohort reorders within 12 months. A repeat customer is worth ~2.6× a one-time buyer ($550–$680 vs. $240–$265). *(crm_05)*
7. **Value is concentrated and leaking.** The top 5% of customers (871) generate 31.9% of revenue; 368 of them (42%) have not ordered in over a year — $849k of lifetime revenue at risk. In RFM terms, "At risk (valuable, lapsed)" is 13% of customers but 25% of revenue. *(crm_02, crm_04)*
8. **Baskets are shallow and identical across segments.** Half of all orders contain one product; basket depth is 1.99 products in every segment. No product pair appears together in more than 3 orders, so SKU-level bundles cannot be justified from the data. *(mer_03, mer_03b, crm_03b)*

## Findings by stakeholder

### Head of Finance — P&L

* Total revenue **$6.52M**, gross profit **$1.07M**, margin **16.35%**, AOV $253. *(fin_01)*
* Yearly: 2020 $1.15M / 18.0% → 2021 $1.41M / 18.5% → 2022 $1.77M / 18.0% → 2023 $2.19M / 12.8%. Orders and active customers both grew ~24–25% in 2023; AOV slipped slightly ($257 → $248). *(fin_01b)*
* Segment P&L *(fin_02)*:

  | Segment | Revenue | Share | Profit | Margin | AOV | Orders / customer |
  |---|---:|---:|---:|---:|---:|---:|
  | Corporate | $3.84M | 58.9% | $609k | 15.8% | $497 | 1.48 |
  | Consumer | $2.15M | 32.9% | $365k | 17.0% | $162 | 1.48 |
  | Self-Employed | $0.53M | 8.1% | $92k | 17.3% | $112 | 1.47 |

* All three segments lost margin in 2023 (Corporate 16.3% → 12.5%, Consumer 20.6% → 13.1%, Self-Employed 19.6% → 13.6%). *(fin_02b)*
* Loss orders: ~21.5% of orders in every segment. Corporate's loss orders cost $188k against $796k of gains (24%). Loss orders carry an average maximum discount of ~49% vs. ~7% on profitable orders. **Every single loss line has a discount; not one undiscounted line loses money.** *(fin_03, fin_03b)*

### CMO — pricing & discount

* Discount depth vs. outcome *(mkt_02, mkt_02b)*:

  | Discount band | Lines | Revenue share | Profit | Margin | Loss-line rate |
  |---|---:|---:|---:|---:|---:|
  | 0% | 57.5% | 56.0% | +$1,142k | 31.3% | 0% |
  | 1–20% | 20.5% | 21.4% | +$212k | 15.2% | 26% |
  | 21–40% | 8.6% | 9.1% | −$51k | −8.6% | 52% |
  | 41–60% | 9.2% | 9.5% | −$147k | −23.8% | 82% |
  | 61–85% | 4.1% | 4.0% | −$90k | −34.4% | 100% |

  By exact level: 10% discount still earns 20% margin with zero loss lines; 20% earns 11%; 30% is break-even (1.3%); 35% and above is negative at every level, with 50–100% of lines losing money.
* The discount pattern is identical in every segment (57% of lines undiscounted, ~22% above 20%). Discount is applied by geography, not by customer type. *(mkt_02c)*
* By category: average discount is 14.1–14.6% in every category — no category is discounted deeper than another. This is expected, because the catalog's category labels are unrelated to the products (`dq_02f`); discount is clearly not being steered by category either way. *(mkt_01)*

### Head of Merchandising — products & baskets

* Volume leader: `P000116` "Herbal Essences Bio", 1,780 units in 329 orders, $67.6k revenue, but only 13.4% margin at a 15% average discount. Second by units (`P000619`, 1,195 units) earns 19%. *(mer_01)*
* Revenue leaders are jewellery items at $25–30k each; one (`P002711` "Sterling Frost Ring") is loss-making at −2% with an 18.7% average discount. *(mer_01b)*
* Per-category top-3 by profit and bottom-3 by loss are in `mer_02` / `mer_02b`. Read them per product, not per category (the labels are noise): the top earners are jewellery at 20–33% margin, and the loss-makers share one trait — average discounts of 20–40%.
* Basket structure *(mer_03b)*: 1-product orders are 50% of orders but 24% of revenue; AOV climbs from $123 (1 product) to $265 (2) to $381 (3) to $753 (5+). Growing the basket by one item is worth more than any single-SKU promotion.
* Market basket *(mer_03)*: the most frequent pair (two hair-colour products) appears in only 3 of 25,728 orders (support 0.01%). With ~3,600 SKUs and 2 lines per order, SKU-pair affinity is statistically empty; a name-based product grouping would be needed to test affinity at a higher level.

### Head of Growth — markets, countries, geography

* Market scorecard *(gro_01, gro_03b)*:

  | Market | Revenue share | Profit share | Margin | Avg discount | 2023 growth | 2023 margin |
  |---|---:|---:|---:|---:|---:|---:|
  | Asia Pacific | 28.1% | 21.5% | 12.5% | 18.1% | +21.9% | 7.2% |
  | Europe | 22.8% | 31.1% | 22.3% | 9.1% | +45.6% | 18.5% |
  | USCA | 21.1% | 20.9% | 16.2% | 15.0% | +18.5% | 13.6% |
  | LATAM | 20.6% | 20.3% | 16.1% | 13.5% | +12.9% | 12.4% |
  | Africa | 7.5% | 6.2% | 13.6% | 15.7% | +17.1% | 13.1% |

* Sub-regions with no discount at all (Eastern Europe, North Africa) earn 32% margin; Eastern Asia and Southern Asia (≈5% discount) earn 26%. The relationship between average discount and margin is monotonic across all 18 material regions. *(gro_01b)*
* Top 15 countries are 67% of revenue; the US alone is 20%. Fastest growing in 2023: Italy (+77%), UK (+74%), Spain (+45%), France (+43%). China is the only top-15 country that shrank (−6.6%); Nigeria is flat (+2%) and loss-making. *(gro_02, gro_02b)*
* Seasonality is stable: June and Nov–Dec peaks, Jan–Feb troughs. 2023 had a soft summer (July −4.8% YoY, August +3.3%) and then reaccelerated to +29–39% in Q4. *(gro_03)*
* "Customers buying across regions": nobody buys across countries, regions or markets. 5,087 customers (29% of all, 94% of repeat customers) ship to a second **city** within their own country. This looks like a shipping-address artefact of the dataset rather than cross-border behaviour, so no international-expansion conclusion should rest on it. *(gro_04, gro_04b)*

### CRM / Head of Growth — customers

* Profile: gender is split evenly; Professional (30%) and Skilled Manual (25%) dominate. Revenue per customer is flat across every occupation × gender cell ($335–$398), so demographics do not predict value — behaviour does. *(crm_01, crm_01c)*
* Retention *(crm_05, crm_05b)*: lifetime repeat rate falls from 50% (2020 cohort) to 10% (2023 cohort) purely because recent cohorts have had less time; the comparable 12-month repeat rate improved 16.5% → 17.6% → 19.0% for the 2020–2022 cohorts. Only 33% of repeat orders happen within 180 days of the previous one; 43% take more than a year.
* VIP churn risk *(crm_02, crm_02b)*: 871 VIPs = 31.9% of revenue; 368 inactive > 365 days; the list is sorted by lifetime revenue and ready for a win-back campaign. Several top-10 customers are Corporate accounts that have been silent for 400–800 days.
* RFM *(crm_04)*:

  | Segment | Customers | Revenue share | Avg orders | Avg lifetime revenue |
  |---|---:|---:|---:|---:|
  | Champions | 2.8% | 8.9% | 4.5 | $1,202 |
  | Loyal | 7.4% | 16.1% | 3.1 | $809 |
  | Potential loyalist | 10.4% | 14.3% | 2.0 | $514 |
  | New / recent one-timer | 21.6% | 14.0% | 1.0 | $243 |
  | Promising | 17.8% | 15.3% | 1.3 | $321 |
  | **At risk (valuable, lapsed)** | **13.2%** | **25.2%** | 1.4 | $713 |
  | Hibernating | 26.8% | 6.3% | 1.1 | $88 |

* Cross-sell Consumer vs Corporate *(crm_03, crm_03b)*: category mix is the same in both segments (51% / 16% / 14% / 13% / 6%, within ±1 point) — unsurprising given the labels, so the basket view is the one to trust: depth is identical (1.99 products, 50% multi-product). The only difference is quantity per line — Corporate buys 21 units per order vs. 7. Corporate is a volume buyer of the same assortment, not a different assortment.

## Recommendations (prioritised)

| # | Recommendation | Owner | Evidence | Expected effect |
|---|---|---|---|---|
| 1 | **Cap line discounts at 30%; require Finance approval above it.** 30% is break-even; 35%+ has never been profitable at any level. | CMO + Finance | mkt_02b | Lines ≥ 35% lost $296k over 4 years ($111k in 2023 alone for all >20% lines) |
| 2 | **Diagnose the 2023 base-margin drop** (33% → 27.7% on undiscounted lines): unit cost, logistics rate card, product mix. | Head of Finance | mkt_02d, fin_01b | Explains ~5 points of margin, worth ~$110k on 2023 revenue |
| 3 | **Regional discount discipline**: stop promotional discounting in Western Africa, Western Asia, Southeastern Asia; review Turkey, Nigeria, Indonesia individually. | Head of Growth + CMO | gro_01b, gro_02 | Negative gross margin at current discount levels — growth there destroys value until pricing changes |
| 4 | **Replace flat % discounts for Corporate with volume/contract terms.** Corporate is 59% of revenue, receives the same 14% average discount and earns the lowest margin. | Head of Finance | fin_02, mkt_02c | Corporate loss orders cost $188k over 4 years; a 5-point margin gain is ≈ $65k/yr on 2023 revenue |
| 5 | **Win-back the 368 lapsed VIPs** (list in `crm_02b`), then the 2,299 "At risk" RFM customers. | CRM | crm_02, crm_04 | $849k lifetime revenue among lapsed VIPs; "At risk" = 25% of revenue |
| 6 | **Second-purchase programme in the first 90–180 days** (only 33% of repeat orders arrive that fast; 12-month repeat rate is <20%). | CRM | crm_05, crm_05b | Repeat buyers are worth 2.6× one-time buyers |
| 7 | **Basket-building offers instead of SKU bundles** (free shipping / threshold gift at 2+ products). | Merchandising | mer_03b, mer_03 | Moving 10% of single-product orders to two products ≈ +$180k revenue on the 4-year base at current AOVs |
| 8 | **Expansion: lead with Europe** (highest margin, fastest growth, lowest discount); grow Asia Pacific only under recommendation 3. | Head of Growth | gro_01, gro_03b | Europe already earns 31% of profit on 23% of revenue |
| 9 | **Rebuild the product category from product names** before any category strategy: the catalog's labels are statistically independent of the products. | Data / BA | dq_02f | Every category-level metric is noise until this is done |

## Limitations

* `profit` is gross margin after discount; it excludes logistics and operating cost, so "loss-making" here means "negative gross margin" — the true economics are worse, not better.
* Category and subcategory labels in the product table are unrelated to the product names (`dq_02f`), so category-level results are reported for completeness but carry no merchandising signal. Product-level results are unaffected.
* The four-year revenue base is $1.63M/year, not the $2.3M in the brief; percentages are unaffected, absolute "opportunity" figures should be read against the actual base.
* Order dates were shifted by a fixed 8 years; seasonality by month is valid, day-of-week is not.
