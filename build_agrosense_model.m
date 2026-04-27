%% =========================================================================
%  Smart AgroSense: AI and Sensor-Based Crop Recommendation System for Nepal
%  Simulink Model Builder Script
%  =========================================================================
%  Run this script in MATLAB to programmatically create the full Simulink model.
%  Requires: MATLAB R2020b+ with Simulink toolbox
%
%  Usage:
%    >> build_agrosense_model
%
%  This will create: SmartAgroSense.slx
%  Then open it with: >> open_system('SmartAgroSense')
% =========================================================================

clear; clc;
disp('====================================================');
disp(' Smart AgroSense Model Builder');
disp(' Crop Recommendation System for Nepal');
disp('====================================================');

%% --- Model Name ---
modelName = 'SmartAgroSense';

% Close if already open
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end

% Create new model
new_system(modelName);
open_system(modelName);

% Set simulation parameters
set_param(modelName, 'StopTime', '100');
set_param(modelName, 'SolverType', 'Fixed-step');
set_param(modelName, 'FixedStep', '0.1');
set_param(modelName, 'Solver', 'FixedStepAuto');

disp('[1/8] Creating Sensor Data Generation Subsystem...');

%% =========================================================================
%  SUBSYSTEM 1: Sensor Data Generation
%  Generates realistic simulated sensor readings for Nepal farming conditions
% =========================================================================

% --- Position layout constants ---
xBase = 30; yBase = 30;
blockW = 120;

% Create Sensor Subsystem
sensorSys = [modelName '/Sensor_Data_Generation'];
add_block('built-in/Subsystem', sensorSys, ...
    'Position', [xBase, yBase, xBase+blockW+20, yBase+160]);

% ---- Inside Sensor Subsystem ----
% Fully random sensor sources to emulate unknown soil/environment state.
rng('shuffle');
pHSeed = num2str(randi([1, 2147483646]));
moistSeed = num2str(randi([1, 2147483646]));
tempSeed = num2str(randi([1, 2147483646]));
humSeed = num2str(randi([1, 2147483646]));

% pH Sensor: random range 4.5 to 8.5
add_block('simulink/Sources/Uniform Random Number', [sensorSys '/pH_Random'], ...
    'Minimum', '4.5', 'Maximum', '8.5', 'SampleTime', '0.1', 'Seed', pHSeed, ...
    'Position', [30, 55, 190, 85]);
add_block('built-in/Outport', [sensorSys '/pH_Out'], ...
    'Port', '1', 'Position', [260, 60, 300, 80]);
add_line(sensorSys, 'pH_Random/1', 'pH_Out/1');

% Moisture Sensor: random range 10% to 90%
add_block('simulink/Sources/Uniform Random Number', [sensorSys '/Moisture_Random'], ...
    'Minimum', '10', 'Maximum', '90', 'SampleTime', '0.1', 'Seed', moistSeed, ...
    'Position', [30, 175, 190, 205]);
add_block('built-in/Outport', [sensorSys '/Moisture_Out'], ...
    'Port', '2', 'Position', [260, 180, 300, 200]);
add_line(sensorSys, 'Moisture_Random/1', 'Moisture_Out/1');

% Temperature Sensor: random range 10C to 40C
add_block('simulink/Sources/Uniform Random Number', [sensorSys '/Temp_Random'], ...
    'Minimum', '10', 'Maximum', '40', 'SampleTime', '0.1', 'Seed', tempSeed, ...
    'Position', [30, 295, 190, 325]);
add_block('built-in/Outport', [sensorSys '/Temp_Out'], ...
    'Port', '3', 'Position', [260, 300, 300, 320]);
add_line(sensorSys, 'Temp_Random/1', 'Temp_Out/1');

% Humidity Sensor: random range 30% to 95%
add_block('simulink/Sources/Uniform Random Number', [sensorSys '/Humidity_Random'], ...
    'Minimum', '30', 'Maximum', '95', 'SampleTime', '0.1', 'Seed', humSeed, ...
    'Position', [30, 415, 190, 445]);
