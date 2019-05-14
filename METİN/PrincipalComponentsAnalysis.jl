module PrincipalComponentsAnalysis

export PCA, inversePCA, PCAfeaturevariances, PCAwhitening, ZCAwhitening

using StatsBase, Statistics, LinearAlgebra


"""
    PCA(data; typeofSim = :cov, normtype = 0, featurenum = size(data,2)) -> PCAinfo

Conduct a Principal Components Analysis on some N*k matrix 'data' where N is the number of observations and k is the number of dimensions.

# Arguments
    - 'data': The original data.
    - 'typeofSim::Symbol = :cov': The type of similarity measure to be used between dimensions of observations.
    The only two possible inputs are: ':cov' and ':cor', standing for covariance and correlation respectively.
    - 'normtype = 0': The type of normalization procedure to be used on the original data.
    The only three possible inputs are: '0', '1' and '2', standing for no normalization,
    mean normalization and mean and variance normalization respectively.
    - 'featurenum = size(data,2)': The number of principal component dimensions to be used.
    Default is equal to the dimensions of the original data.
    - 'variancetobekept = 1': Amount of variance to be kept of the original data after PCA is performed.
    Serves the same purpose with 'featurenum' argument by enforcing a number of dimensions to be kept st
    at least 'variancetobekept' amount of the variance is kept when PCA is conducted on the data.

PCAinfo is a vector of matrices where PCAinfo[1] is the Compressed Data Matrix.

PCAinfo[2] is the Principal Components Matrix.

and PCAinfo[3] and PCAinfo[4] are the corresponding mean and standard deviation matrices given that normalization option is exercised.

See also: [inversePCA], [PCAfeaturevariances]
"""
function PCA(data; typeofSim = :cov, normtype = 0, featurenum = size(data,2), variancetobekept = 1)
    N = normalization(data, normtype = normtype)
    Components = PrincipalComponentsExtractor(N.data; typeofSim = typeofSim)
    eigenval = Components.eigenval
    eigenvec = Components.eigenvec
    if variancetobekept < 1
        totalvar = sum(eigenval)
        featurenum = sum(cumsum(eigenval) / totalvar .< variancetobekept) + 1
    end
    if featurenum != size(data,2)
        eigenval = eigenval[1:featurenum]
        eigenvec = eigenvec[:,1:featurenum]
    end
    transformed = eigenvec' * N.data'
    if normtype == 0
        return [Array(transpose(transformed)), Array(transpose(eigenvec))]
    elseif normtype == 1
        return [Array(transpose(transformed)), Array(transpose(eigenvec)), Array(transpose(N.mean))]
    elseif normtype == 2
        return [Array(transpose(transformed)), Array(transpose(eigenvec)), Array(transpose(N.mean)), Array(transpose(N.stddev))]
    end
end

"""
    PCAfeaturevariances(data; typeofSim = :cov, normalization = 0) -> percentVarianceMaintained

Compute the percentage of variance maintained of the data for the number of principal components maintained.

# Arguments
    - 'data': The original data.
    - 'typeofSim::Symbol = :cov': The type of similarity measure to be used between dimensions of observations.
    The only two possible inputs are: ':cov' and ':cor', standing for covariance and correlation respectively.
    - 'normalization = 0': The type of normalization procedure to be used on the original data.
    The only three possible inputs are: '0', '1' and '2', standing for no normalization,
    mean normalization and mean and variance normalization respectively.

See also: [PCA], [inversePCA]
"""
function PCAfeaturevariances(data; typeofSim = :cov, normtype = 0)
    norm = normalization(data, normtype = normtype)
    Components = PrincipalComponentsExtractor(norm.data; typeofSim = typeofSim)
    variances = Components.eigenval
    totalvar = sum(variances)
    cumsum(variances) / totalvar
end


