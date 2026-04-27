%% One-command launcher for MATLAB simulation + Python AI recommendation
clc; clear; close all;

projectRoot = fileparts(mfilename('fullpath'));
pipelinePath = fullfile(projectRoot, 'run_nepal_matlab_python_pipeline.m');

if ~isfile(pipelinePath)
	error('Pipeline script not found: %s', pipelinePath);
end

run(pipelinePath);
