%% =========================================================================
%  Smart AgroSense: Standalone Simulation & Validation Script
%  File: run_agrosense_simulation.m
%
%  PURPOSE:
%    Run and validate the full AgroSense logic in pure MATLAB without
%    requiring Simulink GUI. Produces plots equivalent to Scope blocks.
%    Use this to verify logic before running the full Simulink model.
%
%  USAGE:
%    >> run_agrosense_simulation
%
% =========================================================================

clear; clc; close all;

disp('=================================================================');
disp('  Smart AgroSense Simulation - Nepal Crop Recommendation System');
disp('=================================================================');

%% --- Simulation Parameters ---
dt = 0.1;           % Sample time (seconds)
T  = 100;           % Total simulation time
t  = 0:dt:T;
N  = length(t);

% Sensor generation mode:
%   'random'    - fully random unknown soil/environment values
%   'realistic' - smooth seasonal-like variation with noise
sensor_mode = 'random';

% Set fixed seed for reproducibility in random mode.
% Change to rng('shuffle') for a different run each time.
rng(42);

%% =========================================================================
%  BLOCK 1: SENSOR DATA GENERATION
%  Random unknown field mode OR realistic wave mode
% =========================================================================

switch lower(sensor_mode)
    case 'random'
        % Fully random values in physical ranges (unknown soil assumption)
        pH_raw    = 4.5 + (8.5 - 4.5) * rand(1, N);
        moist_raw = 10  + (90  - 10)  * rand(1, N);
        temp_raw  = 10  + (40  - 10)  * rand(1, N);
        hum_raw   = 30  + (95  - 30)  * rand(1, N);

    case 'realistic'
        % Seasonal-like trends with bounded Gaussian perturbations
        pH_raw    = 6.5 + 2.0  * sin(0.05*t)      + 0.2*randn(1,N);
        moist_raw = 50  + 30   * sin(0.03*t+1.2)  + 2.0*randn(1,N);
        temp_raw  = 25  + 12   * sin(0.02*t+0.8)  + 1.0*randn(1,N);
        hum_raw   = 65  + 25   * sin(0.04*t+2.0)  + 3.0*randn(1,N);

    otherwise
        error('Unsupported sensor_mode: %s. Use ''random'' or ''realistic''.', sensor_mode);
end

% Clamp to physical limits
pH_raw   = min(max(pH_raw, 4.5), 8.5);
moist_raw = min(max(moist_raw, 10), 90);
temp_raw  = min(max(temp_raw, 10), 40);
hum_raw   = min(max(hum_raw, 30), 95);

fprintf('Sensor Generation: DONE\n');

%% =========================================================================
%  BLOCK 2: SIGNAL FILTERING
%  Moving average (10-sample window) + IIR low-pass filter
% =========================================================================

% Moving average filter
window = 10;
pH_mavg   = movmean(pH_raw,   window);
moist_mavg = movmean(moist_raw, window);
temp_mavg  = movmean(temp_raw,  window);
hum_mavg   = movmean(hum_raw,   window);

% IIR Low-pass filter: H(z) = 0.2 / (z - 0.8)
% Equivalent: y[n] = 0.8*y[n-1] + 0.2*x[n]
alpha = 0.2;
pH_filt   = filter(alpha, [1, -(1-alpha)], pH_mavg);
moist_filt = filter(alpha, [1, -(1-alpha)], moist_mavg);
temp_filt  = filter(alpha, [1, -(1-alpha)], temp_mavg);
hum_filt   = filter(alpha, [1, -(1-alpha)], hum_mavg);

fprintf('Signal Filtering: DONE\n');

%% =========================================================================
%  BLOCK 3: SOIL CLASSIFICATION
% =========================================================================

ph_class   = classify_pH(pH_filt);
moist_class = classify_moisture(moist_filt);
temp_class  = classify_temperature(temp_filt);
hum_class   = classify_humidity(hum_filt);

fprintf('Soil Classification: DONE\n');

%% =========================================================================
%  BLOCK 4: NPK ESTIMATION
%  Estimates N, P, K component data and composite NPK score
%  (replaces expensive NPK sensor with AI inference)
% =========================================================================

% NPK estimation heuristic:
%   - Optimal pH range (6.0-7.0) correlates with available N,P,K
%   - Moderate moisture improves nutrient uptake
%   - pH penalty: deviation from 6.5 reduces available nutrients
ph_deviation = abs(pH_filt - 6.5);
ph_penalty   = max(0, 1 - ph_deviation ./ 2.0);  % 0-1 scale

moist_factor = min(1, max(0, (moist_filt - 20) ./ 50));  % 0-1 scale
temp_factor  = max(0, 1 - abs(temp_filt - 24) ./ 16);    % 0-1 scale
hum_factor   = min(1, max(0, (hum_filt - 35) ./ 45));    % 0-1 scale

