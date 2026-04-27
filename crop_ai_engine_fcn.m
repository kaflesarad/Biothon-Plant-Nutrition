%% =========================================================================
%  MATLAB Function Block: Crop_AI_Engine
%  File: crop_ai_engine_fcn.m
%
%  PURPOSE:
%    Rule-based AI engine that calculates suitability scores for 8 Nepal
%    crops based on filtered soil and environment sensor readings.
%    Selects the top crop and provides a soil improvement advice code.
%
%  CROPS SUPPORTED (index mapping):
%    1 = Rice      | 2 = Maize    | 3 = Wheat
%    4 = Mustard   | 5 = Potato   | 6 = Tomato
%    7 = Lentil    | 8 = Millet
%
%  INPUTS:
%    ph_f    - Filtered pH (4.5 - 8.5)
%    moist_f - Filtered moisture % (10 - 90)
%    temp_f  - Filtered temperature °C (10 - 40)
%    hum_f   - Filtered humidity % (30 - 95)
%    npk_est - Estimated NPK composite score (0-100)
%
%  OUTPUTS:
%    top_score   - Suitability score of best crop (0-100)
%    crop_index  - Index of best crop (1-8, see above)
%    advice_code - Soil improvement advice code (1-6, see legend below)
%
%  ADVICE CODE LEGEND:
%    1 = Add lime to raise pH
%    2 = Add sulfur/organic matter to lower pH
%    3 = Irrigate - soil too dry
%    4 = Improve drainage - soil too wet
%    5 = Add NPK fertilizer - low fertility
%    6 = Soil conditions are good - maintain practices
%
%  PASTE THIS CODE INTO THE MATLAB FUNCTION BLOCK EDITOR IN SIMULINK
% =========================================================================

function [top_score, crop_index, advice_code] = ...
    crop_ai_engine(ph_f, moist_f, temp_f, hum_f, npk_est)

%% -----------------------------------------------------------------------
%  CROP REQUIREMENT TABLE
%  Each row: [pH_min, pH_opt_lo, pH_opt_hi, pH_max,
%             moist_min, moist_opt_lo, moist_opt_hi, moist_max,
%             temp_min, temp_opt_lo, temp_opt_hi, temp_max,
%             hum_min, hum_opt_lo, hum_opt_hi, hum_max,
%             npk_min]
% -----------------------------------------------------------------------

% Crop: Rice
rice     = [5.0, 6.0, 7.0, 8.0,  50, 65, 80, 90,  20, 25, 35, 40,  60, 70, 90, 95,  60];
% Crop: Maize
maize    = [5.5, 6.0, 7.0, 8.0,  30, 45, 65, 80,  18, 22, 32, 38,  40, 55, 80, 90,  55];
% Crop: Wheat
wheat    = [5.5, 6.0, 7.0, 8.0,  25, 40, 60, 70,  10, 15, 22, 28,  35, 50, 70, 85,  50];
% Crop: Mustard
mustard  = [5.5, 6.0, 7.0, 7.5,  20, 35, 55, 70,  10, 15, 25, 30,  30, 45, 65, 80,  40];
% Crop: Potato
potato   = [4.8, 5.5, 6.5, 7.0,  40, 55, 70, 80,  14, 18, 24, 28,  45, 60, 80, 90,  65];
% Crop: Tomato
tomato   = [5.5, 6.0, 6.8, 7.5,  35, 50, 65, 75,  18, 22, 28, 35,  40, 55, 75, 85,  60];
% Crop: Lentil
lentil   = [5.8, 6.5, 7.5, 8.0,  20, 35, 50, 65,  12, 18, 25, 30,  30, 45, 65, 75,  35];
% Crop: Millet
millet   = [5.0, 5.5, 6.5, 7.5,  20, 35, 55, 70,  20, 25, 35, 40,  30, 45, 70, 85,  30];

% Stack into matrix [8 x 17]
cropTable = [rice; maize; wheat; mustard; potato; tomato; lentil; millet];
nCrops = 8;

%% -----------------------------------------------------------------------
%  SUITABILITY SCORE CALCULATION
%  For each parameter, score = 0-100 based on trapezoidal membership:
%    Score = 100 if value in [opt_lo, opt_hi]
%    Score = 0   if value < min or value > max
%    Linearly interpolated in between
% -----------------------------------------------------------------------

scores = zeros(1, nCrops);

for c = 1:nCrops
    req = cropTable(c, :);
    
    % pH score
    ph_score = trapezoid_score(ph_f, req(1), req(2), req(3), req(4));
    
    % Moisture score
    m_score = trapezoid_score(moist_f, req(5), req(6), req(7), req(8));
    
    % Temperature score
    t_score = trapezoid_score(temp_f, req(9), req(10), req(11), req(12));
    
    % Humidity score
    h_score = trapezoid_score(hum_f, req(13), req(14), req(15), req(16));
    
    % NPK score (simple threshold)
    if npk_est >= req(17)
        npk_score = 100;
    elseif npk_est >= req(17) * 0.5
        npk_score = 100 * (npk_est - req(17)*0.5) / (req(17)*0.5);
    else
        npk_score = 0;
    end
    
    % Weighted composite score
    % pH and temperature are critical -> higher weight
    scores(c) = 0.30 * ph_score + ...
                0.25 * m_score  + ...
                0.25 * t_score  + ...
                0.10 * h_score  + ...
                0.10 * npk_score;
end

%% -----------------------------------------------------------------------
%  SELECT BEST CROP
% -----------------------------------------------------------------------
[top_score, crop_index] = max(scores);
top_score = round(top_score);   % Round to integer for display

%% -----------------------------------------------------------------------
%  GENERATE ADVICE CODE
% -----------------------------------------------------------------------
if ph_f < 5.5
    advice_code = 1;    % Add lime to raise pH
elseif ph_f > 7.8
    advice_code = 2;    % Add sulfur/organic matter to lower pH
elseif moist_f < 25
    advice_code = 3;    % Irrigate
elseif moist_f > 75
    advice_code = 4;    % Improve drainage
elseif npk_est < 35
    advice_code = 5;    % Add NPK fertilizer
else
    advice_code = 6;    % Soil conditions are good
end

end

%% -----------------------------------------------------------------------
%  HELPER: Trapezoidal Membership Function
%  Returns score 0-100
%    0   if x < a (below minimum)
%    0-100 ramping up from a to b
%    100  if b <= x <= c (optimal range)
%    100-0 ramping down from c to d
%    0   if x > d (above maximum)
% -----------------------------------------------------------------------
function score = trapezoid_score(x, a, b, c, d)
    if x <= a || x >= d
        score = 0;
    elseif x >= b && x <= c
        score = 100;
    elseif x > a && x < b
        score = 100 * (x - a) / (b - a);
    else  % x > c && x < d
        score = 100 * (d - x) / (d - c);
    end
end
