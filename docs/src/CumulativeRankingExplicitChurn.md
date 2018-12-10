# Cumulative Ranking Explicit Churn (CRE9148)

This experiment runs a [cumulative ranking explicit churn function](https://github.com/ahmetumutdurmus/kareexperiments) through time as explained in the relevant documentation. The The relevant varying and constant hyperparameters are as follows:

## Varying Parameters:

o[:pcatype] = :cor #{:cov, cor}
o[:normtype] = 2 #{:nonorm, :meannorm, :zscore, :minmax} Note that if minmax is used using range[-1,1] or [0.1,0.9] is also an option need 2 take care of that.
o[:lambda] = 10 #[0, +)
o[:churn] = 0.1 #[0.05, 0.3]


## Constant Parameters:

o[:retrospectionperiod] = Month(6)
o[:PCAdays] = 4 # {1:o[:retrospectionperiod]}
o[:rankmode] = :Collective # {:Collective, :PEranks, :Spreadranks}
o[:addsecurities] = false #{true, false}
o[:featurenum] = 1 #{1:NumberOfTradeables}
o[:initialstart] = Date(2013, 1, 2)
o[:endofperiod] = o[:initialstart]

## Input Data:

## Results: 

The results of the experiment are presented in the following [link.](https://docs.google.com/spreadsheets/d/1xAcE-vjqwsU26dImUahlMEpNM8fnMKH7oN798a9fkMA/edit?usp=sharing)

## Codes Links:
