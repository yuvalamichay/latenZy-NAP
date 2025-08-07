%% BATCH LATENCY ANALYSIS (STITCHING METHOD) FOR MULTIPLE FILES
% This script loops through a user-defined list of spike and raw file pairs.
% For each pair, it:
% 1. Creates a unique output folder.
% 2. Applies a "stitching" method to remove the stimulation artifact window.
% 3. Calculates latency, adjusts it back to the original timeline, and filters results.
% 4. Generates plots invisibly in the background.
% 5. Saves all plots and a detailed latencyData struct into the output folder.

clear; clc;

%% --- USER PARAMETERS ---

% --- List of file pairs to analyze ---
% Add as many structs to this cell array as needed.
filePairs = { ...
    struct('spikeFile', 'OWT220207_1I_DIV63_HUB63_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_1I_DIV63_HUB63_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_2B_DIV63_HUB24_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_2B_DIV63_HUB24_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_2D_DIV63_HUB73_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_2D_DIV63_HUB73_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_2E_DIV63_HUB36_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_2E_DIV63_HUB36_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_2I_DIV63_HUB24_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_2I_DIV63_HUB24_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_1I_DIV63_PER37_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_1I_DIV63_PER37_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_2B_DIV63_PER52_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_2B_DIV63_PER52_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_2D_DIV63_PER58_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_2D_DIV63_PER58_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_2E_DIV63_PER71_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_2E_DIV63_PER71_6UA.mat') ...
    ,struct('spikeFile', 'OWT220207_2I_DIV63_PER83_6UA_cSpikes_L0_RP2.mat_Nortefact.mat', 'rawFile', 'OWT220207_2I_DIV63_PER83_6UA.mat') ...
    % --- Add more file pairs below ---
    % Example:
    % ,struct('spikeFile', 'path/to/your/second_spike_file.mat', 'rawFile', 'path/to/your/second_raw_file.mat') ...
};

% --- Global Analysis Parameters ---
numChannels = 60;
fs = 25000; % Hz
spikeMethod = 'bior1p5';
artifact_window_ms = [0, 2]; % ms (artifact window)

% -- Stimulation Detection Parameters for 'longblank' method --
min_blanking_duration_ms = 4;  % Minimum duration of a flat signal to be a stim (ms)
stim_refractory_period_ms = 2000; % Minimum interval between stims (ms)

% -- Unused Parameters (for compatibility with function signature) --
stimThreshold = -1000; % Not used by 'longblank' method
flat_thresh = 0.05; % Not used by 'longblank' method
flat_search_window_ms = 100; % Not used by 'longblank' method

% --- Latenzy Function Parameters ---
useDur = [-0.02 0.05]; % Analysis window in seconds
resampNum = 100;
jitterSize = 2;
peakAlpha = 0.05;
doStitch = true;
useParPool = false;
useDirectQuant = false;
restrictNeg = true;

% --- Electrode/Channel Mapping ---
% 'indices' are the original channel numbers from the recording system (1-based).
% 'ids' are the corresponding electrode labels you want to use for plotting and output.
% The order matters: indices(i) maps to ids(i).
indices = [24 26 29 32 35 37, 21 22 25 30 31 36 39 40, 19 20 23 28 33 38 41 42, 16 17 18 27 34 43 44 45, 15 14 13 4 57 48 47 46, 12 11 8 3 58 53 50 49, 10 9 6 1 60 55 52 51, 7 5 2 59 56 54];
ids = [21 31 41 51 61 71, 12 22 32 42 52 62 72 82, 13 23 33 43 53 63 73 83, 14 24 34 44 54 64 74 84, 15 25 35 45 55 65 75 85, 16 26 36 46 56 66 76 86, 17 27 37 47 57 67 77 87, 28 38 48 58 68 78];

