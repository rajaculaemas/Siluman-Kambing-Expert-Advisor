//+------------------------------------------------------------------+
//| Expert Advisor for XAU/USD Trading                               |
//| Implements:                                                      |
//| - Technical Indicators (Moving Averages, RSI, Bollinger Bands, ADX) |
//| - Risk Management (Daily Loss Limit, Max Open Positions)         |
//| - Trading Hours (Set to UTC+7)                                   |
//| - Trade Logic (Buy, Sell, Stop Loss, Take Profit)                |
//+------------------------------------------------------------------+

// Pengaturan Parameter
extern double Lots = 0.01;               // Ukuran lot per trade (untuk pengaturan default)
extern bool EnableMoneyManagement = true; // Aktifkan Money Management
extern double MaxDailyLossPercent = 30.0;  // Maksimal kerugian harian dalam persen
extern int MaxOpenPositions = 1;         // Maksimal posisi terbuka
extern int StopLoss = 2000;               // Stop Loss dalam pips
extern int TakeProfit = 5000;             // Take Profit dalam pips
extern int MovingAveragePeriod = 50;     // Periode Moving Average
extern int RSI_Period = 14;              // Periode RSI
extern double RSI_Overbought = 70.0;     // Batas Overbought RSI
extern double RSI_Oversold = 30.0;      // Batas Oversold RSI
extern int BollingerBandsPeriod = 20;    // Periode Bollinger Bands
extern double BollingerBandsDeviation = 2.0; // Deviasi Bollinger Bands
extern int ADX_Period = 14;              // Periode ADX
extern int ADX_TrendStrength = 25;       // Ambang batas ADX untuk tren kuat
extern int TradingStartHour = 9;         // Jam mulai trading (UTC+7)
extern int TradingEndHour = 23;          // Jam berakhir trading (UTC+7)

// Variabel Internal
double DailyLossLimit;
double CurrentDailyLoss = 0;
double AccountStartingBalance;
datetime lastTradeTime;

//+------------------------------------------------------------------+
//| Fungsi untuk menghitung ukuran lot berdasarkan saldo             |
//+------------------------------------------------------------------+
double CalculateLotSize() {
    double lotSize = 0.01; // Ukuran lot minimal

    if (EnableMoneyManagement) {
        double accountBalance = AccountBalance();
        if (accountBalance < 200) {
            lotSize = 0.01; // Jika saldo < 200, lot tetap 0.01
        } else {
            lotSize = 0.01 + MathFloor(accountBalance / 200) * 0.01; // Tambah 0.01 setiap kelipatan 200
        }
    } else {
        lotSize = Lots; // Jika MM tidak aktif, gunakan nilai default dari parameter Lots
    }

    return lotSize;
}

//+------------------------------------------------------------------+
//| Fungsi untuk mengukur kerugian harian                            |
//+------------------------------------------------------------------+
double CalculateDailyLoss() {
    double loss = 0;
    for(int i = OrdersHistoryTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) {
            if(OrderType() == OP_BUY || OrderType() == OP_SELL) {
                double profit = OrderProfit() + OrderSwap() + OrderCommission();
                if(profit < 0) loss += MathAbs(profit);
            }
        }
    }
    return loss;
}

