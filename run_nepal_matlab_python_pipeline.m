%% =========================================================================
%  Smart AgroSense: MATLAB Simulation + Python AI Pipeline (Nepal)
%
%  Pipeline:
%    1) MATLAB generates Nepal-specific simulation dataset and latest snapshots
%    2) Python trains crop + nutrient models from MATLAB CSV
%    3) Python predicts recommendations for latest MATLAB snapshots
%    4) MATLAB prints and stores final summary
% =========================================================================

clear; clc; close all;

projectRoot = fileparts(mfilename('fullpath'));
addpath(projectRoot);

fprintf('=================================================================\n');
fprintf(' Smart AgroSense: MATLAB + Python AI Pipeline\n');
fprintf('=================================================================\n\n');

%% Paths
aiDir = fullfile(projectRoot, 'AI');
artifactsDir = fullfile(aiDir, 'artifacts');
outputsDir = fullfile(projectRoot, 'outputs');

if ~exist(artifactsDir, 'dir')
    mkdir(artifactsDir);
end
if ~exist(outputsDir, 'dir')
    mkdir(outputsDir);
end

trainScript = fullfile(aiDir, 'train_nepal_ai.py');
predictScript = fullfile(aiDir, 'predict_nepal_ai.py');

if ~isfile(trainScript)
    error('Missing Python training script: %s', trainScript);
end
if ~isfile(predictScript)
    error('Missing Python prediction script: %s', predictScript);
end

modelPath = fullfile(artifactsDir, 'nepal_crop_nutrient_model.joblib');
metricsPath = fullfile(artifactsDir, 'training_metrics.json');
predictionsPath = fullfile(outputsDir, 'nepal_python_recommendations.csv');
summaryPath = fullfile(outputsDir, 'final_product_summary.txt');

%% Stage 1: MATLAB data generation
fprintf('[1/3] Generating MATLAB Nepal dataset...\n');
[trainCsvPath, latestCsvPath, metadata] = export_nepal_matlab_data(12000, 2026);
fprintf('      Done: %d samples exported.\n\n', metadata.samples);

%% Stage 2: Python training
fprintf('[2/3] Training Python AI model...\n');
pythonCmd = resolve_python_command(projectRoot);
trainCmd = sprintf('%s "%s" --input-csv "%s" --model-out "%s" --metrics-out "%s"', ...
    pythonCmd, trainScript, trainCsvPath, modelPath, metricsPath);

[trainStatus, trainOutput] = system(trainCmd);
fprintf('%s\n', trainOutput);
if trainStatus ~= 0
    error(['Python training failed. Install dependencies with: ', ...
        'pip install -r AI/requirements.txt']);
end
fprintf('      Done: Python model trained.\n\n');

%% Stage 3: Python inference using latest MATLAB data
fprintf('[3/3] Running Python inference on latest MATLAB data...\n');
predictCmd = sprintf('%s "%s" --model "%s" --input-csv "%s" --output-csv "%s"', ...
    pythonCmd, predictScript, modelPath, latestCsvPath, predictionsPath);

[predictStatus, predictOutput] = system(predictCmd);
fprintf('%s\n', predictOutput);
if predictStatus ~= 0
    error('Python inference failed.');
end
fprintf('      Done: Recommendations generated.\n\n');

%% Final report
if ~isfile(predictionsPath)
    error('Predictions file not found: %s', predictionsPath);
end

predTbl = readtable(predictionsPath);
if isempty(predTbl)
    error('Predictions table is empty: %s', predictionsPath);
end

best = predTbl(1,:);

hasClimate = ismember('climate_zone', predTbl.Properties.VariableNames);
hasAltitude = ismember('altitude_m', predTbl.Properties.VariableNames);

fprintf('=================================================================\n');
fprintf(' FINAL RECOMMENDATION (Latest Snapshot)\n');
fprintf('=================================================================\n');
fprintf(' Region:             %s\n', string(best.region));
if hasClimate
    fprintf(' Climate Zone:       %s\n', string(best.climate_zone));
end
fprintf(' Month:              %d\n', best.month);
if hasAltitude
    fprintf(' Altitude:           %.1f m\n', best.altitude_m);