"""
    PrincipalComponentsExtractor(data; typeofSim = :cov) -> (eigenvec, eigenval)
Extract the 'k' Principal Components and their respective eigenvalues of the data presented in a n * k matrix format.

'typeofSim' argument is either :cov or :cor and computes the features using a covariance or correlation matrix respectively.

Note that the features are in decreasing order with respect to their eigenvalues.
"""
function PrincipalComponentsExtractor(data; typeofSim = :cov)
    if typeofSim == :cov
        F = eigen(cov(data))
    elseif typeofSim == :cor
        F = eigen(cor(data))
    else error("The only allowed types are: ':cor' and ':cov'.")
    end
    values = F.values
    vectors = F.vectors
    order = sortperm(values, rev = true)
    values = values[order]
    vectors = vectors[:, order]
    return Components = (eigenvec = vectors, eigenval = values)
end

"""
    inversePCA(PCAinfo) -> reconstructedData

Calculate the inverse PCA of a matrix.

PCAinfo is a vector of matrices where PCAinfo[1] is the Compressed Data Matrix.

PCAinfo[2] is the Principal Components Matrix.

and PCAinfo[3] and PCAinfo[4] are the corresponding mean and standard deviation matrices given that normalization was performed on the original data.

See also: [PCA]
"""
function inversePCA(PCAinfo)
    compresseddata = PCAinfo[1]
    compressionmatrix = PCAinfo[2]
    length(PCAinfo) >= 3 ? datamean = PCAinfo[3] : datamean = zeros(size(compressionmatrix, 2), 1)
    length(PCAinfo) >= 4 ? datastd = PCAinfo[4] : datastd = ones(size(compressionmatrix, 2), 1)
    recovereddata = (compressionmatrix' * compresseddata') .* datastd .+ datamean
    Array(recovereddata')
end

"""
    normalization(data, normtype) -> (normalizeddata, mean, stddev)
Perform standard mean and stddev normalization on the data. Return a tuple containing 'normalizeddata', 'mean' and 'stddev'.

Note that outputs 'mean' and 'stddev' are only produced if the corresponding normalization type (namely 'normtype') is performed.

 # Arguments
    - 'data': The original data to be normalized. Can be either a single dimensional vector or a two dimensional matrix. For the two dimensional matrix the observations are aligned along the first dimension.
    - 'normtype': The type of normalization to be performed on the data. Only three possible choices are '0', '1' and '2'.  They respectively stand for no normalization, mean normalization and mean and stddev normalization.
"""
function normalization(input; normtype = 0)
    if normtype == 0
        return N = (data = input,)
    elseif normtype == 1
        inputmean = mean(input, dims = 1)
        output = input .- inputmean
        return N = (data = output, mean = inputmean)
    elseif normtype == 2
        inputmean = mean(input, dims = 1)
        inputstd = std(input, dims = 1)
        inputstd = [stdval = stdval != 0 ? stdval : Float64(1) for stdval in inputstd]
        input = input .- inputmean
        output = input ./ inputstd
        return N = (data = output, mean = inputmean, stddev = inputstd)
    else error("normtype must be a member of the following set: {0, 1, 2}")
    end
end


"""
    PCAwhitening(data; typeofSim = :cov, normtype = 0, featurenum = size(data,2), variancetobekept = 1, epsilon = 10^(-5)) -> PCAwhiteninginfo
Conduct a PCA Whitening procedure on some N*k matrix 'data' where N is the number of observations and k is the number of dimensions.

# Arguments
    - 'data': The original data.
    - 'typeofSim::Symbol = :cov': The type of similarity measure to be used between dimensions of observations.
    The only two possible inputs are: ':cov' and ':cor', standing for covariance and correlation respectively.
    - 'normtype = 0': The type of normalization procedure to be used on the original data.
    The only three possible inputs are: '0', '1' and '2', standing for no normalization,
    mean normalization and mean and variance normalization respectively.
    - 'featurenum = size(data,2)': The number of principal component dimensions to be used.
    Default is equal to the dimensions of the original data.
    - 'variancetobekept = 1': Amount of variance to be kept of the original data after PCA is performed.
    Serves the same purpose with 'featurenum' argument by enforcing a number of dimensions to be kept st
    at least 'variancetobekept' amount of the variance is kept when PCA is conducted on the data.

PCAwhiteninginfo is a vector of matrices where PCAwhiteninginfo[1] is the Compressed Data Matrix.

PCAwhiteninginfo[2] is the Principal Components Matrix.

PCAwhiteninginfo[3] is the eigenvalues vector of the Principle Components.

and PCAwhiteninginfo[4] and PCAwhiteninginfo[5] are the corresponding mean and standard deviation matrices given that normalization option is exercised.

See also: [PCA] [ZCAwhitening]

"""
function PCAwhitening(data; typeofSim = :cov, normtype = 0, featurenum = size(data,2), variancetobekept = 1, epsilon = 10^(-5))
    N = normalization(data, normtype = normtype)
    Components = PrincipalComponentsExtractor(N.data; typeofSim = typeofSim)
    eigenval = Components.eigenval
    eigenvec = Components.eigenvec
    if variancetobekept < 1
        totalvar = sum(eigenval)
        featurenum = sum(cumsum(eigenval) / totalvar .< variancetobekept) + 1
    end
    if featurenum != size(data,2)
        eigenval = eigenval[1:featurenum]
        eigenvec = eigenvec[:,1:featurenum]
    end
    transformed = eigenvec' *  N.data'
    lambda = sqrt.(reshape(eigenval, 1, :) .+ epsilon)
    output = transformed ./ lambda'
    if normtype == 0
        return [Array(transpose(output)), Array(transpose(eigenvec)), eigenval]
    elseif normtype == 1
        return [Array(transpose(output)), Array(transpose(eigenvec)), eigenval, Array(transpose(N.mean))]
    elseif normtype == 2
        return [Array(transpose(output)), Array(transpose(eigenvec)), eigenval, Array(transpose(N.mean)), Array(transpose(N.stddev))]
    end
end

"""
    ZCAwhitening(data; typeofSim = :cov, normtype = 0, featurenum = size(data,2), variancetobekept = 1, epsilon = 10^(-5)) -> ZCAwhiteninginfo
Conduct a ZCA Whitening procedure on some N*k matrix 'data' where N is the number of observations and k is the number of dimensions.

    # Arguments
    - 'data': The original data.
    - 'typeofSim::Symbol = :cov': The type of similarity measure to be used between dimensions of observations.
    The only two possible inputs are: ':cov' and ':cor', standing for covariance and correlation respectively.
    - 'normtype = 0': The type of normalization procedure to be used on the original data.
    The only three possible inputs are: '0', '1' and '2', standing for no normalization,
    mean normalization and mean and variance normalization respectively.
    - 'featurenum = size(data,2)': The number of principal component dimensions to be used.
    Default is equal to the dimensions of the original data.
    - 'variancetobekept = 1': Amount of variance to be kept of the original data after PCA is performed.
    Serves the same purpose with 'featurenum' argument by enforcing a number of dimensions to be kept st
    at least 'variancetobekept' amount of the variance is kept when PCA is conducted on the data.

ZCAwhiteninginfo is a vector of matrices where ZCAwhiteninginfo[1] is the Compressed Data Matrix.

ZCAwhiteninginfo[2] is the Principal Components Matrix.

ZCAwhiteninginfo[3] is the eigenvalues vector of the Principle Components.

and ZCAwhiteninginfo[4] and ZCAwhiteninginfo[5] are the corresponding mean and standard deviation matrices given that normalization option is exercised.

See also: [PCA] [PCAwhitening]
"""
function ZCAwhitening(data; typeofSim = :cov, normtype = 0, featurenum = size(data,2), variancetobekept = 1, epsilon = 10^(-5))
    PCAinfo = PCAwhitening(data; typeofSim = typeofSim, normtype = normtype, featurenum = featurenum, variancetobekept = variancetobekept, epsilon = epsilon)
    ZCAinfo = copy(PCAinfo)
    ZCAinfo[1] = Array((ZCAinfo[2]' * ZCAinfo[1]')')
    return ZCAinfo
end

end
