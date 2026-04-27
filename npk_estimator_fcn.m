%% =========================================================================
%  MATLAB Function Block: NPK_Estimator
%  File: npk_estimator_fcn.m
%
%  PURPOSE:
%    Estimate composite NPK availability score (0-100) from filtered
%    pH, moisture, temperature, and humidity readings.
%
%  INPUTS:
%    ph_f    - Filtered pH (4.5 to 8.5)
%    moist_f - Filtered soil moisture % (10 to 90)
%    temp_f  - Filtered temperature C (10 to 40)
%    hum_f   - Filtered humidity % (30 to 95)
%
%  OUTPUT:
%    npk_est - Composite NPK estimate (0 to 100)
%
%  PASTE THIS CODE INTO THE MATLAB FUNCTION BLOCK EDITOR IN SIMULINK
% =========================================================================

function npk_est = npk_estimator(ph_f, moist_f, temp_f, hum_f)
%#codegen

% NPK estimation heuristic:
% - pH near 6.5 generally improves nutrient availability
% - moderate moisture supports uptake
% - temperature/humidity adjust estimated N/P/K availability
ph_penalty = max(0, 1 - abs(ph_f - 6.5) / 2.0);           % 0-1
moist_factor = min(1, max(0, (moist_f - 20) / 50));       % 0-1
temp_factor = max(0, 1 - abs(temp_f - 24) / 16);          % 0-1
hum_factor = min(1, max(0, (hum_f - 35) / 45));           % 0-1

npk_base = 100 * (0.6 * ph_penalty + 0.4 * moist_factor);

n_est = npk_base * (0.85 + 0.25 * moist_factor - 0.10 * (1 - hum_factor));
p_est = npk_base * (0.85 + 0.30 * ph_penalty  - 0.15 * (1 - temp_factor));
k_est = npk_base * (0.90 + 0.20 * ph_penalty  + 0.05 * hum_factor);

n_est = min(100, max(0, n_est));
p_est = min(100, max(0, p_est));
k_est = min(100, max(0, k_est));

npk_est = (n_est + p_est + k_est) / 3;
npk_est = min(100, max(0, npk_est));

end
