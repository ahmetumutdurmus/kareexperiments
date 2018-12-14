# Kare Experiments Repository

This repository holds the experiment log, a to do list, individual experiment documents, relevant input data, results and experiment codes for reproducibility purposes.

Each individual experiment is assigned a 7 character unique id of the format `AAA1234`. The first three characters are letters and correspond to the relevant portfolio generating function. The last 4 characters are numbers and are assigned randomly and differ for varying parameters of the portfolio generating function, thus creating a unique experiment. 

A portfolio generating function, *f*, is a mapping from input data and hyperparameters to a portfolio allocation. 

## The Experiment Log

The experiment log is the main document to navigate through the experiments conducted during this study and contains an entry for each portfolio generating function. Each entry has the following format:

>**Function Name (Function Code):**
>
>Function description.
>
>**Parameters:**
>
>The hyperparameters of the function are listed with a small description and perhaps the possible values of the hyperparameter. 
>
>**Experiment IDs:**
>
>The experiment IDs with relative links.
>
>**Input Data:**
>
>A description and link to the input data.

You can access the experiment log from this [link.](https://github.com/ahmetumutdurmus/kareexperiments/blob/master/docs/src/The%20Experiment%20Log.md)
## Individual Experiment Documents

An individual experiment is a series of portfolio generating function runs for different hyperparameters. 

An individual experiment document contains the experiment description, the parameter values to be tweaked and corresponding ranges, the parameter values to be kept constant during the experiment and the relevant links to the source codes, input data and results along with their descriptions. Each document has the following format:

>**Function Name (Experiment ID):**
>
>Experiment description.
>
>**Varying Parameters:**
>
>The list of hyperparameters that are tweaked during the experiment and the corresponding ranges. Possibly along with a simple description of each hyperparameter.
>
>**Constant Parameters:**
>
>The list of hyperparameters that are kept constant during the experiment and their corresponding values. Also possibly along with a simple description of each hyperparameter.
>
>**Code Links:**
>
>Link to executable, ready to go code links for replicating the experiments if need be.
>
>**Input Data:**
>
>A description and link to the input data.
>
>**Results:**
>
>A description and link to the experiment results.

## Input Data, Results and Codes

The input, result and code files should generally be accessed from the experiment log and individual experiment docs. Further explanation won't be provided within the code files, they should generally be accessed via the hiearchical protocol described here.

## To Do Lists

Possible ideas regarding new experiments and modifications of the existing experiments may be provided at the bottom of certain docs as a to do list. Once they are conducted they will be checked as done. 

Below is the main to do list:

- [x] See how long it takes for the effect of churnless initialization to converge for CRE. Compare the portfolio allocations for today initialized 1 year ago vs 5 year ago. // It takes about 15 work days for the initialization effect to lose its effect.
- [x] Measure the effect of PCA reconstruction by conducting CRE with no PCA reconstruction (equivalently 0 eigenvectors). // PCA does seem to have forecasting powers as the experiment suggests.
- [x] See whether enhancing the PCA effect introduces any improvement. Divide both real return and PCA reconstruction vectors by their respective norms. // Not so much, see the relevant experiment for details: [CRE7743](https://github.com/ahmetumutdurmus/kareexperiments/blob/master/docs/src/CRE7743.md)
- [x] Check whether increasing the number eigenvectors improves the results. // Does indeed so given that z-score transformation is performed on the data first. See: [CRE7743](https://github.com/ahmetumutdurmus/kareexperiments/blob/master/docs/src/CRE7743.md)
- [ ] Do a backtesting grid search for the period out of the sample. See if the shape of the return hyperplane is preserved. If so, this suggests that the best hyperparameter structure is not arbitrary, but preserves some actual info about the data generating process.
- [ ] Adding some nonlinearity to decision statistic construction process. Spreadrank^a + lambda * PErank^b for example or log(Spreadrank).
- [ ] Adding some measure of momentum in the process. Tweaking its hyperparameters and such. 
- [x] Implement paper trading for best strategy so far. 
- [ ] Checking if the strategy works on different sets of stocks for different periods of time.
- [ ] An all out experiment summary doc.
- [ ] Changing the experiment naming convention to `AAADDMMYY`. 
- [ ] Initialize CRE allocations from zero and 1 year ago.
- [ ] Write the generic dailyCREfunction.
