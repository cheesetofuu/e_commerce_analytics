"""
validate_results.py
--------------------------------------------------------------------------
Independent cross-check: recompute the headline numbers with pandas
(no SQL) and compare them with the sheets in results/<domain>.xlsx.
A mismatch stops the script with a non-zero exit code.

Usage:
    python scripts/validate_results.py --data data --results results
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def close(a, b, tol=0.01):
    return abs(float(a) - float(b)) <= tol


def sheet(results_dir: Path, workbook: str, sheet_name: str) -> pd.DataFrame:
    return pd.read_excel(results_dir / f"{workbook}.xlsx", sheet_name=sheet_name)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="data")
    ap.add_argument("--results", default="results")
    args = ap.parse_args()
    d, r = Path(args.data), Path(args.results)

    s = pd.read_csv(d / "e_commerce_ecom_sales.csv", parse_dates=["order_date"])
    reg = pd.read_csv(d / "e_commerce_region.csv")
    cust = pd.read_csv(d / "e_commerce_customer.csv")
    checks = []

    # 1. totals (also equal to the answer published on the dataset page for Q1)
    fin = sheet(r, "01_finance_pnl", "fin_01").iloc[0]
    checks += [("total revenue", close(fin.total_revenue, s.sales.sum())),
               ("total profit", close(fin.total_profit, s.profit.sum())),
               ("orders", fin.orders == s.order_id.nunique()),
               ("customers", fin.customers == s.customer_id.nunique())]

    # 2. revenue by segment
    seg = sheet(r, "01_finance_pnl", "fin_02").set_index("segment")
    pseg = s.groupby("segment").sales.sum()
    checks += [(f"segment revenue {k}", close(seg.loc[k, "revenue"], pseg[k])) for k in pseg.index]

    # 3. loss orders by segment (order grain)
    op = s.groupby(["order_id", "segment"]).profit.sum().reset_index()
    ploss = op[op.profit < 0].groupby("segment").size()
    loss = sheet(r, "01_finance_pnl", "fin_03").set_index("segment")
    checks += [(f"loss orders {k}", loss.loc[k, "loss_orders"] == ploss[k]) for k in ploss.index]

    # 4. discount bands
    band = sheet(r, "02_pricing_discount", "mkt_02")
    cut = pd.cut(s.discount, [-0.01, 0, 0.20, 0.40, 0.60, 1.0])
    pband = s.groupby(cut, observed=False).profit.sum().values
    checks.append(("discount band profit", all(close(a, b) for a, b in zip(band.profit, pband))))

    # 5. margin by market
    sm = s.merge(reg, on="region_code")
    pm = sm.groupby("market").apply(lambda g: 100 * g.profit.sum() / g.sales.sum(), include_groups=False).round(2)
    gm = sheet(r, "04_market_growth", "gro_01").set_index("market")
    checks += [(f"margin {k}", close(gm.loc[k, "gross_margin_pct"], pm[k])) for k in pm.index]

    # 6. top 15 countries
    top = sheet(r, "04_market_growth", "gro_02")
    ptop = sm.groupby("country").sales.sum().sort_values(ascending=False).head(15)
    checks.append(("top 15 countries", list(top.country) == list(ptop.index)))

    # 7. YoY growth, one month
    m = sheet(r, "04_market_growth", "gro_03")
    rev = lambda y, mo: s[(s.order_date.dt.year == y) & (s.order_date.dt.month == mo)].sales.sum()
    yoy = 100 * (rev(2023, 12) - rev(2022, 12)) / rev(2022, 12)
    row = m[(m.order_year == 2023) & (m.order_month == 12)].iloc[0]
    checks.append(("YoY Dec-2023", close(row.yoy_revenue_growth_pct, round(yoy, 2))))

    # 8. VIP at risk
    anchor = s.order_date.max()
    c = s.groupby("customer_id").agg(rev=("sales", "sum"), last=("order_date", "max"))
    vip = c[c.rev >= c.rev.quantile(0.95)]  # ~ top 5 %
    vipsum = sheet(r, "05_customer_crm", "crm_02").iloc[0]
    n_risk = ((anchor - vip["last"]).dt.days > 365).sum()
    checks.append(("VIP count within 1", abs(vipsum.vip_customers - len(vip)) <= 1))
    checks.append(("VIP at risk within 1", abs(vipsum.vip_at_risk_365d - n_risk) <= 1))

    # 9. RFM segments cover every customer exactly once
    rfm = sheet(r, "05_customer_crm", "crm_04")
    checks.append(("RFM customers sum", rfm.customers.sum() == s.customer_id.nunique()))
    scores = sheet(r, "05_customer_crm", "crm_04b")
    checks.append(("RFM scores unique customers", scores.customer_id.is_unique and len(scores) == len(cust)))

    # 10. cohort repeat rate
    first = s.groupby("customer_id").agg(fy=("order_date", "min"), n=("order_id", "nunique"))
    prep = (first.groupby(first.fy.dt.year).n.apply(lambda x: 100 * (x > 1).mean())).round(2)
    coh = sheet(r, "05_customer_crm", "crm_05").set_index("cohort_year")
    checks += [(f"repeat rate {y}", close(coh.loc[y, "lifetime_repeat_rate_pct"], prep[y])) for y in prep.index]

    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"  [{'OK' if ok else 'FAIL'}] {name}")
    print(f"\n{len(checks) - len(failed)}/{len(checks)} checks passed")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