NPK_base = 100 * (0.6 * ph_penalty + 0.4 * moist_factor);

% Estimated macronutrient availability (0-100)
N_est = NPK_base .* (0.85 + 0.25 * moist_factor - 0.10 * (1 - hum_factor));
P_est = NPK_base .* (0.85 + 0.30 * ph_penalty  - 0.15 * (1 - temp_factor));
K_est = NPK_base .* (0.90 + 0.20 * ph_penalty  + 0.05 * hum_factor);

N_est = min(100, max(0, N_est));
P_est = min(100, max(0, P_est));
K_est = min(100, max(0, K_est));

% Composite NPK score used by recommender
NPK_est = (N_est + P_est + K_est) / 3;
NPK_est = min(100, max(0, NPK_est));

fprintf('NPK Estimation: DONE\n');

%% =========================================================================
%  BLOCK 5: AI CROP RECOMMENDATION
% =========================================================================

% Crop requirement table [pH_min, pH_optLo, pH_optHi, pH_max,
%                          moist_min, moist_optLo, moist_optHi, moist_max,
%                          temp_min, temp_optLo, temp_optHi, temp_max,
%                          hum_min, hum_optLo, hum_optHi, hum_max,
%                          npk_min]
cropTable = [
  5.0, 6.0, 7.0, 8.0,  50, 65, 80, 90,  20, 25, 35, 40,  60, 70, 90, 95, 60;  % Rice
  5.5, 6.0, 7.0, 8.0,  30, 45, 65, 80,  18, 22, 32, 38,  40, 55, 80, 90, 55;  % Maize
  5.5, 6.0, 7.0, 8.0,  25, 40, 60, 70,  10, 15, 22, 28,  35, 50, 70, 85, 50;  % Wheat
  5.5, 6.0, 7.0, 7.5,  20, 35, 55, 70,  10, 15, 25, 30,  30, 45, 65, 80, 40;  % Mustard
  4.8, 5.5, 6.5, 7.0,  40, 55, 70, 80,  14, 18, 24, 28,  45, 60, 80, 90, 65;  % Potato
  5.5, 6.0, 6.8, 7.5,  35, 50, 65, 75,  18, 22, 28, 35,  40, 55, 75, 85, 60;  % Tomato
  5.8, 6.5, 7.5, 8.0,  20, 35, 50, 65,  12, 18, 25, 30,  30, 45, 65, 75, 35;  % Lentil
  5.0, 5.5, 6.5, 7.5,  20, 35, 55, 70,  20, 25, 35, 40,  30, 45, 70, 85, 30;  % Millet
];

cropNames = {'Rice','Maize','Wheat','Mustard','Potato','Tomato','Lentil','Millet'};
nCrops = 8;

% Calculate scores for each timestep
scores_ts     = zeros(N, nCrops);
top_crop_ts   = zeros(1, N);
top_score_ts  = zeros(1, N);
advice_code_ts = zeros(1, N);

for k = 1:N
    s = zeros(1, nCrops);
    for c = 1:nCrops
        req = cropTable(c,:);
        s(c) = 0.30 * trapezoid(pH_filt(k),    req(1),  req(2),  req(3),  req(4))  + ...
               0.25 * trapezoid(moist_filt(k),  req(5),  req(6),  req(7),  req(8))  + ...
               0.25 * trapezoid(temp_filt(k),   req(9),  req(10), req(11), req(12)) + ...
               0.10 * trapezoid(hum_filt(k),    req(13), req(14), req(15), req(16)) + ...
               0.10 * npk_score(NPK_est(k), req(17));
    end
    scores_ts(k,:) = s;
    [top_score_ts(k), top_crop_ts(k)] = max(s);
    advice_code_ts(k) = get_advice(pH_filt(k), moist_filt(k), NPK_est(k));
end

fprintf('AI Crop Recommendation: DONE\n');

%% =========================================================================
%  DISPLAY: Final timestep results (farmer-facing output)
% =========================================================================

fprintf('\n');
disp('=================================================================');
disp('  CURRENT FIELD CONDITIONS (last reading)');
disp('=================================================================');
fprintf('  Soil pH:          %.2f  (%s)\n', pH_filt(end),   ph_label(ph_class(end)));
fprintf('  Soil Moisture:    %.1f%% (%s)\n', moist_filt(end), moisture_label(moist_class(end)));
fprintf('  Temperature:      %.1f°C (%s)\n', temp_filt(end),  temp_label(temp_class(end)));
fprintf('  Air Humidity:     %.1f%% (%s)\n', hum_filt(end),   humidity_label(hum_class(end)));
fprintf('  NPK Estimate:     %.1f/100\n', NPK_est(end));
fprintf('  Nitrogen (N):     %.1f/100 (%s)\n', N_est(end), fertility_label(N_est(end)));
fprintf('  Phosphorus (P):   %.1f/100 (%s)\n', P_est(end), fertility_label(P_est(end)));
fprintf('  Potassium (K):    %.1f/100 (%s)\n', K_est(end), fertility_label(K_est(end)));
fprintf('\n');