add_block('built-in/Outport', [sensorSys '/Humidity_Out'], ...
    'Port', '4', 'Position', [260, 420, 300, 440]);
add_line(sensorSys, 'Humidity_Random/1', 'Humidity_Out/1');

disp('[2/8] Creating Signal Filtering Subsystem...');

%% =========================================================================
%  SUBSYSTEM 2: Signal Filtering
%  Moving average + discrete low-pass filter for each sensor channel
% =========================================================================

filterSys = [modelName '/Signal_Filtering'];
add_block('built-in/Subsystem', filterSys, ...
    'Position', [220, yBase, 380, yBase+160]);

% ---- Filter for each channel (inside filterSys) ----
sensors = {'pH', 'Moisture', 'Temp', 'Humidity'};
yOff = [30, 150, 270, 390];

for i = 1:4
    s = sensors{i};
    yo = yOff(i);
    
    % Input port
    add_block('built-in/Inport', [filterSys '/' s '_In'], ...
        'Port', num2str(i), 'Position', [30, yo, 70, yo+30]);
    
    % Moving Average (Discrete FIR with uniform window = 10 samples)
    % Approximated using Transfer Fcn Discrete with numerator = ones(1,10)/10
    add_block('simulink/Discrete/Discrete Transfer Fcn', ...
        [filterSys '/' s '_MovAvg'], ...
        'Numerator', 'ones(1,10)/10', ...
        'Denominator', '[1 0 0 0 0 0 0 0 0 0]', ...
        'SampleTime', '0.1', ...
        'Position', [110, yo, 230, yo+30]);
    
    % Low-pass filter: H(z) = 0.2/(z - 0.8) => smoothing constant ~0.2
    add_block('simulink/Discrete/Discrete Transfer Fcn', ...
        [filterSys '/' s '_LPF'], ...
        'Numerator', '[0.2]', ...
        'Denominator', '[1, -0.8]', ...
        'SampleTime', '0.1', ...
        'Position', [270, yo, 390, yo+30]);
    
    % Output port (filtered signal)
    add_block('built-in/Outport', [filterSys '/' s '_Out'], ...
        'Port', num2str(i), 'Position', [440, yo+5, 480, yo+25]);
    
    % Connect
    add_line(filterSys, [s '_In/1'],    [s '_MovAvg/1']);
    add_line(filterSys, [s '_MovAvg/1'], [s '_LPF/1']);
    add_line(filterSys, [s '_LPF/1'],   [s '_Out/1']);
end

disp('[3/8] Creating Soil Classification Subsystem...');

%% =========================================================================
%  SUBSYSTEM 3: Soil Condition Classification
%  Uses MATLAB Function block to classify each sensor reading
% =========================================================================

classSys = [modelName '/Soil_Classification'];
add_block('built-in/Subsystem', classSys, ...
    'Position', [430, yBase, 590, yBase+160]);

% Classifier MATLAB Function block
add_block('built-in/Inport', [classSys '/pH_filt'],       'Port','1','Position',[30,30,70,60]);
add_block('built-in/Inport', [classSys '/Moist_filt'],    'Port','2','Position',[30,100,70,130]);
add_block('built-in/Inport', [classSys '/Temp_filt'],     'Port','3','Position',[30,170,70,200]);
add_block('built-in/Inport', [classSys '/Humidity_filt'], 'Port','4','Position',[30,240,70,270]);

add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [classSys '/Soil_Classifier'], ...
    'Position', [120, 30, 280, 280]);

% Load classifier function code so the block exposes all expected ports
soilFcnFile = fullfile(pwd, 'soil_classifier_fcn.m');
load_matlab_function_block_script([classSys '/Soil_Classifier'], soilFcnFile, 'Soil_Classifier');

add_block('built-in/Outport', [classSys '/pH_Class'],      'Port','1','Position',[340,50,380,70]);
add_block('built-in/Outport', [classSys '/Moist_Class'],   'Port','2','Position',[340,120,380,140]);
add_block('built-in/Outport', [classSys '/Temp_Class'],    'Port','3','Position',[340,190,380,210]);
add_block('built-in/Outport', [classSys '/Humidity_Class'],'Port','4','Position',[340,260,380,280]);

