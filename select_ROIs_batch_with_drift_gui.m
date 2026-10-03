function select_ROIs_batch_with_drift_gui()
% SELECT_ROIS_BATCH_WITH_DRIFT_GUI
%   Select ROIs for multiple drift-corrected movie files using GUI
%   Automatically pairs each movie with its corresponding drift file
%   Saves ROI info in "Saved_ROIs" and full mean images separately

clc; close all;

% === Select multiple movie files ===
[movieFiles, moviePath] = uigetfile('*record.mat', 'Select movie .mat files', 'MultiSelect', 'on');
if isequal(movieFiles, 0)
    disp('No movie file selected.');
    return;
end
if ischar(movieFiles)
    movieFiles = {movieFiles};
end

% === Prepare save directory ===
savedir = fullfile(moviePath, 'Saved_ROIs');
if ~exist(savedir, 'dir'), mkdir(savedir); end

for k = 1:numel(movieFiles)
    fname = movieFiles{k};
    fileID = erase(fname, '.mat');
    movieFile = fullfile(moviePath, fname);
    driftFile = fullfile(moviePath, [fileID '_hybridBG_drift.mat']);

    fprintf('%s ▶ [%d/%d] %s\n', newline, k, numel(movieFiles), fileID);

    data = load(movieFile);
    if ~isfield(data, 'movie1')
        warning('Skipping: no movie found in %s', fname);
        continue;
    end
    [instruments, movie] = deal(data.instruments, data.movie1);

    if ~isfile(driftFile)
        warning('Skipping: drift file not found for %s', fileID);
        continue;
    end
    drift = load(driftFile);
    if ~isfield(drift, 'cumX') || ~isfield(drift, 'cumY')
        warning('Skipping: drift file invalid for %s', fileID);
        continue;
    end
    cumX = drift.cumX;
    cumY = drift.cumY;

    % === Drift Correction ===
    [h, w, T] = size(movie);
    movie_corr = zeros(h, w, T);
    for t = 1:T
        movie_corr(:,:,t) = imtranslate(double(movie(:,:,t)), [-cumX(t), -cumY(t)], 'OutputView', 'same', 'Method','bicubic');
    end

    % === Force-based Frame Split ===
    [lowFrames, highFrames] = detect_stable_force_frames(instruments, T);
    % disp('low force #frame')
    % disp(lowFrames)
    % disp('high force #frame')
    % disp(highFrames)
    meanLow  = mean(movie_corr(:,:,lowFrames), 3);
    meanHigh = mean(movie_corr(:,:,highFrames), 3);

    % === ROI Selection Parameters ===
    roiWidth = 50; roiHeight = 13; offsetLeft = 15; deltaSearch = 5;
    roiPos_all = {}; peakCol_all = []; peakRow_all = [];

    fig = figure('Name',['Click ROI for ' fileID],'Color','w');
    imagesc(meanLow); axis image off; colormap('jet'); colorbar;
    title('Click near Cy3 signal (ESC to cancel)'); hold on;

    while true
        [cx, cy, btn] = ginput(1);
        if isempty(btn) || btn == 27, break; end

        cx = round(cx); cy = round(cy);
        if cx < 1 || cx > size(meanLow,2) || cy < 1 || cy > size(meanLow,1)
            warning('⚠️ Clicked outside image bounds. Try again.'); continue;
        end

        xSearchMin = max(1, cx - deltaSearch);
        xSearchMax = min(size(meanLow,2), cx + deltaSearch);
        ySearchMin = max(1, cy - deltaSearch);
        ySearchMax = min(size(meanLow,1), cy + deltaSearch);

        rowProfile = meanLow(cy, xSearchMin:xSearchMax);
        if max(rowProfile) < 0.05 * max(meanLow(:))
            warning('⚠️ No significant signal at clicked location. Try again.'); continue;
        end
        [~, maxIdxX] = max(rowProfile);
        peakCol = xSearchMin + maxIdxX - 1;

        colProfile = meanLow(ySearchMin:ySearchMax, peakCol);
        [~, maxIdxY] = max(colProfile);
        peakRow = ySearchMin + maxIdxY - 1;

        x = peakCol - offsetLeft;
        y = peakRow - floor(roiHeight/2);
        x = max(1, min(x, size(meanLow,2) - roiWidth + 1));
        y = max(1, min(y, size(meanLow,1) - roiHeight + 1));

        roiIndex = numel(roiPos_all) + 1;
        rectangle('Position', [x, y, roiWidth, roiHeight], 'EdgeColor','r', 'LineWidth', 1.5);
        plot(cx, cy, 'w+', 'MarkerSize', 10, 'LineWidth', 1.5);
        plot(peakCol, peakRow, 'r*', 'MarkerSize', 10, 'LineWidth', 1.5);
        text(x + 2, y - 10, sprintf('ROI %d', roiIndex), 'Color','y', 'FontSize', 7, 'FontWeight','bold');

        roiPos_all{end+1} = [x, y, roiWidth, roiHeight];
        peakCol_all(end+1) = peakCol;
        peakRow_all(end+1) = peakRow;
    end

    if isempty(roiPos_all)
        fprintf('⚠️  No ROIs selected for %s\n', fileID);
        continue;
    end
    saveas(fig, fullfile(savedir, [fileID '_ROI_selection.png'])); close(fig);

    % === Background Estimation (ScatteredInterpolant) ===
    [bgLow_full, bgHigh_full] = estimate_background_scattered_nansafe(meanLow, meanHigh, roiPos_all);
    save(fullfile(savedir, [fileID '_full_meanImages.mat']), 'meanLow', 'meanHigh', 'bgLow_full', 'bgHigh_full');
    % === 전체 시각화 추가 ===
    visualize_background_correction_whole(meanLow, meanHigh, bgLow_full, bgHigh_full, savedir, fileID);

    % === ROI 별 저장 및 시각화 ===
    roiInfo = struct();
    for i = 1:numel(roiPos_all)
        roi = roiPos_all{i};
        x = roi(1); y = roi(2); w = roi(3); h = roi(4);

        patchLow = meanLow(y:y+h-1, x:x+w-1) - bgLow_full(y:y+h-1, x:x+w-1);
        patchHigh = meanHigh(y:y+h-1, x:x+w-1) - bgHigh_full(y:y+h-1, x:x+w-1);
        patchLow(patchLow < 0) = 0; patchHigh(patchHigh < 0) = 0;

        roiInfo(i).filename = fileID;
        roiInfo(i).roiID = i;
        roiInfo(i).roiPos_all = roi;
        roiInfo(i).imageLow = patchLow;
        roiInfo(i).imageHigh = patchHigh;
        roiInfo(i).lowFrames = lowFrames;
        roiInfo(i).highFrames = highFrames;
        roiInfo(i).peakRow = peakRow_all(i);
        roiInfo(i).peakCol = peakCol_all(i);

        % --- 시각화 ---
        visualize_bg_subtraction(meanLow, meanHigh, bgLow_full, bgHigh_full, roi, savedir, fileID, i);
    end

    save(fullfile(savedir, [fileID '_ROIs.mat']), 'roiInfo', 'roiPos_all');
    fprintf('✅ Saved: %s\n', [fileID '_ROIs.mat']);
end
end
