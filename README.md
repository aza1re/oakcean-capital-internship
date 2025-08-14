# Oakcean Capital Internship

Welcome to my showcase of my internship at Oakcean Capital. This repository documents my work and solutions for the internship, focusing on quantitative trading, data engineering, and algorithmic strategy development.

## Overview

During my internship, I worked on building a data pipeline and developing trading strategies for the China A-share market, specifically using data from the Shanghai Stock Exchange (SSE). The work is divided into two main tasks:

---

## Task 1: Pairs Trading & Statistical Arbitrage – Medium Frequency Trading

**Objective:**  
Explore the possibility of utilizing statistical arbitrage strategies in the China stock market.

**Key Steps:**
- **Data Collection:**  
  - Downloaded historical daily data for selected SSE stocks using Yahoo Finance.
  - Stored the data in a MongoDB database for efficient querying and analysis.
- **API Development:**  
  - Built a REST API using FastAPI to expose time series data for any ticker and date range.
- **Analysis:**  
  - Implemented correlation analysis and clustering to group stocks with similar price movements.
  - Developed a mean-reversion strategy and performed backtesting to evaluate performance.

**Relevant Files:**
- [`tasks/task1/main.py`](tasks/task1/main.py): Main pipeline, data ingestion, API, and strategy execution.
- [`tasks/task1/correlation.py`](tasks/task1/correlation.py): Stock clustering and correlation analysis.
- [`tasks/task1/mrs.py`](tasks/task1/mrs.py): Mean reversion strategy implementation.

I plan to further backtest my strategies and deploy it on QuantConnect, stay tuned for my Quant journey!