add_line(classSys, 'pH_filt/1',       'Soil_Classifier/1');
add_line(classSys, 'Moist_filt/1',    'Soil_Classifier/2');
add_line(classSys, 'Temp_filt/1',     'Soil_Classifier/3');
add_line(classSys, 'Humidity_filt/1', 'Soil_Classifier/4');
add_line(classSys, 'Soil_Classifier/1', 'pH_Class/1');
add_line(classSys, 'Soil_Classifier/2', 'Moist_Class/1');
add_line(classSys, 'Soil_Classifier/3', 'Temp_Class/1');
add_line(classSys, 'Soil_Classifier/4', 'Humidity_Class/1');

disp('[4/8] Creating AI Crop Recommendation Subsystem...');

%% =========================================================================
%  SUBSYSTEM 4: AI Crop Recommendation Engine
% =========================================================================

aiSys = [modelName '/AI_Crop_Recommendation'];
add_block('built-in/Subsystem', aiSys, ...
    'Position', [640, yBase, 820, yBase+200]);

% Inputs
inputLabels = {'pH_filt','Moist_filt','Temp_filt','Humidity_filt'};
for i = 1:4
    add_block('built-in/Inport', [aiSys '/' inputLabels{i}], ...
        'Port', num2str(i), 'Position', [30, 20+(i-1)*60, 80, 40+(i-1)*60]);
end

% NPK estimator block (rule-based from filtered sensor inputs)
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [aiSys '/NPK_Estimator'], ...
    'Position', [110, 30, 240, 120]);

% Load NPK estimator function code
npkFcnFile = fullfile(pwd, 'npk_estimator_fcn.m');
load_matlab_function_block_script([aiSys '/NPK_Estimator'], npkFcnFile, 'NPK_Estimator');

% AI Recommendation engine
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [aiSys '/Crop_AI_Engine'], ...
    'Position', [280, 20, 430, 300]);

% Load crop AI function code so the block exposes all expected ports
cropAIFcnFile = fullfile(pwd, 'crop_ai_engine_fcn.m');
load_matlab_function_block_script([aiSys '/Crop_AI_Engine'], cropAIFcnFile, 'Crop_AI_Engine');

% Outputs
add_block('built-in/Outport', [aiSys '/Crop_Score'],    'Port','1','Position',[490,50,530,70]);
add_block('built-in/Outport', [aiSys '/Crop_Index'],    'Port','2','Position',[490,130,530,150]);
add_block('built-in/Outport', [aiSys '/Advice_Code'],   'Port','3','Position',[490,210,530,230]);

for i = 1:4
    add_line(aiSys, [inputLabels{i} '/1'], ['Crop_AI_Engine/' num2str(i)]);
end

% Internal NPK estimation wiring
add_line(aiSys, 'pH_filt/1', 'NPK_Estimator/1');
add_line(aiSys, 'Moist_filt/1', 'NPK_Estimator/2');
add_line(aiSys, 'Temp_filt/1', 'NPK_Estimator/3');
add_line(aiSys, 'Humidity_filt/1', 'NPK_Estimator/4');
add_line(aiSys, 'NPK_Estimator/1', 'Crop_AI_Engine/5');

add_line(aiSys, 'Crop_AI_Engine/1', 'Crop_Score/1');
add_line(aiSys, 'Crop_AI_Engine/2', 'Crop_Index/1');
add_line(aiSys, 'Crop_AI_Engine/3', 'Advice_Code/1');

disp('[5/8] Creating Cost Comparison Subsystem...');

%% =========================================================================
%  SUBSYSTEM 5: Cost Comparison
% =========================================================================

costSys = [modelName '/Cost_Comparison'];
add_block('built-in/Subsystem', costSys, ...
    'Position', [640, yBase+220, 820, yBase+360]);

