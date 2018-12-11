# The Experiment Log

## Cumulative Ranking Explicit Churn (CRE)

This function takes an array of returns and an array of PE ratios and produces an array of portfolio allocations. 
CRE respectively conducts a PCA and inverse PCA operation on the returns matrix and measures the spread 
between the PCA reconstruction returns and realized market returns. Then it creates two rankings using this 
spreads and the PE ratios and creates a statistic by adding the two rankings according to a weight given as a parameter.

CRE then each day iteratively creates a portfolio allocation collecting the 20 best alternatives available according to this 
statistic while also considering a churn constraint specified by again a parameter.

### Parameters:

```julia
o[:pcatype] = {:cov, :cor}
    Type of similarity used during PCA.
o[:normtype] = {0, 1, 2} 
    Type of normalization procedure used on raw data before PCA. `0` denotes no normalization. 
    `1` denotes subtracting the mean. `2` denotes z-score normalization. 
o[:lambda] = [0,+)
    The constant before PE rankings to enforce the relative weights of PCA spread and PE rankings. 
    Note that the constant before PCA spread rankings is 1. 
o[:churn] = [0,1]
    The daily churn constraint of the portfolio generating function.
o[:retrospectionperiod] = [Month(3), Month(24)]
    The length of retrospection period of return series to be used while doing PCA.
o[:PCAdays] = [1, o[:retrospectionperiod]]
    The number of days to compound when obtaining the spread between PCA reconstruction and market returns.
o[:rankmode] =  {:Collective, :PEranks, :Spreadranks}  
    The ranking statistic to use when optimizing. `:Collective` denotes the statistic obtained by using both PE
    and spread. `:PEranks` and `:Spreadranks` are self explanatory.
o[:addsecurities] = {true, false} 
    The decision whether to add the returns of the nontradable indices to the PCA analysis. If true, the 
    nontradable indices are included in the PCA reconstruction process but are disregarded during trading.
o[:featurenum] = [1, # of eigenvectors in the PCA]
    The number of eigenvectors to be used when conducting the PCA.  
o[:initialstart] = Date(2013, 1, 2)
    The first date of backtesting.
o[:endofperiod] = o[:initialstart]
    The current day holder for portfolio generation function. 
```
## Experiment IDs:

*   [CRE9148](https://github.com/ahmetumutdurmus/kareexperiments/blob/master/docs/src/CRE9148.md)
*   [CRE2948](https://github.com/ahmetumutdurmus/kareexperiments/blob/master/docs/src/CRE2948.md)
