%% =========================================================================
%  MATLAB Function Block: Soil_Classifier
%  File: soil_classifier_fcn.m
%
%  PURPOSE:
%    Classifies filtered sensor readings into human-readable soil condition
%    categories encoded as integers for display/processing.
%
%  INPUTS:
%    ph_val   - Filtered soil pH (4.5 to 8.5)
%    moist    - Filtered soil moisture % (10 to 90)
%    temp     - Filtered temperature °C (10 to 40)
%    humidity - Filtered air humidity % (30 to 95)
%
%  OUTPUTS:
%    ph_class       - 1=Acidic, 2=Slightly Acidic, 3=Neutral, 4=Alkaline
%    moisture_class - 1=Dry, 2=Moderate, 3=Wet
%    temp_class     - 1=Low, 2=Suitable, 3=High
%    humidity_class - 1=Low, 2=Moderate, 3=High
%
%  PASTE THIS CODE INTO THE MATLAB FUNCTION BLOCK EDITOR IN SIMULINK
% =========================================================================

function [ph_class, moisture_class, temp_class, humidity_class] = ...
    soil_classifier(ph_val, moist, temp, humidity)

%% pH Classification
% Nepal soils range from strongly acidic hill soils to alkaline terai soils
if ph_val < 5.5
    ph_class = 1;     % Strongly Acidic - needs lime
elseif ph_val < 6.5
    ph_class = 2;     % Slightly Acidic - suits most crops
elseif ph_val <= 7.5
    ph_class = 3;     % Neutral - ideal for most Nepal crops
else
    ph_class = 4;     % Alkaline - needs acidifying agents
end

%% Moisture Classification
% Based on volumetric water content equivalents
if moist < 25
    moisture_class = 1;   % Dry - irrigation needed
elseif moist <= 60
    moisture_class = 2;   % Moderate - good for most crops
else
    moisture_class = 3;   % Wet - drainage may be needed
end

%% Temperature Classification
% Based on Nepal's major crop growing seasons
if temp < 15
    temp_class = 1;   % Too Low - only cold-tolerant crops (wheat, barley)
elseif temp <= 32
    temp_class = 2;   % Suitable - rice, maize, vegetables grow well
else
    temp_class = 3;   % Too High - heat stress risk, shade crops
end

%% Humidity Classification
if humidity < 45
    humidity_class = 1;   % Low - drought risk, moisture conservation needed
elseif humidity <= 70
    humidity_class = 2;   % Moderate - balanced for most crops
else
    humidity_class = 3;   % High - disease risk (fungal), good for rice
end

end
