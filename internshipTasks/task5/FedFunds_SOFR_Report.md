# Fed Funds Rate, SOFR & Interest Rate Derivatives (USD & EUR)

**Prepared for:** This Week's Task  
**Date:** 28 September 2025  
**Prepared by:** [Your name]

---

## Executive summary

The transition from unsecured short-term benchmarks (such as the federal funds market) to overnight risk-free rates (SOFR in USD and €STR in EUR) has materially changed pricing, hedging, and margining for interest-rate products. This report provides a concise primer on the key benchmarks; an overview of listed and OTC derivatives used to express rate views in USD and EUR; pricing and settlement methods; margining practices and collateral considerations; risk metrics practitioners use to quantify sensitivity and tail risk; and a forward-looking market outlook with trade ideas for the next 6–12 months.

---

## Contents

1. Why this matters
2. Definitions and benchmarks
3. Key instruments in USD markets
4. Key instruments in EUR markets
5. Futures: quotation and contract economics
6. Pricing methodology: futures and implied forwards
7. Pricing methodology: swaps and OIS discounting
8. Convexity and basis considerations
9. Settlement mechanics
10. Margining and clearing
11. Practical margin details
12. Risk metrics: DV01 / PV01
13. Risk metrics: convexity and non-linearity
14. Risk metrics: VAR and stress testing
15. Market outlook: context (as of 28 Sep 2025)
16. Market outlook: scenarios & trade ideas
17. Illustrative trade: 3M SOFR futures curve steepener
18. Worked example: DV01 calculation & sizing
19. Execution, liquidity & operational considerations
20. Appendix: key formulas and cheat sheet
21. Appendix: suggested next steps
22. References and further reading
23. Contact

---

## 1. Why this matters

Short-term rates determine funding costs, valuation discounting, and the cost of hedging exposures across financial institutions and corporate issuers. The move to overnight risk-free rates (RFRs) has introduced changes in product design, compounding conventions, and basis risk that must be managed.

---

## 2. Definitions and benchmarks

**Federal Funds Rate (FFR)** — the effective overnight unsecured rate at which depository institutions lend reserve balances held at the Federal Reserve to one another. Policy is implemented via the Fed's target range and open market operations.

**SOFR (Secured Overnight Financing Rate)** — a USD overnight rate reflecting collateralized repo backed by U.S. Treasuries; administered by the New York Fed in cooperation with the Alternative Reference Rates Committee (ARRC).

**€STR (Euro Short-Term Rate)** — the euro-area overnight rate used as the euro risk-free benchmark, administered by the ECB/Eurosystem.

**Euribor** — a term unsecured interbank rate in EUR markets that remains widely used for floating-rate products but is complemented by €STR-based instruments.

Notes: SOFR is secured (repo) while federal funds and Euribor are unsecured; this generates basis differences that must be considered when hedging across benchmarks.

---

## 3. Key instruments in USD markets

- **3M SOFR futures (CME)** — cash-settled contracts referencing the compounded SOFR over the contract period. Used for hedging and expressing forward-rate views.  
- **1M SOFR futures (CME)** — provide finer granularity for curve construction and hedging.  
- **30‑Day Fed Funds futures (CME)** — used to express policy rate expectations.  
- **SOFR OIS swaps (OTC, cleared)** — the OIS curve is used for discounting collateralized cashflows and for swap valuation.  
- **Options on futures and pay/receive structures** — including calendar spreads and strip options to express convexity and volatility views.

---

## 4. Key instruments in EUR markets

- **3M Euribor futures (Eurex)** — classic futures for Euribor exposures.  
- **3M €STR futures (Eurex)** — newer contracts referencing compounded €STR over the period.  
- **€STR OIS and Euribor OIS swaps** — used to construct discount and forward curves; basis swaps between Euribor and €STR are common.  
- **Options, packs, and strip trades** — employed for volatility, convexity and term-structure views.

---

## 5. Futures: quotation and contract economics

Short-term rate futures commonly use the quotation `Price = 100 − R` where `R` is the annualized rate in percent. Contract sizes and tick values vary by exchange. For example, a typical 3M SOFR future specification may use a contract multiplier of USD 2,500 per index point; a tick of 0.01 index point often equals USD 25. Traders translate tick moves into DV01 to size hedges and measure P&L exposure.

---

## 6. Pricing methodology: futures and implied forwards

A futures price can be converted into an implied forward rate by computing `R = 100 − FuturesPrice`. When a contract references a compounded overnight rate (e.g., compounded SOFR), final cash settlement is calculated from the business‑day compounded realized overnight rates over the reference period. Importantly, futures are margined daily and therefore can exhibit convexity bias relative to swaps, which affects replication strategies and hedge performance under volatility.

---

## 7. Pricing methodology: swaps and OIS discounting

Swap pricing sets the present value (PV) of fixed leg payments equal to the PV of the expected floating leg, using appropriate discount factors. Since the IBOR transition, collateralized cashflows and many cleared products are discounted using the overnight index swap (OIS) curve tied to the relevant RFR (e.g., SOFR for USD). Curve construction typically bootstraps discount and forward curves from money market instruments, futures, FRAs and swap quotes while accounting for compounding conventions and any convexity/basis adjustments.

---

## 8. Convexity and basis considerations

**Convexity** arises because futures are marked-to-market daily (variation margin flows) whereas swaps pay/receive at scheduled times and accumulate. The daily settlement feature means futures-based implied forwards differ from swap-implied forwards when volatility is non-negligible. Practitioners apply convexity adjustments or use spread hedges to reduce mismatch when replicating swap exposures with futures strips. **Basis risk** between secured (SOFR) and unsecured (Fed funds, Euribor) rates is another important operational consideration.