% Expensive system cost: NPK sensor ~$150 + pH $30 + others = ~$350
add_block('simulink/Sources/Constant', [costSys '/Expensive_System'], ...
    'Value', '350', 'Position', [30, 40, 120, 70]);

% Low-cost system: pH $10 + moisture $8 + temp $5 + humidity $5 + MCU $12 = ~$40
add_block('simulink/Sources/Constant', [costSys '/LowCost_System'], ...
    'Value', '40', 'Position', [30, 120, 120, 150]);

% Cost reduction: ((350-40)/350)*100 = 88.6%
add_block('simulink/Math Operations/Add', [costSys '/Cost_Diff'], ...
    'Inputs', '+-', 'Position', [170, 55, 210, 85]);
add_block('simulink/Math Operations/Divide', [costSys '/Cost_Ratio'], ...
    'Position', [260, 55, 310, 85]);
add_block('simulink/Math Operations/Gain', [costSys '/To_Percent'], ...
    'Gain', '100', 'Position', [360, 55, 420, 85]);

add_block('built-in/Outport', [costSys '/Cost_Reduction_Pct'], ...
    'Port', '1', 'Position', [470, 60, 510, 80]);
add_block('built-in/Outport', [costSys '/LowCost_USD'], ...
    'Port', '2', 'Position', [470, 130, 510, 150]);

add_line(costSys, 'Expensive_System/1', 'Cost_Diff/1');
add_line(costSys, 'LowCost_System/1',   'Cost_Diff/2');
add_line(costSys, 'Cost_Diff/1',         'Cost_Ratio/1');
add_line(costSys, 'Expensive_System/1',  'Cost_Ratio/2');
add_line(costSys, 'Cost_Ratio/1',        'To_Percent/1');
add_line(costSys, 'To_Percent/1',        'Cost_Reduction_Pct/1');
add_line(costSys, 'LowCost_System/1',    'LowCost_USD/1');

disp('[6/8] Adding Dashboard Display blocks...');

%% =========================================================================
%  DASHBOARD DISPLAY BLOCKS
%  Using Display blocks for key outputs
% =========================================================================

dashX = 900;

displayBlocks = { ...
    'pH_Display',          [dashX, 30,  dashX+100, 60],  'pH Value'; ...
    'Moisture_Display',    [dashX, 80,  dashX+100, 110], 'Moisture (%)'; ...
    'Temp_Display',        [dashX, 130, dashX+100, 160], 'Temperature (C)'; ...
    'Humidity_Display',    [dashX, 180, dashX+100, 210], 'Humidity (%)'; ...
    'CropScore_Display',   [dashX, 250, dashX+100, 280], 'Suitability Score'; ...
    'CropIndex_Display',   [dashX, 300, dashX+100, 330], 'Crop Index'; ...
    'AdviceCode_Display',  [dashX, 350, dashX+100, 380], 'Advice Code'; ...
    'CostSave_Display',    [dashX, 430, dashX+100, 460], 'Cost Saved (%)'; ...
};

for i = 1:size(displayBlocks, 1)
    add_block('simulink/Sinks/Display', ...
        [modelName '/' displayBlocks{i,1}], ...
        'Position', displayBlocks{i,2}, ...
        'Format', 'short');
end

disp('[7/8] Adding Scope blocks for raw vs filtered signals...');

%% =========================================================================
%  SCOPE BLOCKS: Raw vs Filtered comparison
% =========================================================================

scopeY = [30, 120, 210, 300];
scopeLabels = {'pH_Scope','Moisture_Scope','Temp_Scope','Humidity_Scope'};

for i = 1:4
    add_block('simulink/Sinks/Scope', ...
        [modelName '/' scopeLabels{i}], ...
        'Position', [750, scopeY(i), 850, scopeY(i)+50], ...
        'NumInputPorts', '2', ...
        'Open', 'off');
    % Note: connections to raw + filtered done after subsystems are wired
end

disp('[8/8] Wiring all top-level subsystems together...');

