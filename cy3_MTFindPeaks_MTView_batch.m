function cy3_MTFindPeaks_MTView_batch()
% -------------------------------------------------------------------------
% batch analysis - keeps the original MTFindPeaks / MTView logic unchanged
% requirements covered:
%   - LOW and HIGH each use a different avgLim (default proposed from the first file of each group, then entered manually)
%   - output is written next to each file, in "<filename>_Output"
%   - intermediate results are saved (ROI/peak overlay, heat maps, ...)
%   - the corrected signals of all files are pooled into a single histogram as well
% -------------------------------------------------------------------------

%% ===== user settings =====
PeakR        = 5;           % radius of the signal circle
ROIR         = 50;          % radius of the search ROI (MTFindPeaks only)
exR_det      = PeakR + 1;   % exR of MTFindPeaks
exR_view     = PeakR + 2;   % outer radius of the MTView background ring
histNumBins  = 64;          % bin count of the pooled histogram
saveDPI      = 300;

%% ===== file selection =====
[filesLow, pathLow] = uigetfile('*.mat','Select LOW files (multi-select OK)', 'MultiSelect','on');
if isequal(filesLow,0), disp('Cancelled.'); return; end
filesLow = normalize_file_list(filesLow);

filesHigh = {}; pathHigh = '';
if strcmp(questdlg('Also select HIGH files?','HIGH selection','Yes','No','Yes'),'Yes')
    [filesHigh, pathHigh] = uigetfile('*.mat','Select HIGH files (multi-select OK)', 'MultiSelect','on');
    if ~isequal(filesHigh,0), filesHigh = normalize_file_list(filesHigh); else, filesHigh = {}; end
end

%% ===== LOW avgLim (set separately per group) =====
SrefL = load(fullfile(pathLow, filesLow{1}));  assert(isfield(SrefL,'movie1'),'movie1 missing');
meanRefL = mean(double(SrefL.movie1),3);
defL = {num2str(prctile(meanRefL(:),5)), num2str(prctile(meanRefL(:),99))};
aL = inputdlg({'LOW avgLim low','LOW avgLim high'}, 'avgLim for MTFindPeaks (LOW)', 1, defL);
if isempty(aL), return; end
avgLimLOW = [str2double(aL{1}), str2double(aL{2})];

%% ===== HIGH avgLim (only when present) =====
avgLimHIGH = [];
if ~isempty(filesHigh)
    SrefH = load(fullfile(pathHigh, filesHigh{1}));  assert(isfield(SrefH,'movie1'),'movie1 missing');
    meanRefH = mean(double(SrefH.movie1),3);
    defH = {num2str(prctile(meanRefH(:),5)), num2str(prctile(meanRefH(:),99))};
    aH = inputdlg({'HIGH avgLim low','HIGH avgLim high'}, 'avgLim for MTFindPeaks (HIGH)', 1, defH);
    if isempty(aH), return; end
    avgLimHIGH = [str2double(aH{1}), str2double(aH{2})];
end

%% ===== accumulation buffer (for the pooled histogram) =====
ALL_corr = []; LOW_corr = []; HIGH_corr = [];

%% ===== LOW processing (MTFindPeaks -> MTView per file, avgLim = avgLimLOW) =====
for i = 1:numel(filesLow)
    fp = fullfile(pathLow, filesLow{i});
    corrVec = run_one_file_MT_native(fp, avgLimLOW, PeakR, ROIR, exR_det, exR_view, saveDPI);
    LOW_corr = [LOW_corr; corrVec(:)]; %#ok<AGROW>
    ALL_corr = [ALL_corr; corrVec(:)]; %#ok<AGROW>
end

%% ===== HIGH processing (when present, avgLim = avgLimHIGH) =====
for i = 1:numel(filesHigh)
    fp = fullfile(pathHigh, filesHigh{i});
    corrVec = run_one_file_MT_native(fp, avgLimHIGH, PeakR, ROIR, exR_det, exR_view, saveDPI);
    HIGH_corr = [HIGH_corr; corrVec(:)]; %#ok<AGROW>
    ALL_corr  = [ALL_corr;  corrVec(:)]; %#ok<AGROW>