---

## 9. Settlement mechanics

Most modern short-term rate futures are cash-settled. The final settlement price is computed from the realized compounded overnight rate over the contract's reference period per the exchange formula (business-day conventions, day-count basis and lookback/observation rules apply). Exchanges publish last trading day and final settlement procedures in contract specifications — consult those documents before trading.

---

## 10. Margining and clearing

Margining involves **Initial Margin (IM)** and **Variation Margin (VM)**. IM covers potential future exposure based on a CCP's risk model and is recalibrated periodically. VM is exchanged daily to reflect mark-to-market P&L. CCPs typically offer portfolio margining across cleared products (futures and cleared swaps), which reduces aggregate IM when offsetting positions exist. Collateral eligibility, haircuts and concentration limits materially influence funding costs and operational requirements.

---

## 11. Practical margin details

Initial margin levels depend on volatility and CCP methodology. Exchanges publish margin rates and often update them with market stress events. Variation margin settlement in futures provides tight cash settlement mechanics; OTC swap margining depends on clearing status and CSA terms. Understand the CCP default fund contributions and IM floors that may apply to large or concentrated portfolios.

---

## 12. Risk metrics: DV01 / PV01

**DV01 / PV01** is the dollar value change of the instrument per 1 basis‑point parallel move in the underlying rate. For futures, DV01 can be derived from the contract tick mapping: for example, if 0.01 index point = $25, then 1 bp ≈ $25 per contract. DV01 is used for initial hedge sizing, P&L sensitivity analysis and risk budgeting.

---

## 13. Risk metrics: convexity and non-linearity

Convexity (second‑order sensitivity) is crucial when exposures are large or when rate moves are non-linear. Using futures strips to replicate swap exposures leaves residual convexity that will create P&L divergence under large moves. A practical approach is to compute swap PV01 and futures strip PV01 and measure the residual; for large exposures, model second-order effects explicitly in risk systems.

---

## 14. Risk metrics: VAR and stress testing

VaR methodologies (historical or parametric) estimate tail losses over specified horizons and confidence levels. Complement VaR with scenario stress tests: e.g., a parallel +/−100 bps shock across the curve, liquidity shocks (widening bid/ask spreads), and margin-shock scenarios to capture funding strain. Include non-linear instruments (options) in scenario runs with appropriate revaluation engines.

---

## 15. Market outlook: context (as of 28 Sep 2025)

Context: Recent central bank actions and macro data have influenced front‑end rates. Market-implied probabilities (from futures and swap markets) show varying expectations for further easing; the actual path depends on incoming inflation and labor market data. EUR outcomes depend on euro-area inflation persistence, growth dynamics and bank liquidity considerations that affect term rates and basis spreads.

---

## 16. Market outlook: scenarios & trade ideas

- **Baseline (most likely):** Mild easing priced — trade ideas: receive in the front-end using futures, curve flatteners.  
- **Dovish surprise:** Faster cuts than priced — trade ideas: extend duration, long-duration carry trades, steepener via front-end instruments.  
- **Hawkish surprise:** Inflation persistence — trade ideas: pay fixed, shorten duration, use options to hedge volatility.  
- **EUR-specific:** If ECB stays hawkish, favor EUR curve steepeners or basis trades between Euribor and €STR instruments.

---

## 17. Illustrative trade: 3M SOFR futures curve steepener

**View:** Near-term SOFR falls faster than longer-dated forwards.  
**Implementation:** Buy near-month 3M SOFR futures and sell further-out 3M SOFR futures (calendar steepener). Size using DV01 mapping; monitor convexity and roll costs. Consider margin offsets from the CCP if positions are cleared in the same account.

---

## 18. Worked example: DV01 calculation & sizing

**Example:** If a 3M SOFR futures contract has 0.01 index-point = $25, then 1 bp ≈ $25 per contract. If an OTC swap has PV01 = $800, approximate number of contracts required to hedge = 800 / 25 = 32 contracts (rounded). Use convexity adjustments and cross-instrument basis modeling to refine sizing for execution.

---

## 19. Execution, liquidity & operational considerations

Prioritize liquid expiries and work strips or packs to improve execution. Use clearing relationships to capture portfolio margin offsets and reduce IM. Operational readiness requires tracking settlement calendars, fixing conventions, knowing the final settlement formulas, and preparing for margin or market stress events.

---

## 20. Appendix: key formulas and cheat sheet

- **Futures implied rate:** `R_fwd = 100 − FuturesPrice`  
- **Compounded overnight rate (generic):** `R_comp = (∏ (1 + r_i × d_i/360) − 1) × (360 / total_days)` — check exchange-specific rules for precise formula and daycount basis.  
- **Swap fixed rate (concept):** Solve for fixed `K` such that `PV_fixed = PV_float` using discount factors from the OIS curve.

---

## 21. Appendix: suggested next steps

1. Build a backtest comparing front-end SOFR futures vs OIS swaps.  
2. Simulate convexity using historical volatility scenarios (±50–100 bps).  
3. Compute IM under current CCP parameters for proposed books.  
4. Draft trade execution plan with liquidity provider quotes and slippage targets.

---

## 22. References and further reading

Exchange product pages (CME, Eurex), CCP margin documentation, central bank releases and educational notes on convexity and the IBOR transition. Consult exchange contract specs for exact settlement formulas and conventions.

---

## 23. Contact

Prepared by: [Your name]  
Email: you@company.com

---