%% =========================================================================
%  TOP-LEVEL WIRING
%  Connect Sensor -> Filter -> Classifier -> AI Engine -> Dashboard
% =========================================================================

% Sensor -> Filter
add_line(modelName, 'Sensor_Data_Generation/1', 'Signal_Filtering/1');
add_line(modelName, 'Sensor_Data_Generation/2', 'Signal_Filtering/2');
add_line(modelName, 'Sensor_Data_Generation/3', 'Signal_Filtering/3');
add_line(modelName, 'Sensor_Data_Generation/4', 'Signal_Filtering/4');

% Filter -> Classifier
add_line(modelName, 'Signal_Filtering/1', 'Soil_Classification/1');
add_line(modelName, 'Signal_Filtering/2', 'Soil_Classification/2');
add_line(modelName, 'Signal_Filtering/3', 'Soil_Classification/3');
add_line(modelName, 'Signal_Filtering/4', 'Soil_Classification/4');

% Filter -> AI Engine
add_line(modelName, 'Signal_Filtering/1', 'AI_Crop_Recommendation/1');
add_line(modelName, 'Signal_Filtering/2', 'AI_Crop_Recommendation/2');
add_line(modelName, 'Signal_Filtering/3', 'AI_Crop_Recommendation/3');
add_line(modelName, 'Signal_Filtering/4', 'AI_Crop_Recommendation/4');

% NPK is estimated internally inside AI_Crop_Recommendation subsystem.

% AI -> Dashboard
add_line(modelName, 'AI_Crop_Recommendation/1', 'CropScore_Display/1');
add_line(modelName, 'AI_Crop_Recommendation/2', 'CropIndex_Display/1');
add_line(modelName, 'AI_Crop_Recommendation/3', 'AdviceCode_Display/1');

% Filter -> Dashboard (sensor readings)
add_line(modelName, 'Signal_Filtering/1', 'pH_Display/1');
add_line(modelName, 'Signal_Filtering/2', 'Moisture_Display/1');
add_line(modelName, 'Signal_Filtering/3', 'Temp_Display/1');
add_line(modelName, 'Signal_Filtering/4', 'Humidity_Display/1');

% Cost -> Dashboard
add_line(modelName, 'Cost_Comparison/1', 'CostSave_Display/1');

% Scopes: raw sensor vs filtered
add_line(modelName, 'Sensor_Data_Generation/1', 'pH_Scope/1');
add_line(modelName, 'Signal_Filtering/1',        'pH_Scope/2');
add_line(modelName, 'Sensor_Data_Generation/2', 'Moisture_Scope/1');
add_line(modelName, 'Signal_Filtering/2',        'Moisture_Scope/2');
add_line(modelName, 'Sensor_Data_Generation/3', 'Temp_Scope/1');
add_line(modelName, 'Signal_Filtering/3',        'Temp_Scope/2');
add_line(modelName, 'Sensor_Data_Generation/4', 'Humidity_Scope/1');
add_line(modelName, 'Signal_Filtering/4',        'Humidity_Scope/2');

% Arrange model layout
set_param(modelName, 'ZoomFactor', 'FitSystem');

% Save model
save_system(modelName, 'SmartAgroSense.slx');
disp('====================================================');
disp(' Model saved as: SmartAgroSense.slx');
disp(' Run: sim(''SmartAgroSense'') to simulate');
disp('====================================================');
disp('MATLAB Function blocks were auto-loaded from companion .m files.');

function load_matlab_function_block_script(blockPath, scriptFile, blockLabel)
if ~isfile(scriptFile)
    warning('%s not found. %s ports may be incomplete.', scriptFile, blockLabel);
    return;
end

try
    rt = sfroot;
    chart = find(rt, '-isa', 'Stateflow.EMChart', 'Path', blockPath);
    if isempty(chart)
        warning('Could not locate %s chart object at path: %s', blockLabel, blockPath);
        return;
    end
    chart.Script = fileread(scriptFile);
catch ME
    warning('Failed to load %s into %s: %s', scriptFile, blockLabel, ME.message);
end
end