bestCrop = cropNames{top_crop_ts(end)};
bestScore = top_score_ts(end) * 100;
adviceStr = advice_message(advice_code_ts(end), bestCrop, pH_filt(end), moist_filt(end));

disp('=================================================================');
disp('  AI RECOMMENDATION');
disp('=================================================================');
fprintf('  Recommended Crop: %s\n', bestCrop);
fprintf('  Suitability Score: %.0f / 100\n', bestScore);
fprintf('\n  Advice: %s\n', adviceStr);
disp('=================================================================');

fprintf('\nAll Crop Scores at final timestep:\n');
for c = 1:nCrops
    bar_len = round(scores_ts(end,c));
    fprintf('  %-8s [%-50s] %.0f%%\n', cropNames{c}, repmat('|',1,round(bar_len/2)), scores_ts(end,c)*100);
end

%% =========================================================================
%  COST COMPARISON
% =========================================================================
cost_expensive = 350;   % USD: Full sensor suite with NPK sensor
cost_lowcost   = 40;    % USD: pH + Moisture + Temp + Humidity + MCU
cost_reduction = 100 * (cost_expensive - cost_lowcost) / cost_expensive;

fprintf('\n');
disp('=================================================================');
disp('  COST COMPARISON');
disp('=================================================================');
fprintf('  Traditional system cost: $%d (with NPK sensor)\n', cost_expensive);
fprintf('  AgroSense system cost:   $%d (AI-estimated NPK)\n', cost_lowcost);
fprintf('  Cost Reduction:          %.1f%%\n', cost_reduction);
fprintf('  Savings per unit:        $%d\n', cost_expensive - cost_lowcost);
disp('=================================================================');

%% =========================================================================
%  PLOTS: Equivalent to Simulink Scope blocks
% =========================================================================

figure('Name','AgroSense - Raw vs Filtered Sensor Signals', ...
       'Position', [50, 50, 1200, 800], 'Color','white');

subplotLabels = {'pH (4.5-8.5)', 'Moisture % (10-90)', ...
                 'Temperature °C (10-40)', 'Humidity % (30-95)'};
rawData    = {pH_raw,    moist_raw,  temp_raw,   hum_raw};
filtData   = {pH_filt,   moist_filt, temp_filt,  hum_filt};
yLimits    = {[4,9], [5,95], [8,45], [25,100]};
colors = {[0.2 0.5 0.9], [0.1 0.7 0.3], [0.9 0.3 0.2], [0.7 0.2 0.8]};

for i = 1:4
    subplot(4,1,i);
    plot(t, rawData{i},  'Color', [0.7 0.7 0.7], 'LineWidth', 0.8); hold on;
    plot(t, filtData{i}, 'Color', colors{i},      'LineWidth', 2.0);
    xlabel('Time (s)'); ylabel(subplotLabels{i});
    legend('Raw (Noisy)', 'Filtered', 'Location', 'northeast');
    ylim(yLimits{i});
    grid on;
    title(['Sensor: ' subplotLabels{i}]);
end
sgtitle('AgroSense: Raw vs Filtered Sensor Signals');

figure('Name','AgroSense - Crop Suitability Scores', ...
       'Position', [50, 100, 1200, 500], 'Color','white');

subplot(2,1,1);
plot(t, top_score_ts * 100, 'Color', [0.2 0.7 0.3], 'LineWidth', 2);
xlabel('Time (s)'); ylabel('Suitability Score (0-100)');
title('Best Crop Suitability Score Over Time');
ylim([0, 110]); grid on;

subplot(2,1,2);
plot(t, top_crop_ts, 'Color', [0.8 0.4 0.1], 'LineWidth', 2);
xlabel('Time (s)'); ylabel('Crop Index (1-8)');
yticks(1:8); yticklabels(cropNames);
title('Recommended Crop Over Time');
ylim([0.5, 8.5]); grid on;
sgtitle('AgroSense: AI Crop Recommendation Over Time');

figure('Name','AgroSense - Estimated NPK Components', ...
    'Position', [70, 140, 1200, 500], 'Color','white');
