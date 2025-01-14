"""
    compute_DRT(frequencies, measurements; <keyword arguments>)

Calculate the Distribution of Relaxation Times using RBF discretization and Tikhonov regularisation.

The essential inputs are a set of frequencies and the impedance measurements conducted at those frequencies.
There are also a number of keyword arguments to fine-tune the calculation. 

## Keyword arguments
- `method::String="im"`: the part of the measurements used to calculate the DRT.
- `rbf_kernel = SqExponentialKernel()`: The RBF used to discretize the DRT.
- `width_coeff::Float64=0.10`: the hyperparameter influencing the shape factor of the RBF.
- `λ::Float64=1e-2`: a hyperparameter tuning the degree of regularisation.
- `peak_strictness::Float64=0.01`: A measure to avoid artifacts in the DRT by removing peaks
            with amplitude less than a given percentage of the highest peak.
 """
function compute_DRT(frequencies, measurements;
                        method="im",
                        width_coeff=0.10,
                        rbf_kernel=SqExponentialKernel(),
                        λ=1e-2,
                        peak_strictness=0.01)
    ϵ = calculate_shape_factor(frequencies, width_coeff, rbf_kernel)

    # Get the real and imaginary parts of the impedance measurements.
    Z_exp_imag = imag(measurements)
    Z_exp_real = real(measurements)

    # Calculate the matrices for the reconstruction of the real and imaginary parts of the impedance spectra.
    Z_drt_imag = construct_Z_imag(frequencies, ϵ, rbf_kernel)
    Z_drt_real = construct_Z_real(frequencies, ϵ, rbf_kernel)

    # Select the appropriate objective function for DRT calculation using the real part of the measurements, the imaginary part or both.
    if method == "re_im"
        obj = x -> joint_objective(Z_drt_imag, -Z_exp_imag, Z_drt_real, Z_exp_real, x, λ)
    elseif method == "im"
        obj = x ->  objective(Z_drt_imag, -Z_exp_imag, x, λ)
    elseif method == "re"
        obj = x ->  objective(Z_drt_real, Z_exp_real, x, λ)
    end

    # Initialize the weight vector θ, with values offset slightly from zero (boundary).
    n = length(frequencies) + 1
    θ = fill(0.05, n)

    # Optimize the weights θ with the restriction θ >= 0 (no negative peaks).
    upper = 1e8ones(n) # Arbitrarily large upper bound.
    lower = zeros(n)
    results = optimize(obj, lower, upper, θ, Fminbox(BFGS()), autodiff=:forward)

    # The first value corresponds to R_inf (unless "im" is used), while the rest are the DRT weights.
    θ_hat = results.minimizer[2:end]

    # Get the frequencies over which the DRT is calculated (higher resolution than input frequencies through interpolation).
    taumax = ceil(f->maximum(log10(1 / f),frequencies)) + 1 
    taumin = floor(f->min(log10(1 / f),frequencies)) - 1 
    #taumax = ceil(maximum(log10.(1 ./ frequencies))) + 1  
    #taumin = floor(minimum(log10.(1 ./ (frequencies)))) .-1
    out_frequencies = [10.0^i for i in range(-taumin, -taumax, 10length(frequencies))]

    # Calculate the DRT over these frequencies, using the estimated weight vector θ_hat.
    drt = drt_interpolation(out_frequencies, frequencies, θ_hat, ϵ, rbf_kernel)

    # Find the indices of the peaks in the DRT profile, with removal of possible artifacts.
    pkindices = get_peak_inds(drt, peak_strictness)

    taus_out = 1 ./ out_frequencies

    relaxation_times = taus_out[pkindices]
    peak_amplitudes = drt[pkindices]

    return relaxation_times, peak_amplitudes, taus_out, drt
end

"""
    drt_interpolation(out_frequencies,frequencies, θ, ϵ, rbf_kernel)

Calculates the DRT (defined on the whole real line), using the weights θ the RBF information, and the frequencies.
"""
function drt_interpolation(out_frequencies, frequencies, θ, ϵ, rbf_kernel)
    out_drt = Vector{Float64}(undef, length(out_frequencies))
    x0 = -log.(frequencies)
    x = -log.(out_frequencies)
    for k in eachindex(out_frequencies)
        out_drt[k] = (transpose(θ) * rbf_kernel.(ϵ.*x[k], ϵ.*x0))[1]
    end
    return out_drt
end

"""
get_peak_inds(drt,strictness)

Find the peaks in the DRT. Possible artifacts are eliminated depending
on the value of the strictness argument.
"""
function get_peak_inds(drt, strictness)
    pkindices = findpeaks1d(drt)[1]
    amplitudes = drt[pkindices]
    max_amplitude = maximum(amplitudes)
    to_remove = amplitudes .≤ strictness*max_amplitude
    return pkindices[.!to_remove]
end