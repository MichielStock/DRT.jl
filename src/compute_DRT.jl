function compute_DRT(frequencies, measurements; method="im", width_coeff = 0.10,
    rbf_kernel = SqExponentialKernel() , λ = 1e-2, peak_strictness = 0.01)

    ϵ = calculate_shape_factor(frequencies,width_coeff,rbf_kernel)

    Z_exp_imag = imag(measurements)
    Z_exp_real = real(measurements)
    Z_drt_imag = construct_Z_imag(frequencies, ϵ, rbf_kernel)
    Z_drt_real = construct_Z_real(frequencies, ϵ, rbf_kernel)

    if method == "re_im"
        obj = x -> joint_objective(Z_drt_imag, -Z_exp_imag, Z_drt_real, Z_exp_real, x, λ)
    elseif method == "im"
        obj = x ->  objective(Z_drt_imag, -Z_exp_imag, x, λ)
    elseif method == "re"
        obj = x ->  objective(Z_drt_real, Z_exp_real, x, λ)
    end

    
    n = length(frequencies) + 2
    θ = fill(0.05, n)

    upper = 1e8 .*ones(n) 
    lower = zeros(n)
    results = optimize(obj, lower, upper, θ, Fminbox(BFGS()), autodiff=:forward)

    θ_hat = transpose(hcat(results.minimizer...))[2:length(frequencies)+1,:]

    taumax = ceil(maximum(log10.(1 ./ frequencies))) + 1  
    taumin = floor(minimum(log10.(1 ./ (frequencies)))) .-1
    out_frequencies = [10.0^i for i in LinRange(-taumin, -taumax, 10*length(frequencies))]

    drt = drt_interpolation(out_frequencies, frequencies, θ_hat, ϵ , rbf_kernel)

    pkindices = get_peak_inds(drt,peak_strictness)

    taus_out = 1 ./ out_frequencies

    relaxation_times = taus_out[pkindices]
    peak_amplitudes = drt[pkindices]

    return relaxation_times, peak_amplitudes, taus_out, drt
end


function drt_interpolation(out_frequencies,frequencies, θ, ϵ, rbf_kernel)
    out_drt = Array{Float64}(undef,length(out_frequencies))
    x0 = -log.(frequencies); x = -log.(out_frequencies)
    for k in eachindex(out_frequencies)
        out_drt[k] = (transpose(θ) * rbf_kernel.(ϵ.*x[k],ϵ .*x0))[1]
    end
    return out_drt
end

function get_peak_inds(drt,strictness)
    pkindices = findpeaks1d(drt)[1]
    amplitudes = drt[pkindices]
    max_amplitude = maximum(amplitudes)
    to_remove = amplitudes .<= strictness*max_amplitude
    deleteat!(pkindices, to_remove)
    return pkindices
end