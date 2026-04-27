function [datasetPath, latestPath, metadata] = export_nepal_matlab_data(numSamples, randomSeed)
% EXPORT_NEPAL_MATLAB_DATA
% Generates Nepal-focused agricultural simulation data in MATLAB and exports
% it for downstream Python AI training/inference.
%
% Outputs:
%   datasetPath - CSV with full training dataset.
%   latestPath  - CSV with recent sensor snapshots for inference.
%   metadata    - Struct with run details.

if nargin < 1 || isempty(numSamples)
    numSamples = 5000;
end
if nargin < 2 || isempty(randomSeed)
    randomSeed = 2026;
end

rng(randomSeed);

projectRoot = fileparts(mfilename('fullpath'));
dataDir = fullfile(projectRoot, 'data');
if ~exist(dataDir, 'dir')
    mkdir(dataDir);
end

[cropNames, cropTable, nutrientBase, cropCalendar, regionProfiles, regionWeights] = nepal_reference_profiles();

regionNames = fieldnames(regionProfiles);

rowId = (1:numSamples)';
regionCol = cell(numSamples, 1);
climateZoneCell = cell(numSamples, 1);
monthCol = zeros(numSamples, 1);
altitude_m = zeros(numSamples, 1);
pH = zeros(numSamples, 1);
moisture = zeros(numSamples, 1);
temperature = zeros(numSamples, 1);
humidity = zeros(numSamples, 1);
N_avail = zeros(numSamples, 1);
P_avail = zeros(numSamples, 1);
K_avail = zeros(numSamples, 1);
NPK_composite = zeros(numSamples, 1);
CropCell = cell(numSamples, 1);
N_apply_kg_ha = zeros(numSamples, 1);
P_apply_kg_ha = zeros(numSamples, 1);
K_apply_kg_ha = zeros(numSamples, 1);

for i = 1:numSamples
    regionIdx = weighted_choice(regionWeights);
    regionName = regionNames{regionIdx};
    regionCfg = regionProfiles.(regionName);

    monthV = randi(12);
    altitudeV = sample_altitude(regionCfg);

    [phV, moistV, tempV, humV] = simulate_sensor_snapshot(regionCfg, monthV, altitudeV);

    climateZoneV = infer_climate_zone(altitudeV, tempV, humV, monthV);

    [nAvail, pAvail, kAvail, npkComposite] = estimate_npk_components(phV, moistV, tempV, humV);

    cropIdx = select_crop_for_conditions( ...
        phV, moistV, tempV, humV, npkComposite, monthV, altitudeV, climateZoneV, ...
        regionCfg, cropTable, cropCalendar);

    [nDose, pDose, kDose] = estimate_npk_application( ...
        cropIdx, nutrientBase, nAvail, pAvail, kAvail, phV, moistV, humV, altitudeV, climateZoneV);

    regionCol{i} = regionName;
    climateZoneCell{i} = climateZoneV;
    monthCol(i) = monthV;
    altitude_m(i) = altitudeV;
    pH(i) = phV;
    moisture(i) = moistV;
    temperature(i) = tempV;
    humidity(i) = humV;
    N_avail(i) = nAvail;
    P_avail(i) = pAvail;
    K_avail(i) = kAvail;
    NPK_composite(i) = npkComposite;
    CropCell{i} = cropNames{cropIdx};
    N_apply_kg_ha(i) = nDose;
    P_apply_kg_ha(i) = pDose;
    K_apply_kg_ha(i) = kDose;
end

Crop = categorical(CropCell, cropNames);
region = categorical(regionCol, regionNames);
climate_zone = categorical(climateZoneCell, ...
    {'Tropical_Monsoon', 'Subtropical_Humid', 'Temperate_Hill', 'Cool_Mountain', 'Alpine_Cold'});

datasetTbl = table( ...
    rowId, region, climate_zone, monthCol, altitude_m, pH, moisture, temperature, humidity, ...
    N_avail, P_avail, K_avail, NPK_composite, Crop, ...
    N_apply_kg_ha, P_apply_kg_ha, K_apply_kg_ha, ...
    'VariableNames', { ...
        'sample_id', 'region', 'climate_zone', 'month', 'altitude_m', 'pH', 'moisture', ...
        'temperature', 'humidity', 'N_avail', 'P_avail', 'K_avail', 'NPK_composite', ...
        'Crop', 'N_apply_kg_ha', 'P_apply_kg_ha', 'K_apply_kg_ha'});

datasetPath = fullfile(dataDir, 'nepal_training_from_matlab.csv');
writetable(datasetTbl, datasetPath);