plot(t, N_est,   'Color', [0.2 0.6 0.2], 'LineWidth', 2); hold on;
plot(t, P_est,   'Color', [0.85 0.55 0.1], 'LineWidth', 2);
plot(t, K_est,   'Color', [0.25 0.45 0.85], 'LineWidth', 2);
plot(t, NPK_est, 'k--', 'LineWidth', 2);
xlabel('Time (s)'); ylabel('Estimated Fertility (0-100)');
title('Estimated N, P, K and Composite NPK Over Time');
legend('Nitrogen (N)', 'Phosphorus (P)', 'Potassium (K)', 'Composite NPK', ...
    'Location', 'southeast');
ylim([0, 110]);
grid on;

figure('Name','AgroSense - Cost Comparison', ...
       'Position',[100,200,500,400], 'Color','white');
bar_data = [cost_expensive; cost_lowcost];
bar(bar_data, 'FaceColor', 'flat', ...
    'CData', [0.9 0.3 0.3; 0.2 0.7 0.3]);
set(gca, 'XTickLabel', {'Traditional System','AgroSense (AI NPK)'});
ylabel('System Cost (USD)');
title(sprintf('Cost Comparison - %.1f%% Reduction', cost_reduction));
for i = 1:2
    text(i, bar_data(i)+5, sprintf('$%d', bar_data(i)), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
grid on;

disp('Plots generated. Simulation complete!');

%% =========================================================================
%  HELPER FUNCTIONS
% =========================================================================

function score = trapezoid(x, a, b, c, d)
    if x <= a || x >= d
        score = 0;
    elseif x >= b && x <= c
        score = 1;
    elseif x > a && x < b
        score = (x - a) / (b - a);
    else
        score = (d - x) / (d - c);
    end
end

function s = npk_score(npk, npk_min)
    if npk >= npk_min
        s = 1;
    elseif npk >= npk_min * 0.5
        s = (npk - npk_min*0.5) / (npk_min*0.5);
    else
        s = 0;
    end
end

function c = classify_pH(ph)
    c = ones(size(ph));
    c(ph >= 5.5 & ph < 6.5) = 2;
    c(ph >= 6.5 & ph <= 7.5) = 3;
    c(ph > 7.5) = 4;
end

function c = classify_moisture(m)
    c = ones(size(m));
    c(m >= 25 & m <= 60) = 2;
    c(m > 60) = 3;
end

function c = classify_temperature(t)
    c = ones(size(t));
    c(t >= 15 & t <= 32) = 2;
    c(t > 32) = 3;
end

function c = classify_humidity(h)
    c = ones(size(h));
    c(h >= 45 & h <= 70) = 2;
    c(h > 70) = 3;
end

function code = get_advice(ph, moist, npk)
    if ph < 5.5,       code = 1;
    elseif ph > 7.8,   code = 2;
    elseif moist < 25, code = 3;
    elseif moist > 75, code = 4;
    elseif npk < 35,   code = 5;
    else,              code = 6;
    end
end

function s = ph_label(c)
    labels = {'Strongly Acidic','Slightly Acidic','Neutral','Alkaline'};
    s = labels{min(max(c,1),4)};
end

function s = moisture_label(c)
    labels = {'Dry','Moderate','Wet'};
    s = labels{min(max(c,1),3)};
end

function s = temp_label(c)
    labels = {'Too Low','Suitable','Too High'};
    s = labels{min(max(c,1),3)};
end

function s = humidity_label(c)
    labels = {'Low','Moderate','High'};
    s = labels{min(max(c,1),3)};
end

function s = fertility_label(v)
    if v < 35
        s = 'Low';
    elseif v < 65
        s = 'Medium';
    else
        s = 'High';
    end
end

function msg = advice_message(code, crop, ph, moist)
    ph_desc = '';
    if ph < 5.5,       ph_desc = 'strongly acidic';
    elseif ph < 6.5,   ph_desc = 'slightly acidic';
    elseif ph <= 7.5,  ph_desc = 'neutral';
    else,              ph_desc = 'alkaline';
    end

    moist_desc = '';
    if moist < 25,     moist_desc = 'dry';
    elseif moist < 60, moist_desc = 'moderate';
    else,              moist_desc = 'wet';
    end

    base = sprintf('Soil is %s and moisture is %s. %s is recommended. ', ...
                   ph_desc, moist_desc, crop);
    advices = { ...
        'Add agricultural lime (2-3 ton/ha) to raise soil pH.', ...
        'Apply sulfur or organic compost to reduce pH.', ...
        'Irrigate field immediately - soil is too dry.', ...
        'Improve field drainage - excess moisture may cause root rot.', ...
        'Apply balanced NPK fertilizer (10-10-10) before planting.', ...
        'Maintain current farming practices - conditions are optimal.' ...
    };
    msg = [base advices{min(max(code,1),6)}];
end