end

%% ===== pooled histogram (saved in the first LOW output folder) =====
if ~isempty(ALL_corr)
    refOut = outdir_of_mat(fullfile(pathLow, filesLow{1}));
    save_hist(ALL_corr,  fullfile(refOut,'Z_combined_hist_ALL'),  histNumBins, saveDPI, 'ALL files');
    if ~isempty(LOW_corr)
        save_hist(LOW_corr,  fullfile(refOut,'Z_combined_hist_LOW'),  histNumBins, saveDPI, 'LOW');
    end
    if ~isempty(HIGH_corr)
        save_hist(HIGH_corr, fullfile(refOut,'Z_combined_hist_HIGH'), histNumBins, saveDPI, 'HIGH');
    end
end

disp('Done. Per-file outputs are next to each input (*_Output). Group-specific avgLim applied.');
end % ===== main =====



%% ========================= 1-file runner (MTFindPeaks → MTView) =========================
function corrVec = run_one_file_MT_native(matPath, avgLim, PeakR, ROIR, exR_det, exR_view, saveDPI)
    % ---- Load
    S = load(matPath);  assert(isfield(S,'movie1'),'movie1 missing');
    movie1 = double(S.movie1);
    [h,w,N] = size(movie1);
    avgFrame = mean(movie1,3);

    % ---- Paths
    [fileDir, nameOnly] = fileparts(matPath);
    outDir = outdir_of_mat(matPath);  if ~exist(outDir,'dir'), mkdir(outDir); end
    savePeakPath = fullfile(fileDir, [nameOnly '_peak.mat']);

    % ---- MTFindPeaks UX (unchanged)
    f1 = figure(1); clf; imagesc(avgFrame, avgLim); axis image; colormap(jet(256)); colorbar;
    hold on; hBead = plot(NaN,NaN,'w','LineWidth',2); hold off; title('Click a point ');
    f2 = figure(2); clf; hFluor = plot(1:N, NaN(1,N), 'r', 'LineWidth', 2);
    xlabel('Frame'); ylabel('Intensity (a.u.)');

    % intensity probe
    figure(1); disp('Click a point');
    V = movie1;
    while true
        [gx, gy] = ginput(1);
        if numel(gx)>0
            set(hFluor,'YData', V(round(gy(1)), round(gx(1)), :));
        else
            break;
        end
    end

    % ROI selection (the last click is used)
    ROIX = (1+w)/2; ROIY = (1+h)/2; exR = exR_det;
    figure(1); title('Click for an ROI'); disp('Click for an ROI');
    while true
        [gx, gy] = ginput(1);
        if numel(gx)>0
            ROIX = gx(1); ROIY = gy(1);
            [xdata, ydata] = DrawCircle(ROIX, ROIY, ROIR, false);
            set(hBead,'XData',xdata,'YData',ydata);
        else
            break;
        end
    end

    % candidates / sorting / non-maximum suppression (original)
    [X, Y] = meshgrid(1:w, 1:h);
    V = avgFrame;
    ind = find( (X-ROIX).^2 + (Y-ROIY).^2 < ROIR^2 );
    ind( V(ind) < avgLim(2) ) = [];                   % avgLim(2) is the actual threshold
    [~, sortI] = sort( V(ind), 'descend' );  ind = ind(sortI);  ind0 = ind;

    Peaks = zeros(0,2);
    while ~isempty(ind)
        cx = X(ind(1));  cy = Y(ind(1));
        ci = (X(ind0)-cx).^2 + (Y(ind0)-cy).^2 <= exR^2 ;
        if V(cy,cx) >= max( V(ind0(ci)) )
            Peaks(end+1,:) = [cx cy]; %#ok<AGROW>
            ind( (X(ind)-cx).^2 + (Y(ind)-cy).^2 <= exR^2 ) = [];
        else
            ind(1) = [];
        end
    end
    NPeaks = size(Peaks,1);

    % correct peaks (original: disc median-corrected centre of mass)
    [PX, PY] = meshgrid(-exR:exR, -exR:exR);
    PeakI = find(PX.^2 + PY.^2 <= PeakR^2);
    for i = 1:NPeaks
        xi = Peaks(i,1); yi = Peaks(i,2);
        lin = h*(xi+PX(PeakI)-1) + yi+PY(PeakI);
        lin = lin(lin>=1 & lin<=h*w);               % guard against the border
        bg = median( V(lin) );
        Vbgsub = max( V(lin) - bg, 0 );
        cx = sum( X(lin) .* Vbgsub )/sum(Vbgsub);
        cy = sum( Y(lin) .* Vbgsub )/sum(Vbgsub);
        Peaks(i,:) = [cx cy];
    end

    % save the peak overlay
    f3 = figure(1); title('Peaks'); hold on;
    for i = 1:NPeaks
        DrawCircle(Peaks(i,1), Peaks(i,2), exR);
    end
    hold off; axis image; colormap(jet(256));
    minX = max(1, min(Peaks(:,1)) - exR);
    maxX = min(w, max(Peaks(:,1)) + exR);
    minY = max(1, min(Peaks(:,2)) - exR);
    maxY = min(h, max(Peaks(:,2)) + exR);
    axis([minX maxX minY maxY]);
    exportgraphics(f3, fullfile(outDir,'C_Peaks_on_avgFrame.png'), 'Resolution', saveDPI);

    % save Peaks (original format)
    save(fullfile(fileDir, [nameOnly '_peak.mat']), 'Peaks');

    % save the average TIF (for visualisation)
    imwrite(to_uint16_by_percentiles(avgFrame, 1, 99), ...
            fullfile(outDir, sprintf('%s_mean.tif', nameOnly)), 'Compression','none');

    % ---- MTView (original computation) + save the intermediates
    [Sgnl, Bgnd] = MTView_native(Peaks, movie1, [nameOnly '.mat'], fileDir, avgLim, PeakR, exR_view, saveDPI);

    % returns the corrected signal for the pooled histogram
    corrVec = Sgnl(:);

    % tidy up the windows
    try, close(1); close(2); end %#ok<*TRYNC>