latestCount = min(48, numSamples);
latestIdx = (numSamples - latestCount + 1):numSamples;
latestTbl = datasetTbl(latestIdx, { ...
    'region', 'climate_zone', 'month', 'altitude_m', ...
    'pH', 'moisture', 'temperature', 'humidity', ...
    'N_avail', 'P_avail', 'K_avail', 'NPK_composite'});
latestPath = fullfile(dataDir, 'nepal_latest_sensor_from_matlab.csv');
writetable(latestTbl, latestPath);

metadata = struct();
metadata.samples = numSamples;
metadata.seed = randomSeed;
metadata.datasetPath = datasetPath;
metadata.latestPath = latestPath;
metadata.generatedOn = datestr(now, 31);

fprintf('===============================================================\n');
fprintf(' MATLAB Nepal data export completed\n');
fprintf('===============================================================\n');
fprintf('Samples generated: %d\n', numSamples);
fprintf('Training CSV:      %s\n', datasetPath);
fprintf('Latest CSV:        %s\n', latestPath);
fprintf('===============================================================\n');

end

function idx = weighted_choice(weights)
r = rand();
c = cumsum(weights(:));
idx = find(r <= c, 1, 'first');
if isempty(idx)
    idx = numel(weights);
end
end

function altitudeV = sample_altitude(regionCfg)
altitudeV = regionCfg.altMin + (regionCfg.altMax - regionCfg.altMin) * rand() + 80 * randn();
altitudeV = clip_value(altitudeV, 60, 5200);
end

function [phV, moistV, tempV, humV] = simulate_sensor_snapshot(regionCfg, monthV, altitudeV)
% Month-aware synthetic weather for Nepal regions with altitude influence.
phase = 2 * pi * (monthV - 1) / 12;

isMonsoon = monthV >= 6 && monthV <= 9;
monsoonBoost = 1.0 * double(isMonsoon);

% Temperature lapse rate approximation: -6.5 C per 1000m above ~300m.
altitudeCooling = max(0, altitudeV - 300) * (6.5 / 1000);

tempSeason = 6.0 * sin(phase - 0.8);
humSeason = 9.0 * sin(phase + 0.5);

tempV = regionCfg.tempBase + tempSeason - altitudeCooling + 2.2 * randn();
humV = regionCfg.humBase + humSeason + 8.0 * monsoonBoost + 4.0 * randn();

moistTrend = 0.35 * humV + 12.0 * monsoonBoost;
moistV = regionCfg.moistBase + (moistTrend - 0.35 * regionCfg.humBase) + 5.0 * randn();

phShiftMonsoon = -0.08 * monsoonBoost;
phV = regionCfg.phBase + phShiftMonsoon + 0.28 * randn();

phV = clip_value(phV, 4.5, 8.5);
moistV = clip_value(moistV, 10, 90);
tempV = clip_value(tempV, 4, 40);
humV = clip_value(humV, 20, 95);
end

function climateZone = infer_climate_zone(altitudeV, tempV, humV, monthV)
isMonsoon = monthV >= 6 && monthV <= 9;

if altitudeV >= 3400 || tempV <= 6
    climateZone = 'Alpine_Cold';
elseif altitudeV >= 2200
    climateZone = 'Cool_Mountain';
elseif altitudeV >= 1100
    climateZone = 'Temperate_Hill';
elseif isMonsoon && humV >= 65
    climateZone = 'Tropical_Monsoon';
else
    climateZone = 'Subtropical_Humid';
end
end

function cropIdx = select_crop_for_conditions(phV, moistV, tempV, humV, npkV, monthV, altitudeV, climateZone, regionCfg, cropTable, cropCalendar)
nCrops = size(cropTable, 1);
scores = zeros(1, nCrops);

for c = 1:nCrops
    req = cropTable(c, :);

    baseScore = 0.30 * trapezoid_membership(phV, req(1), req(2), req(3), req(4)) + ...
                0.25 * trapezoid_membership(moistV, req(5), req(6), req(7), req(8)) + ...
                0.25 * trapezoid_membership(tempV, req(9), req(10), req(11), req(12)) + ...
                0.10 * trapezoid_membership(humV, req(13), req(14), req(15), req(16)) + ...
                0.10 * npk_membership(npkV, req(17));

    seasonBonus = 0.08 * cropCalendar(c, monthV);
    regionBonus = 0.06 * regionCfg.cropPreference(c);
    altitudeBonus = 0.06 * altitude_crop_bonus(c, altitudeV);
    climateBonus = 0.06 * climate_crop_bonus(c, climateZone);

    scores(c) = baseScore + seasonBonus + regionBonus + altitudeBonus + climateBonus;
end

[~, cropIdx] = max(scores);
end

