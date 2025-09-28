# Simple SVD via Power Method — Pricing Library Development

What is SVD?
- SVD factors any real m×n matrix A as A = U Σ V^T.
  - U: left singular vectors (m)
  - V: right singular vectors (n)
  - Σ: singular values (scales)

What this implementation does
- Computes the dominant singular triplet (σ1, u1, v1) with the power method (alternating Av / A^T u).
- In finance this finds the strongest common mode in a matrix (e.g., a dominant factor across assets).

Quick reminders for quant use
- Work with returns (not prices). Demean each asset time series before SVD (PCA = SVD on demeaned returns).
- The top singular vector approximates the main common factor; singular value indicates its strength.

Examples of this implementation in Finance

1) Extract the top market factor (single-factor PCA)
- Build R: matrix of shape (n_assets × T_days) of daily returns.
- Demean each row (asset): R_demeaned = R - R.mean(axis=1, keepdims=True).
- Top right singular vector v (length T) shows the time series of the dominant mode; left u (length n) gives asset loadings.

Python example (compute top factor and exposures)
```python
import numpy as np
# R: n x T returns matrix
R = np.random.randn(50, 252) * 0.02  # example synthetic returns
R -= R.mean(axis=1, keepdims=True)   # demean per asset

# numpy SVD for reference
U, S, VT = np.linalg.svd(R, full_matrices=False)
sigma1 = S[0]
u1 = U[:,0]        # asset exposures to factor
v1 = VT.T[:,0]     # factor time series (length T)

# normalize factor time series
v1 /= np.linalg.norm(v1)
print("Top sigma:", sigma1)
```

2) Low-rank denoising for covariance estimation
- Keep k top singular values/vectors to build low-rank approximation R_k = U_k Σ_k V_k^T.
- Use R_k to compute a cleaner covariance for portfolio optimization (reduces noise).

Python example (rank-1 approximation)
```python
# rank-1 approximation
R1 = sigma1 * np.outer(u1, v1)
# cleaner covariance (asset x asset)
cov_clean = np.cov(R1)
```

3) Pair/group selection & mean-reversion signal (practical trading use)
- Use top factor to remove common mode: residuals = returns - (u1 @ u1.T) @ returns  (project out first factor).
- For one asset pair, compute spread = w1 * r1 - w2 * r2 where weights from u1 or simple equal weights.
- Create signal: z = (spread - spread.mean()) / spread.std(); enter short/long when |z| > threshold, exit at 0.

Python example (simple residual mean-reversion)
```python
# project returns onto top factor and remove it
factor_exposures = u1.reshape(-1,1)   # n x 1
factor_ts = v1.reshape(1,-1)          # 1 x T
R_proj = factor_exposures @ (factor_ts)  # n x T rank-1 reconstruction
residuals = R - R_proj

# pick asset i and j, create spread and z-score
i, j = 0, 1
spread = residuals[i] - residuals[j]
z = (spread - spread.mean()) / spread.std()
# simple trading rule: long when z < -1, short when z > 1
```

4) Backtest outline (simple)
- Construct entry/exit rules from z-scores on residual spread.
- Size positions to be dollar-neutral (e.g., weights w_i = 1, w_j = -1 * (price_i * vol_i)/(price_j * vol_j) to balance risk).
- Compute P&L per day, cumulate, measure Sharpe and max drawdown.

5) When to use the power method vs full SVD
- Power method: efficient when you only need the top 1 (or few via block power) factors on very large matrices or streaming data.
- Full SVD / randomized SVD / ARPACK: use when you need many components or better numerical stability.

Beginner tips
- Always demean returns before SVD for factor interpretation.
- Verify the power method result against numpy.linalg.svd on small data to ensure correctness.
- Monitor convergence (spectral gap σ1/σ2). Small gap → slower convergence; consider block power or randomized methods.

References and next steps
- Golub & Van Loan (numerical linear algebra)
- Practice: run power-method C++ example on a returns matrix exported from Python; compare factors and P&L for a toy mean-reversion strategy.