end



%% ========================= MTView (original computation kept) =========================
function [Sgnl, Bgnd] = MTView_native(Peaks, movie1, fileName, filePath, avgLim, PeakR, exR, saveDPI)
    movie1 = double(movie1);
    [h,~,N] = size(movie1);
    avgFrame = mean(movie1, 3);

    [~, nameOnly, ~] = fileparts(fileName);
    outputFolder = fullfile(filePath, [nameOnly '_Output']);
    if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

    % show and save the average frame
    f = figure('Visible','off'); imagesc(avgFrame, avgLim);
    title('Peaks'); hold on;
    for i = 1:size(Peaks, 1)
        DrawCircle(Peaks(i, 1), Peaks(i, 2), PeakR, true, [1, 1, 1], 1, i);
    end
    hold off; axis image; colormap(jet(256));
    exportgraphics(f, fullfile(outputFolder, 'AverageFrame.png'), 'Resolution', saveDPI);
    close(f);

    % signal/background intensity (original)
    Sgnl = zeros(size(Peaks, 1), N);
    Bgnd = zeros(size(Peaks, 1), N);
    [PX, PY] = meshgrid(-exR:exR, -exR:exR);
    PeakI = find(PX.^2 + PY.^2 <= PeakR^2);
    BgndI = find((PX.^2 + PY.^2 >= PeakR^2) & (PX.^2 + PY.^2 <= exR^2));
    for i = 1:size(Peaks, 1)
        xi = round(Peaks(i, 1)); yi = round(Peaks(i, 2));
        pkIi = h * (xi + PX(PeakI) - 1) + yi + PY(PeakI);
        bgIi = h * (xi + PX(BgndI) - 1) + yi + PY(BgndI);
        pkIi = pkIi(pkIi>=1 & pkIi<=numel(avgFrame));
        bgIi = bgIi(bgIi>=1 & bgIi<=numel(avgFrame));
        for k = 1:N
            framek = movie1(:, :, k);
            Bgnd(i, k) = mean(framek(bgIi));
            Sgnl(i, k) = mean(framek(pkIi)) - Bgnd(i, k);
        end
    end

    % save the heat maps
    f1 = figure('Visible','off'); imagesc(Bgnd,[min(Bgnd(:)), max(Bgnd(:))]);
    title('Background Intensity'); xlabel('Time (frame)'); ylabel('Molecule');
    colorbar('EastOutside'); colormap(jet(256));
    exportgraphics(f1, fullfile(outputFolder, 'BackgroundIntensity.png'), 'Resolution', 300);
    close(f1);

    f2 = figure('Visible','off'); imagesc(Sgnl,[min(Sgnl(:)), max(Sgnl(:))]);
    title('Signal Intensity'); xlabel('Time (frame)'); ylabel('Molecule');
    colorbar('EastOutside'); colormap(jet(256));
    exportgraphics(f2, fullfile(outputFolder, 'SignalIntensity.png'), 'Resolution', 300);
    close(f2);

    % save the individual peak time traces
    for i = 1:size(Peaks, 1)
        f3 = figure('Visible','off');
        plot(1:N, Bgnd(i, :), 'k', 'LineWidth', 1); hold on;
        plot(1:N, Sgnl(i, :), 'r', 'LineWidth', 1); hold off;
        xlabel('Time (frame)'); ylabel('Intensity (a.u.)');
        title(sprintf('Peak %d: (%.1f, %.1f)', i, Peaks(i, 1), Peaks(i, 2)));
        exportgraphics(f3, fullfile(outputFolder, sprintf('Peak_%03d.png', i)), 'Resolution', 300);
        close(f3);
    end

    % save Fluor.mat
    save(fullfile(outputFolder, 'Fluor.mat'), 'Sgnl', 'Bgnd', 'avgLim', 'PeakR', 'exR');
