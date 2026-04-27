%% =========================================================================
%  MATLAB Function Block: ML_Predict_Block
%  File: ml_predict_block_fcn.m
%
%  PURPOSE:
%    Calls a trained compact ML model (Decision Tree or Random Forest)
%    from within a Simulink MATLAB Function block.
%    Outputs predicted crop index and confidence score.
%
%  PREREQUISITES:
%    1. Run train_agrosense_ml_model.m to generate agrosense_models_compact.mat
%    2. Ensure agrosense_models_compact.mat is on the MATLAB path
%
%  HOW TO USE IN SIMULINK:
%    1. Add a MATLAB Function block to your model
%    2. Open it and replace its content with this function
%    3. Connect 4 input ports (pH, moisture, temp, humidity)
%    4. Connect 2 output ports (crop_pred, confidence)
%
%  PASTE THIS CODE INTO THE MATLAB FUNCTION BLOCK EDITOR IN SIMULINK
% =========================================================================

function [crop_pred, confidence] = ml_predict_block(ph_f, moist_f, temp_f, hum_f)
%#codegen

% Load compact model (persistent to avoid reloading each timestep)
persistent dtModel cropClassNames

if isempty(dtModel)
    % Load from .mat file - must be on MATLAB path
    loaded = coder.load('agrosense_models_compact.mat', 'dtModelCompact', 'cropNames');
    dtModel = loaded.dtModelCompact;
    cropClassNames = loaded.cropNames;
end

% Assemble feature vector: [pH, moisture, temp, humidity]
X_input = [ph_f, moist_f, temp_f, hum_f];

% Predict crop class and posterior probabilities
[label, scores] = predict(dtModel, X_input);

% Output crop index (1-8)
crop_pred = double(label);

% Confidence = max posterior probability * 100
confidence = max(scores) * 100;

end

%% =========================================================================
%  ALTERNATIVE: Pure MATLAB Decision Tree (no .mat file needed)
%  Use this simplified version if you cannot load .mat files in Simulink
% =========================================================================

function [crop_pred, confidence] = ml_predict_simple(ph_f, moist_f, temp_f, hum_f)
%#codegen
% Simplified hand-coded decision tree for Nepal crop prediction
% Depth-4 tree based on dominant feature splits

    if ph_f < 5.8
        if temp_f < 20
            if moist_f < 40
                crop_pred = 4; conf = 0.72; % Mustard
            else
                crop_pred = 5; conf = 0.68; % Potato
            end
        else
            if hum_f > 70
                crop_pred = 1; conf = 0.75; % Rice
            else
                crop_pred = 8; conf = 0.65; % Millet
            end
        end
    elseif ph_f < 6.8
        if temp_f < 20
            if moist_f < 45
                crop_pred = 3; conf = 0.78; % Wheat
            else
                crop_pred = 5; conf = 0.70; % Potato
            end
        elseif temp_f < 28
            if moist_f > 60
                crop_pred = 6; conf = 0.74; % Tomato
            else
                crop_pred = 2; conf = 0.76; % Maize
            end
        else
            if hum_f > 75
                crop_pred = 1; conf = 0.80; % Rice
            else
                crop_pred = 2; conf = 0.71; % Maize
            end
        end
    else  % pH >= 6.8 (neutral to alkaline)
        if temp_f < 22
            crop_pred = 7; conf = 0.73; % Lentil
        elseif moist_f < 45
            crop_pred = 7; conf = 0.68; % Lentil
        elseif moist_f < 65
            crop_pred = 3; conf = 0.72; % Wheat
        else
            crop_pred = 1; conf = 0.65; % Rice
        end
    end
    
    confidence = conf * 100;

end
