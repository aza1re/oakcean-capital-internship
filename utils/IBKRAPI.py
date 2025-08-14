from ib_insync import *

class IBKRAPI:
    def __init__(self, host='127.0.0.1', port=7497, client_id=1):
        self.ib = IB()
        self.host = host
        self.port = port
        self.client_id = client_id
        self.connected = False

    def connect(self):
        if not self.connected:
            self.ib.connect(self.host, self.port, clientId=self.client_id)
            self.connected = True

    def disconnect(self):
        if self.connected:
            self.ib.disconnect()
            self.connected = False

    def get_account_summary(self):
        self.connect()
        return self.ib.accountSummary()

    def get_positions(self):
        self.connect()
        return self.ib.positions()

    def get_open_orders(self):
        self.connect()
        return self.ib.openOrders()

    def place_order(self, symbol, quantity, action='BUY', order_type='MKT', exchange='SMART'):
        self.connect()
        contract = Stock(symbol, exchange, 'USD')
        if order_type == 'MKT':
            order = MarketOrder(action, quantity)
        elif order_type == 'LMT':
            # For limit orders, you should provide a price argument
            raise ValueError("Limit orders require a price argument.")
        else:
            raise ValueError("Unsupported order type.")
        trade = self.ib.placeOrder(contract, order)
        return trade

    def get_historical_data(self, symbol, end_date_time='', duration_str='1 D', bar_size='1 min', what_to_show='TRADES', exchange='SMART'):
        self.connect()
        contract = Stock(symbol, exchange, 'USD')
        bars = self.ib.reqHistoricalData(
            contract,
            endDateTime=end_date_time,
            durationStr=duration_str,
            barSizeSetting=bar_size,
            whatToShow=what_to_show,
            useRTH=True,
            formatDate=1
        )
        return bars

# Example usage:
# ibkr = IBKRAPI()
# print(ibkr.get_account_summary())
# print(ibkr.get_positions())
# print(ibkr.get_open_orders())
# bars = ibkr.get_historical_data('AAPL')
#