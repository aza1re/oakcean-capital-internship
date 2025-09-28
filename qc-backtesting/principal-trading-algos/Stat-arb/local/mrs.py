import pandas as pd

class MeanReversionStrategy:
    def __init__(self, lookback=20, entry_threshold=1.0, exit_threshold=0.2):
        self.lookback = lookback
        self.entry_threshold = entry_threshold
        self.exit_threshold = exit_threshold

    def calculate_zscore(self, series):
        rolling_mean = series.rolling(window=self.lookback).mean()
        rolling_std = series.rolling(window=self.lookback).std()
        zscore = (series - rolling_mean) / rolling_std
        return zscore

    def generate_signals(self, price_series):
        zscore = self.calculate_zscore(price_series)
        signals = pd.Series(0, index=price_series.index)
        signals[zscore > self.entry_threshold] = -1  # Short signal
        signals[zscore < -self.entry_threshold] = 1  # Long signal
        signals[(zscore < self.exit_threshold) & (zscore > -self.exit_threshold)] = 0  # Exit
        return signals

    def backtest(self, price_series):
        signals = self.generate_signals(price_series)
        returns = price_series.pct_change().shift(-1)  # Next day's return
        strategy_returns = signals * returns
        cumulative_returns = (1 + strategy_returns.fillna(0)).cumprod()
        return cumulative_returns, strategy_returns

# Example usage:
# strategy = MeanReversionStrategy(lookback=20, entry_threshold=1.0, exit_threshold=0.2)
# signals = strategy.generate_signals(price_series)
# cumulative_returns, strategy_returns =