end
fprintf(' Predicted Crop:     %s\n', string(best.predicted_crop));
fprintf(' Confidence:         %.2f%%\n', best.confidence_pct);
fprintf(' N recommendation:   %.2f kg/ha\n', best.N_recommend_kg_ha);
fprintf(' P recommendation:   %.2f kg/ha\n', best.P_recommend_kg_ha);
fprintf(' K recommendation:   %.2f kg/ha\n', best.K_recommend_kg_ha);
fprintf(' Top 3 crops:        %s (%.2f%%), %s (%.2f%%), %s (%.2f%%)\n', ...
    string(best.top1_crop), best.top1_score_pct, ...
    string(best.top2_crop), best.top2_score_pct, ...
    string(best.top3_crop), best.top3_score_pct);
fprintf('=================================================================\n\n');

write_summary(summaryPath, metadata, best, metricsPath, modelPath, predictionsPath);

fprintf('Saved summary: %s\n', summaryPath);
fprintf('Pipeline complete.\n');

function cmd = resolve_python_command(projectRoot)
% Prefer project virtual environment Python first, then system launcher.
venvPython = fullfile(projectRoot, '.venv', 'Scripts', 'python.exe');
if isfile(venvPython)
    cmd = ['"', venvPython, '"'];
    return;
end

[statusPy, ~] = system('py -3 --version');
if statusPy == 0
    cmd = 'py -3';
    return;
end

[statusPython, ~] = system('python --version');
if statusPython == 0
    cmd = 'python';
    return;
end

error(['Python executable not found. Install Python 3 and ensure ', ...
    'either "py -3" or "python" works in terminal.']);
end

function write_summary(summaryPath, metadata, best, metricsPath, modelPath, predictionsPath)
hasClimate = ismember('climate_zone', best.Properties.VariableNames);
hasAltitude = ismember('altitude_m', best.Properties.VariableNames);

lines = {
    'SMART AGROSENSE FINAL PRODUCT SUMMARY'
    ['Generated on: ', datestr(now)]
    ''
    'PIPELINE'
    'MATLAB simulation data -> Python model training -> Python inference'
    ''
    'DATA'
    ['Samples generated: ', num2str(metadata.samples)]
    ['Training CSV: ', metadata.datasetPath]
    ['Latest CSV: ', metadata.latestPath]
    ''
    'ARTIFACTS'
    ['Model: ', modelPath]
    ['Metrics: ', metricsPath]
    ['Predictions: ', predictionsPath]
    ''
    'FINAL RECOMMENDATION'
    ['Region: ', char(string(best.region))]
    ['Climate Zone: ', char(string(get_opt_value(best, hasClimate, 'climate_zone', 'N/A')))]
    ['Month: ', num2str(best.month)]
    ['Altitude (m): ', char(string(get_opt_value(best, hasAltitude, 'altitude_m', 'N/A')))]
    ['Crop: ', char(string(best.predicted_crop))]
    ['Confidence: ', sprintf('%.2f%%', best.confidence_pct)]
    ['N recommendation (kg/ha): ', sprintf('%.2f', best.N_recommend_kg_ha)]
    ['P recommendation (kg/ha): ', sprintf('%.2f', best.P_recommend_kg_ha)]
    ['K recommendation (kg/ha): ', sprintf('%.2f', best.K_recommend_kg_ha)]
    ['Top 3: ', char(string(best.top1_crop)), ' (', sprintf('%.2f', best.top1_score_pct), '%), ', ...
        char(string(best.top2_crop)), ' (', sprintf('%.2f', best.top2_score_pct), '%), ', ...
        char(string(best.top3_crop)), ' (', sprintf('%.2f', best.top3_score_pct), '%)']
};

fid = fopen(summaryPath, 'w');
if fid < 0
    error('Cannot write summary file: %s', summaryPath);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
for i = 1:numel(lines)
    fprintf(fid, '%s\n', lines{i});
end
end

function value = get_opt_value(tblRow, hasField, fieldName, fallback)
if hasField
    value = tblRow.(fieldName);
else
    value = fallback;
end
end
