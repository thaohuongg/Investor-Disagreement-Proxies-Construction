# Investor-Disagreement-Proxies-Construction
Construct proxies for Investor Disagreement at the market level

The code is to collect & construct: - Unexplained Trading Volume
                                                       - Stock Return Volatility
                                                       - Bid-Ask Spread in Percentage

         Language: SAS
         Data Source: Wharton
         Code Reference: https://gist.github.com/mgao6767/1b5fccc5c457780fcd6a07669ca9db83


1. The time period of output data: 01 April 1980 - 30 March 2022 (10,591 0bs)

2. The sample contains outstanding common stocks traded on NYSE, Nasdaq, AMEX, and The Arca Stock Market(SM) 

3. Estimation Windows for rolling Regression is set to 60 days

4. Minimum observation in regression is 80% of the Estimation Window amount
    Drop if missing values within the estimation period are out of 20% of the Estimation Windows

5. The gap between the ending day of the regression period and the day on which unexplained trading volume is recorded is 3 days. 
    For example: The estimated result from regression for 13Aug2021-05Nov2021 period will be recorded in 9Nov2021. 

6. The Market Return Volatility is calculated as the standard deviation of individual stock returns within a day.

7.   The Market Bid-Ask Spread is calculated as the average of bid-ask spreads in percentage within day.