%% --- MAIN BATCH PROCESSING LOOP ---
for k = 1:numel(filePairs)
    % --- Get current file pair ---
    spikeFile = filePairs{k}.spikeFile;
    rawFile = filePairs{k}.rawFile;
    
    fprintf('\n\n============================================================\n');
    fprintf('STARTING ANALYSIS FOR FILE PAIR %d of %d:\n', k, numel(filePairs));
    fprintf('  Spike File: %s\n', spikeFile);
    fprintf('  Raw File: %s\n', rawFile);
    fprintf('============================================================\n');

    % --- Generate a unique output directory for this file pair ---
    [~, baseName, ~] = fileparts(rawFile);
    timestamp = datestr(now, 'ddmmmyyyy_HHMMSS');
    outputDir = sprintf('Latency_Analysis_%s_%s', baseName, timestamp);
    if ~exist(outputDir, 'dir'), mkdir(outputDir); end
    fprintf('Saving analysis plots and data to folder: %s\n', outputDir);

    % --- Start of Integrated Analysis Script ---

    %% 1. CONVERT SPIKE TIMES
    S = load(spikeFile);
    if isfield(S, 'spikeTimes')
        spikeTimesConverted = S.spikeTimes;
    elseif isfield(S, 'spikes')
        disp('Converting ''spikes'' matrix to ''spiketimesconverted'' struct format...');
        [row, col] = find(S.spikes);
        spikeTimesConverted = cell(1, numChannels);
        for ch = 1:numChannels
            spike_samples = row(col == ch);
            spike_sec = spike_samples / fs;
            spikeTimesConverted{ch} = struct(spikeMethod, spike_sec);
        end
    else
        error('Neither ''spikeTimes'' nor ''spikes'' found in file %s.', spikeFile);
    end

    %% 2. ESTIMATE STIM TIMES
    fprintf('Detecting stimulation times...\n');
    [stimTimes_ms, ~, ~] = detect_stim_times(rawFile, numChannels, fs, ...
        stimThreshold, min_blanking_duration_ms, flat_thresh, stim_refractory_period_ms, flat_search_window_ms);
    stimTimesConverted = stimTimes_ms / 1000;

    %% 3. REMOVE ARTIFACT SPIKES AND "STITCH" SPIKE TRAIN
    fprintf('Applying stitching artifact removal...\n');
    R = load(rawFile);
    dat = double(R.dat);
    [num_samples, ~] = size(dat);
    recording_length_sec = num_samples / fs;
    
    spikeTimesConvertedCleaned = cell(1, numChannels);
    cutWin_sec = artifact_window_ms / 1000;
    artifactDur_sec = diff(cutWin_sec);

    for ch = 1:numChannels
        if isempty(spikeTimesConverted{ch}) || ~isfield(spikeTimesConverted{ch}, spikeMethod)
            spikeTimesConvertedCleaned{ch} = [];
            continue;
        end
        spikeTimes_sec = spikeTimesConverted{ch}.(spikeMethod);
        if isempty(spikeTimes_sec) || isempty(stimTimesConverted)
            spikeTimesConvertedCleaned{ch} = spikeTimes_sec;
            continue;
        end
        analysis_window_sec = [-max(stimTimesConverted), recording_length_sec];
        [~, trialSpikes] = getRelSpikeTimes(spikeTimes_sec, stimTimesConverted, analysis_window_sec);
        trialSpikesShifted = cellfun(@(x) [x(x < cutWin_sec(1)) + artifactDur_sec; x(x >= cutWin_sec(2))], trialSpikes, 'UniformOutput', false);
        allCleanSpikesCell = cell(size(trialSpikesShifted));
        for i = 1:length(trialSpikesShifted)
            spikesRel = trialSpikesShifted{i};
            if ~isempty(spikesRel)
                allCleanSpikesCell{i} = spikesRel + stimTimesConverted(i);
            end
        end
        spikeTimesConvertedCleaned{ch} = unique(vertcat(allCleanSpikesCell{:}));
    end

    %% 4. CALCULATE FIRING RATES (ON ORIGINAL CHANNELS)
    fprintf('Calculating firing rates...\n');
    firingRates = zeros(1, numChannels);
    for ch = 1:numChannels
        if ~isempty(spikeTimesConvertedCleaned{ch})
            firingRates(ch) = numel(spikeTimesConvertedCleaned{ch}) / recording_length_sec;
        else
            firingRates(ch) = 0;
        end
    end
    
    %% 5. CALCULATE AND PLOT LATENCY, APPLYING ELECTRODE MAPPING FOR OUTPUT
    fprintf('Calculating latencies and generating plots...\n');
    latencyData = struct([]);
    structIdx = 1; % Index for latencyData struct
    
    % --- Set default figure visibility to 'off' for batch processing ---
    set(0, 'DefaultFigureVisible', 'off');
    
    % Loop through all original channels
    for ch = 1:numChannels
        % Find if the current channel has a mapping to an electrode ID
        map_idx = find(indices == ch, 1);
        
        % If this channel is not in our 'indices' map, skip it
        if isempty(map_idx)
            continue;
        end
        
        % Get the corresponding electrode ID for filenames and struct
        electrodeID = ids(map_idx);
        
        spikeTimes = spikeTimesConvertedCleaned{ch};
        
        if isempty(spikeTimes)
            latency_compressed = NaN;
            adjustedLatency = NaN;
            sLatenzy = [];
        else
            [latency_compressed, sLatenzy] = latenzy(spikeTimes, stimTimesConverted, useDur, resampNum, ...
                jitterSize, peakAlpha, doStitch, useParPool, useDirectQuant, restrictNeg, false);

            if isnan(latency_compressed)
                adjustedLatency = NaN;
            elseif latency_compressed <= cutWin_sec(1) + artifactDur_sec
                adjustedLatency = latency_compressed - artifactDur_sec;
            else
                adjustedLatency = latency_compressed;
            end
            
            if ~isnan(adjustedLatency) && adjustedLatency <= cutWin_sec(2)
                adjustedLatency = NaN;
            end

            if ~isnan(adjustedLatency)
                % Call latenzy to generate the plot invisibly
                latenzy(spikeTimes, stimTimesConverted, useDur, resampNum, jitterSize, peakAlpha, ...
                    doStitch, useParPool, useDirectQuant, restrictNeg, true);
                
                fh = gcf; % Get handle to the current (invisible) figure
                
                % Add a title with the final, adjusted latency and electrode ID
                titleStr = sprintf('Electrode %d - Final Adjusted Latency: %.2f ms', electrodeID, adjustedLatency * 1000);
                sgtitle(fh, titleStr, 'Color', 'k', 'FontWeight', 'bold');
                
                % Save the modified figure using the electrode ID
                plotFileName = sprintf('Latency_Elec%d.png', electrodeID);
                exportgraphics(fh, fullfile(outputDir, plotFileName));
                close(fh); % Close invisible figure after saving
            end
        end

        % Save data to the struct, using the correct electrode ID
        latencyData(structIdx).electrode = electrodeID;
        latencyData(structIdx).latency_compressed = latency_compressed;
        latencyData(structIdx).latency = adjustedLatency;
        latencyData(structIdx).sLatenzy = sLatenzy;
        latencyData(structIdx).firingRate = firingRates(ch); % Firing rate from original channel
        
        structIdx = structIdx + 1; % Increment struct index
    end
    
    % --- Restore default figure visibility ---
    set(0, 'DefaultFigureVisible', 'on');

    %% 6. SAVE LATENCY DATA
    latencyDataFilename = fullfile(outputDir, sprintf('%s_latencyData.mat', baseName));
    save(latencyDataFilename, 'latencyData');
    fprintf('Saved latency data to %s\n', latencyDataFilename);
    
    fprintf('--- Finished analysis for: %s ---\n', baseName);
    close all;
end

fprintf('\n\nAll file pairs have been processed.\n');