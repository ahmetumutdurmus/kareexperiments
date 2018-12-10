# Kare Experiments Repository

This repository holds the experiment log, a to do list, individual experiment documents, relevant input data, results and experiment codes for reproducibility purposes.

Each individual experiment is assigned a 7 character unique id of the format `AAA1234`. The first three characters are letters and correspond to the relevant portfolio generating function. The last 4 characters are numbers and are assigned randomly and differ for varying parameters of the portfolio generating function thus create a unique experiment. 

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

The input, result and code files should generally be accessed from the experiment log and individual experiment docs. Further explanation won't be provided within these folders. Use at your own risk. 

## To Do Lists

Possible ideas regarding new experiments and modifications of the existing experiments may be provided at the bottom of certain docs as a to do list. Once they are conducted they will be check as done. 
