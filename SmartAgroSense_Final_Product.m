%% =========================================================================
%  Smart AgroSense - Final Product Entrypoint
%  File: SmartAgroSense_Final_Product.m
%
%  PURPOSE:
%    One command to run the full project pipeline in a clean order.
%
%  USAGE:
%    matlab -batch SmartAgroSense_Final_Product
% =========================================================================

clc; clear; close all;

fprintf('=================================================================\n');
fprintf(' Smart AgroSense Final Product\n');
fprintf('=================================================================\n\n');

% Pipeline toggles
runModelBuilder = true;
runStandaloneSimulation = true;
runPythonAIPipeline = true;

projectRoot = fileparts(mfilename('fullpath'));

requiredFiles = { ...
    'build_agrosense_model.m', ...
    'run_agrosense_simulation.m', ...
    'run_nepal_matlab_python_pipeline.m', ...
    fullfile('AI', 'train_nepal_ai.py'), ...
    fullfile('AI', 'predict_nepal_ai.py') ...
};

for i = 1:numel(requiredFiles)
    fullPath = fullfile(projectRoot, requiredFiles{i});
    if ~isfile(fullPath)
        error('Required file not found: %s', fullPath);
    end
end

addpath(projectRoot);
addpath(fullfile(projectRoot, 'AI'));

if runModelBuilder
    fprintf('[1/3] Building Simulink model...\n');
    run_stage_script(fullfile(projectRoot, 'build_agrosense_model.m'));
    fprintf('      Done: SmartAgroSense.slx generated.\n\n');
else
    fprintf('[1/3] Skipped Simulink model build.\n\n');
end

if runStandaloneSimulation
    fprintf('[2/3] Running standalone simulation...\n');
    run_stage_script(fullfile(projectRoot, 'run_agrosense_simulation.m'));
    fprintf('      Done: standalone simulation completed.\n\n');
else
    fprintf('[2/3] Skipped standalone simulation.\n\n');
end

if runPythonAIPipeline
    fprintf('[3/3] Running Python AI from MATLAB-exported Nepal data...\n');
    run_stage_script(fullfile(projectRoot, 'run_nepal_matlab_python_pipeline.m'));
    fprintf('      Done: Python AI recommendation pipeline completed.\n\n');
else
    fprintf('[3/3] Skipped Python AI pipeline.\n\n');
end

fprintf('=================================================================\n');
fprintf(' Final product pipeline completed successfully.\n');
fprintf('=================================================================\n');

function run_stage_script(scriptPath)
% Run stage scripts in an isolated function workspace.
% This prevents clear/clc inside child scripts from wiping caller variables.
if ~isfile(scriptPath)
    error('Stage script not found: %s', scriptPath);
end
run(scriptPath);
end