function bonus = altitude_crop_bonus(cropIdx, altitudeV)
switch cropIdx
    case 1  % Rice
        bonus = range_membership(altitudeV, 60, 150, 900, 1300);
    case 2  % Maize
        bonus = range_membership(altitudeV, 100, 400, 1800, 2500);
    case 3  % Wheat
        bonus = range_membership(altitudeV, 500, 1000, 2200, 3000);
    case 4  % Mustard
        bonus = range_membership(altitudeV, 400, 900, 2000, 2800);
    case 5  % Potato
        bonus = range_membership(altitudeV, 900, 1400, 3000, 3800);
    case 6  % Tomato
        bonus = range_membership(altitudeV, 300, 700, 1800, 2600);
    case 7  % Lentil
        bonus = range_membership(altitudeV, 600, 1000, 2200, 3000);
    otherwise % Millet
        bonus = range_membership(altitudeV, 200, 700, 2500, 3500);
end
end

function bonus = climate_crop_bonus(cropIdx, climateZone)
climateMap = struct();
climateMap.Tropical_Monsoon = [1.00, 0.82, 0.42, 0.35, 0.45, 0.72, 0.30, 0.58];
climateMap.Subtropical_Humid = [0.80, 0.88, 0.60, 0.62, 0.70, 0.84, 0.62, 0.72];
climateMap.Temperate_Hill = [0.40, 0.76, 0.90, 0.88, 0.92, 0.78, 0.86, 0.82];
climateMap.Cool_Mountain = [0.15, 0.40, 0.82, 0.78, 0.96, 0.42, 0.90, 0.94];
climateMap.Alpine_Cold = [0.05, 0.18, 0.52, 0.45, 0.88, 0.08, 0.64, 0.80];

if isfield(climateMap, climateZone)
    bonus = climateMap.(climateZone)(cropIdx);
else
    bonus = 0.5;
end
end

function [nAvail, pAvail, kAvail, npkComposite] = estimate_npk_components(phV, moistV, tempV, humV)
phPenalty = max(0, 1 - abs(phV - 6.5) / 2.0);
moistFactor = min(1, max(0, (moistV - 20) / 50));
tempFactor = max(0, 1 - abs(tempV - 24) / 16);
humFactor = min(1, max(0, (humV - 35) / 45));

npkBase = 100 * (0.6 * phPenalty + 0.4 * moistFactor);

nAvail = npkBase * (0.85 + 0.25 * moistFactor - 0.10 * (1 - humFactor));
pAvail = npkBase * (0.85 + 0.30 * phPenalty - 0.15 * (1 - tempFactor));
kAvail = npkBase * (0.90 + 0.20 * phPenalty + 0.05 * humFactor);

nAvail = clip_value(nAvail, 0, 100);
pAvail = clip_value(pAvail, 0, 100);
kAvail = clip_value(kAvail, 0, 100);
npkComposite = (nAvail + pAvail + kAvail) / 3;
end

function [nDose, pDose, kDose] = estimate_npk_application(cropIdx, nutrientBase, nAvail, pAvail, kAvail, phV, moistV, humV, altitudeV, climateZone)
baseN = nutrientBase(cropIdx, 1);
baseP = nutrientBase(cropIdx, 2);
baseK = nutrientBase(cropIdx, 3);

nDeficit = max(0, 1 - nAvail / 100);
pDeficit = max(0, 1 - pAvail / 100);
kDeficit = max(0, 1 - kAvail / 100);

droughtStress = max(0, (35 - moistV) / 35);
waterLogStress = max(0, (humV - 82) / 18);

nDose = baseN * (0.78 * nDeficit + 0.22 * droughtStress) + 5.0 * randn();
pDose = baseP * (0.82 * pDeficit) + 3.5 * randn();
kDose = baseK * (0.80 * kDeficit + 0.20 * waterLogStress) + 3.5 * randn();

if phV < 5.6
    pDose = pDose + 7 + 2 * rand();
elseif phV > 7.8
    pDose = pDose + 5 + 2 * rand();
end

if altitudeV >= 2200
    pDose = pDose + 4 + 2 * rand();
    kDose = kDose + 4 + 2 * rand();
elseif altitudeV <= 300
    nDose = nDose + 3 + 1.5 * rand();
end

switch climateZone
    case 'Tropical_Monsoon'
        nDose = nDose + 0.08 * baseN;
    case 'Cool_Mountain'
        pDose = pDose + 0.05 * baseP;
    case 'Alpine_Cold'
        nDose = nDose - 0.10 * baseN;
        pDose = pDose + 0.08 * baseP;
end

nDose = clip_value(nDose, 0, 220);
pDose = clip_value(pDose, 0, 150);
kDose = clip_value(kDose, 0, 170);
end