end



%% ========================= Utils (including the original DrawCircle) =========================
function files = normalize_file_list(filesIn)
    if ischar(filesIn), files = {filesIn};
    elseif iscell(filesIn), files = filesIn;
    else, files = {};
    end
end

function outDir = outdir_of_mat(matPath)
    [p, n] = fileparts(matPath);
    outDir = fullfile(p, [n '_Output']);
end

function save_hist(vals, basepath, nbins, dpi, ttl)
    edges   = linspace(min(vals), max(vals), nbins+1);
    [counts, edges] = histcounts(vals, edges);
    centers = edges(1:end-1) + diff(edges)/2;
    fh = figure('Visible','off','Color','w');
    bar(centers, counts, 'EdgeColor','none'); grid on;
    xlabel('Intensity (background-corrected, a.u.)'); ylabel('Count');
    title(['Combined histogram — ' ttl]);
    exportgraphics(fh, [basepath '.png'], 'Resolution', dpi);
    close(fh);
    writetable(table(centers(:),counts(:),'VariableNames',{'Intensity','Count'}), [basepath '.csv']);
end

function U = to_uint16_by_percentiles(img, pLo, pHi)
    lo = prctile(img(:), pLo); hi = prctile(img(:), pHi);
    img = min(max(img, lo), hi);
    U = uint16( 65535 * (img - lo) / max(hi-lo, eps) );
end

function [ xdata, ydata ] = DrawCircle(x, y, r, flag, c, w, i)
    xdata = x + r*cos(2*pi*(0:0.05:1));
    ydata = y + r*sin(2*pi*(0:0.05:1));
    if nargin < 4, flag = true; end
    if nargin < 5, c = [ 1 1 1 ]; end
    if nargin < 6, w = 2; end
    if flag
        plot( xdata, ydata, '-', 'Color', c, 'LineWidth', w );
        if nargin>=7, text(xdata(1), ydata(1), mat2str(i),'Color','w'); end
    end
end