//+------------------------------------------------------------------+
//| Fungsi untuk memeriksa apakah waktu trading sudah sesuai         |
//+------------------------------------------------------------------+
bool IsTradingTime() {
    int currentHour = TimeHour(TimeCurrent()) + 7; // Convert to UTC+7
    if(currentHour >= TradingStartHour && currentHour < TradingEndHour) {
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Fungsi untuk membuka posisi trading                              |
//+------------------------------------------------------------------+
void OpenTrade(int direction) {
    if (CurrentDailyLoss >= DailyLossLimit) {
        Print("Max Daily Loss reached, no new trades will be opened today.");
        return;
    }

    // Tentukan arah (Buy = 1, Sell = -1)
    double price = Ask;

    // Tentukan Stop Loss dan Take Profit
    int sl = direction == 1 ? Ask - StopLoss * Point : Bid + StopLoss * Point;
    int tp = direction == 1 ? Ask + TakeProfit * Point : Bid - TakeProfit * Point;

    // Tentukan ukuran lot berdasarkan money management
    double lotSize = CalculateLotSize();

    // Tentukan Stop Loss dan Take Profit dalam unit harga
    int ticket = 0;
    if (direction == 1) {
        ticket = OrderSend(Symbol(), OP_BUY, lotSize, Ask, 0, sl, tp, "Buy Order", 0, 0, Green);
    } else {
        ticket = OrderSend(Symbol(), OP_SELL, lotSize, Bid, 0, sl, tp, "Sell Order", 0, 0, Red);
    }
    if(ticket < 0) {
        Print("Error opening order: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Fungsi untuk menutup posisi terbuka                              |
//+------------------------------------------------------------------+
void ClosePositions() {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == Symbol()) {
                int orderType = OrderType();
                if(orderType == OP_BUY) {
                    // Memeriksa apakah OrderClose berhasil
                    if (!OrderClose(OrderTicket(), OrderLots(), Bid, 0, Red)) {
                        Print("Error closing buy order: ", GetLastError());
                    }
                } else if(orderType == OP_SELL) {
                    // Memeriksa apakah OrderClose berhasil
                    if (!OrderClose(OrderTicket(), OrderLots(), Ask, 0, Green)) {
                        Print("Error closing sell order: ", GetLastError());
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Fungsi untuk memeriksa kondisi trend dengan ADX dan Bollinger    |
//+------------------------------------------------------------------+
bool CheckTrend() {
    // Cek apakah nilai ADX lebih tinggi dari threshold untuk menunjukkan tren kuat
    double adxValue = iADX(Symbol(), 0, ADX_Period, PRICE_CLOSE, 0, 0);  // Menggunakan parameter yang benar

    // Mengambil nilai Upper Band dan Lower Band dari Bollinger Bands
    double upperBand = iBands(Symbol(), 0, BollingerBandsPeriod, BollingerBandsDeviation, 0, PRICE_CLOSE, MODE_UPPER, 0);
    double lowerBand = iBands(Symbol(), 0, BollingerBandsPeriod, BollingerBandsDeviation, 0, PRICE_CLOSE, MODE_LOWER, 0);
    
    // Mendapatkan harga pasar terkini
    double price = Ask;

    // Cek jika ADX menunjukkan tren yang kuat
    if (adxValue > ADX_TrendStrength) {
        if (price > upperBand) {
            return true; // Harga di atas Upper Band, buka posisi Sell
        } else if (price < lowerBand) {
            return true; // Harga di bawah Lower Band, buka posisi Buy
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Fungsi utama EA untuk trading di XAU/USD                         |
//+------------------------------------------------------------------+
void OnTick() {
    // Cek apakah hari ini sudah ada kerugian yang tercatat
    if (DayOfWeek() != TimeDayOfWeek(lastTradeTime)) {
        CurrentDailyLoss = 0;
    }
    lastTradeTime = TimeCurrent();

    // Cek kondisi kerugian harian tercapai
    DailyLossLimit = AccountBalance() * MaxDailyLossPercent / 100;

    // Cek apakah kita sudah melebihi jumlah posisi terbuka
    if (OrdersTotal() >= MaxOpenPositions) {
        return;
    }

    // Cek apakah kita sedang dalam jam trading yang aktif
    if (!IsTradingTime()) {
        return;
    }

    // Cek kondisi ADX dan Bollinger Bands
    if (CheckTrend()) {
        // Jika tren kuat, buka posisi buy atau sell berdasarkan Bollinger Bands
        if (Ask < iBands(Symbol(), 0, BollingerBandsPeriod, BollingerBandsDeviation, 0, PRICE_CLOSE, MODE_LOWER, 0)) {
            OpenTrade(1);  // Buka posisi Buy
        } else if (Ask > iBands(Symbol(), 0, BollingerBandsPeriod, BollingerBandsDeviation, 0, PRICE_CLOSE, MODE_UPPER, 0)) {
            OpenTrade(-1); // Buka posisi Sell
        }
    }

    // Cek kondisi Moving Average dan RSI
    double maCurrent = iMA(Symbol(), 0, MovingAveragePeriod, 0, MODE_SMA, PRICE_CLOSE, 0);
    double maPrevious = iMA(Symbol(), 0, MovingAveragePeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
    double rsi = iRSI(Symbol(), 0, RSI_Period, PRICE_CLOSE, 0);

    if (maCurrent > maPrevious && rsi < RSI_Oversold) {
        OpenTrade(1);  // Buka posisi Buy
    } else if (maCurrent < maPrevious && rsi > RSI_Overbought) {
        OpenTrade(-1); // Buka posisi Sell
    }
}