function score = trapezoid_membership(x, a, b, c, d)
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

function score = range_membership(x, a, b, c, d)
score = trapezoid_membership(x, a, b, c, d);
end

function score = npk_membership(npkValue, npkMin)
if npkValue >= npkMin
    score = 1;
elseif npkValue >= (npkMin * 0.5)
    score = (npkValue - npkMin * 0.5) / (npkMin * 0.5);
else
    score = 0;
end
end

function x = clip_value(x, lo, hi)
x = min(hi, max(lo, x));
end

function [cropNames, cropTable, nutrientBase, cropCalendar, regionProfiles, regionWeights] = nepal_reference_profiles()

cropNames = {'Rice', 'Maize', 'Wheat', 'Mustard', 'Potato', 'Tomato', 'Lentil', 'Millet'};

cropTable = [ ...
    5.0, 6.0, 7.0, 8.0, 50, 65, 80, 90, 20, 25, 35, 40, 60, 70, 90, 95, 60; ... % Rice
    5.5, 6.0, 7.0, 8.0, 30, 45, 65, 80, 18, 22, 32, 38, 40, 55, 80, 90, 55; ... % Maize
    5.5, 6.0, 7.0, 8.0, 25, 40, 60, 70, 10, 15, 22, 28, 35, 50, 70, 85, 50; ... % Wheat
    5.5, 6.0, 7.0, 7.5, 20, 35, 55, 70, 10, 15, 25, 30, 30, 45, 65, 80, 40; ... % Mustard
    4.8, 5.5, 6.5, 7.0, 40, 55, 70, 80, 14, 18, 24, 28, 45, 60, 80, 90, 65; ... % Potato
    5.5, 6.0, 6.8, 7.5, 35, 50, 65, 75, 18, 22, 28, 35, 40, 55, 75, 85, 60; ... % Tomato
    5.8, 6.5, 7.5, 8.0, 20, 35, 50, 65, 12, 18, 25, 30, 30, 45, 65, 75, 35; ... % Lentil
    5.0, 5.5, 6.5, 7.5, 20, 35, 55, 70, 20, 25, 35, 40, 30, 45, 70, 85, 30  ... % Millet
];

nutrientBase = [ ...
    120, 60, 40; ...  % Rice
    100, 50, 40; ...  % Maize
    90, 45, 35;  ...  % Wheat
    80, 50, 40;  ...  % Mustard
    110, 60, 90; ...  % Potato
    120, 70, 60; ...  % Tomato
    30, 40, 25;  ...  % Lentil
    45, 25, 25   ...  % Millet
];

% 1 indicates a common planting/growing window for the crop.
cropCalendar = [ ...
% J F M A M J J A S O N D
  0 0 0 1 1 1 1 1 1 0 0 0; ... % Rice
  1 1 1 1 1 1 1 1 1 1 1 1; ... % Maize
  1 1 1 0 0 0 0 0 0 1 1 1; ... % Wheat
  1 1 1 0 0 0 0 0 0 1 1 1; ... % Mustard
  1 1 1 1 1 0 0 0 0 1 1 1; ... % Potato
  1 1 1 1 1 1 1 1 1 1 1 1; ... % Tomato
  1 1 1 0 0 0 0 0 0 1 1 1; ... % Lentil
  1 1 1 1 1 1 1 1 1 1 1 1  ... % Millet
];

regionProfiles = struct();

regionProfiles.Terai = struct( ...
    'phBase', 6.4, ...
    'moistBase', 53, ...
    'tempBase', 27.0, ...
    'humBase', 70, ...
    'altMin', 60, ...
    'altMax', 700, ...
    'cropPreference', [1.00, 0.85, 0.60, 0.45, 0.50, 0.55, 0.35, 0.40]);

regionProfiles.Hill = struct( ...
    'phBase', 5.9, ...
    'moistBase', 46, ...
    'tempBase', 21.5, ...
    'humBase', 64, ...
    'altMin', 700, ...
    'altMax', 2200, ...
    'cropPreference', [0.65, 0.85, 0.80, 0.70, 0.85, 0.75, 0.70, 0.75]);

regionProfiles.Mountain = struct( ...
    'phBase', 5.6, ...
    'moistBase', 38, ...
    'tempBase', 15.0, ...
    'humBase', 57, ...
    'altMin', 2200, ...
    'altMax', 4500, ...
    'cropPreference', [0.25, 0.45, 0.85, 0.70, 0.75, 0.45, 0.85, 0.95]);

% Approximate Nepal land share used as sampling weights.
regionWeights = [0.48, 0.37, 0.15];

end
