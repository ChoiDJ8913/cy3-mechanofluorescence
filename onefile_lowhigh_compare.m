function onefile_lowhigh_compare()
% Analyze LOW/HIGH contained in a single Fluor.mat per folder.
% - Select a parent folder; scans **/Fluor.mat recursively
% - For each Fluor.mat (Sgnl: ROI x Frame):
%   * computes the mean signal of the LOW and HIGH windows (same file)
%   * drops ROIs that bleach (decay within a window)
%   * scatter plots and histograms for both raw and relative (LOW baseline = 1)
%   * writes a per-ROI metric CSV and a debug CSV
%
% Defaults reflect: exposure=0.1 s, condition switch at 5 s (gap 3-7 s excluded)
%  -> LOW = 1~300,  HIGH = 701~1000

%% ===== user settings =====
% frame windows (1-based, clipped automatically to the file length)
lowFrames      = 1:40;       % 0~3 s
highFrames     = 61:100;    % 7~10 s
baselineFrames = 1:40;        % baseline for the relative normalisation (LOW = 1), taken from the start of LOW

% bleaching test (applied within each of the LOW and HIGH windows)
bleach_frac_win = 0.50;       % use 20% of the window length as early/late
bleach_burnin   = 0;          % frames discarded at the start of early
bleach_ratio_th = 0.80;       % late/early < 0.6 => bleaching

% quality filter (on the LOW baseline)
snr_min       = 0.0;          % raise above 0 if needed (e.g. 1.0)
abs_low_min   = 0.0;          % minimum mean brightness of the LOW baseline

% histogram
nbins_raw     = 70;
clip_raw      = [];           % e.g. [30 310] (leave empty to disable)
nbins_rel     = 60;
clip_rel      = [0 1.5];      % clip the range of the relative values if needed

% equality band of the scatter plot (+/-10%)
equiv_band    = 0.10;

%% ===== input and output =====
parentDir = uigetdir(pwd, 'Select parent folder containing Fluor.mat (single-file LOW/HIGH)');
if parentDir==0, disp('Cancelled.'); return; end
outDir  = fullfile(parentDir, 'onefile_lowhigh_results');  if ~exist(outDir,'dir'), mkdir(outDir); end
csvDir  = fullfile(outDir, 'csv');                          if ~exist(csvDir,'dir'), mkdir(csvDir); end
figDir  = fullfile(outDir, 'fig');                          if ~exist(figDir,'dir'), mkdir(figDir); end

%% ===== recursive search for Fluor.mat =====
hits = [ dir(fullfile(parentDir,'**','Fluor.mat')); dir(fullfile(parentDir,'**','fluor.mat')) ];
if isempty(hits)
    error('No Fluor.mat found under: %s', parentDir);
end

%% ===== pooled buffers =====
X_raw = []; Y_raw = [];
X_rel = []; Y_rel = [];
rows  = {};      % accumulate the per-ROI metrics
dbg   = {};      % per-file summary and drop counts

%% ===== loop =====
for h = 1:numel(hits)
    fpath = fullfile(hits(h).folder, hits(h).name);
    [ok, R] = analyze_one_file(fpath, lowFrames, highFrames, baselineFrames, ...
                               bleach_frac_win, bleach_burnin, bleach_ratio_th, ...
                               snr_min, abs_low_min);
    if ~ok
        dbg(end+1,:) = {fpath, 'load_fail', 0, 0, 0, 0}; %#ok<AGROW>
        continue;
    end

    % keep only the valid ROIs of the file (not bleaching and passing quality)
    x_raw = R.mu_low_raw;  y_raw = R.mu_high_raw;
    x_rel = R.mu_low_rel;  y_rel = R.mu_high_rel;

    % apply the histogram clip
    if ~isempty(clip_raw)
        keep = x_raw>=clip_raw(1) & x_raw<=clip_raw(2) & y_raw>=clip_raw(1) & y_raw<=clip_raw(2);
        x_raw = x_raw(keep); y_raw = y_raw(keep);
    end
    if ~isempty(clip_rel)
        keep = x_rel>=clip_rel(1) & x_rel<=clip_rel(2) & y_rel>=clip_rel(1) & y_rel<=clip_rel(2);
        x_rel = x_rel(keep); y_rel = y_rel(keep);
    end

    X_raw = [X_raw; x_raw];   Y_raw = [Y_raw; y_raw]; %#ok<AGROW>
    X_rel = [X_rel; x_rel];   Y_rel = [Y_rel; y_rel]; %#ok<AGROW>

    % accumulate the per-ROI metric table
    nadd = numel(R.roi);
    for i = 1:nadd
        rows(end+1,:) = {fpath, R.roi(i), R.nFrame, ...
                         R.mu_low_raw(i), R.mu_high_raw(i), ...
                         R.mu_low_rel(i), R.mu_high_rel(i), ...
                         R.bleach_low(i), R.bleach_high(i), ...
                         R.snr_low(i), R.base_low(i), R.base_high(i)}; %#ok<AGROW>
    end

    dbg(end+1,:) = {fpath, 'ok', R.nROI, R.nKeep, R.nBleachDrop, R.nQualDrop}; %#ok<AGROW>
end

%% ===== save the CSVs =====
% per-ROI
varNames = {'file','roi','nFrame','mu_low_raw','mu_high_raw','mu_low_rel','mu_high_rel', ...
            'bleach_low','bleach_high','snr_low','baseline_low','baseline_high'};
if isempty(rows)
    T = cell2table(cell(0,numel(varNames)),'VariableNames',varNames);
else
    T = cell2table(rows,'VariableNames',varNames);
end
writetable(T, fullfile(csvDir,'per_roi_metrics_onefile.csv'));

% debug summary
dbgT = cell2table(dbg,'VariableNames',{'file','status','nROI','nKept','nBleachDropped','nQualityDropped'});
writetable(dbgT, fullfile(csvDir,'debug_summary.csv'));

%% ===== figures and count CSVs =====
% RAW scatter
if ~isempty(X_raw)
    make_scatter(X_raw, Y_raw, equiv_band, 'LOW mean (raw)', 'HIGH mean (raw)', fullfile(figDir,'scatter_raw.png'));
    write_hist_counts([X_raw; Y_raw], nbins_raw, fullfile(csvDir,'raw_all_counts.csv')); % full range, for reference
end
% REL scatter (normalised to LOW = 1)
if ~isempty(X_rel)
    make_scatter(X_rel, Y_rel, equiv_band, 'LOW mean (rel, LOW=1)', 'HIGH mean (rel, LOW=1)', fullfile(figDir,'scatter_rel.png'));
    write_hist_counts([X_rel; Y_rel], nbins_rel, fullfile(csvDir,'rel_all_counts.csv'));
end

% histograms (LOW and HIGH, raw and rel)
if ~isempty(X_raw)
    make_overlay_hist(X_raw, Y_raw, nbins_raw, 'Sgnl (raw)', fullfile(figDir,'hist_raw_low_vs_high.png'));
    writematrix(X_raw, fullfile(csvDir,'LOW_raw_values.csv'));
    writematrix(Y_raw, fullfile(csvDir,'HIGH_raw_values.csv'));
end
if ~isempty(X_rel)
    make_overlay_hist(X_rel, Y_rel, nbins_rel, 'Relative (LOW=1)', fullfile(figDir,'hist_rel_low_vs_high.png'));
    writematrix(X_rel, fullfile(csvDir,'LOW_rel_values.csv'));
    writematrix(Y_rel, fullfile(csvDir,'HIGH_rel_values.csv'));
end

fprintf('Done. Results in:\n  %s\n', outDir);
end

%% ================= internal functions =================
function [ok, R] = analyze_one_file(fluorMat, lowFrames, highFrames, baselineFrames, ...
                                    bleach_frac_win, bleach_burnin, bleach_ratio_th, ...
                                    snr_min, abs_low_min)
% read Sgnl from Fluor.mat, orient it as ROI x Frame, and compute the per-window mean, quality and bleach flags

ok = false; R = struct;
try
    D = load(fluorMat);
catch ME
    warning('Load failed: %s (%s)', fluorMat, ME.message);
    return;
end
if ~isfield(D,'Sgnl') && ~isfield(D,'Signal')
    warning('No Sgnl/Signal in %s', fluorMat); return;
end
S = []; if isfield(D,'Sgnl'), S = double(D.Sgnl); else, S = double(D.Signal); end

% fix the ROI x Frame orientation: pick the usable one from the high/low frame indices
needMax = max([lowFrames, highFrames]);
[n1,n2] = size(S);
cand = {};
cand{1} = S;
cand{2} = S.';
pick = 1;
for c=1:2
    nf = size(cand{c},2);
    if nf >= needMax
        pick = c; break;
    end
end
S = cand{pick};
[nROI, nFrame] = size(S);

% intersection with the actual indices
Lidx = intersect(lowFrames,  1:nFrame);
Hidx = intersect(highFrames, 1:nFrame);
Bidx = intersect(baselineFrames, 1:nFrame);
if isempty(Lidx) || isempty(Hidx) || isempty(Bidx)
    warning('Frames too short in %s (nFrame=%d).', fluorMat, nFrame); return;
end

% LOW baseline statistics (quality)
muB = mean(S(:,Bidx),2,'omitnan');
sdB = std( S(:,Bidx),0,2,'omitnan');
snr = muB ./ (sdB + eps);
qual = isfinite(muB) & muB > abs_low_min & isfinite(snr) & snr >= snr_min;

% bleaching test per window (early vs late within each window)
[bleL, ~] = win_bleach_flags(S, Lidx, bleach_frac_win, bleach_burnin, bleach_ratio_th);
[bleH, ~] = win_bleach_flags(S, Hidx, bleach_frac_win, bleach_burnin, bleach_ratio_th);

keep = qual & ~bleL & ~bleH;

% mean (raw)
muL = mean(S(:,Lidx),2,'omitnan');
muH = mean(S(:,Hidx),2,'omitnan');

% relative normalisation (LOW baseline = 1)
base = muB; base(~isfinite(base)|base<=0) = NaN;
muL_rel = muL ./ base;
muH_rel = muH ./ base;

% return structure (filtered to the kept ROIs)
roiKeep = find(keep);
R.file        = fluorMat;
R.nROI        = nROI;
R.nFrame      = nFrame;
R.roi         = roiKeep;
R.mu_low_raw  = muL(keep);
R.mu_high_raw = muH(keep);
R.mu_low_rel  = muL_rel(keep);
R.mu_high_rel = muH_rel(keep);
R.bleach_low  = bleL(keep);
R.bleach_high = bleH(keep);
R.snr_low     = snr(keep);
R.base_low    = muB(keep);
R.base_high   = mean(S(:,Hidx),2,'omitnan'); R.base_high = R.base_high(keep);

R.nKeep        = numel(roiKeep);
R.nBleachDrop  = sum(~qual & (bleL | bleH)) + sum(qual & (bleL | bleH));
R.nQualDrop    = sum(~qual);

ok = true;
end

function [is_bleach, ratio] = win_bleach_flags(S, idxWin, frac_win, burnin, ratio_th)
% bleaching is judged from the early/late mean ratio within a window
nF = numel(idxWin);
L  = max(5, round(frac_win * nF));
i0 = idxWin(1) + max(0,burnin);
i0 = min(i0, idxWin(end));
early = i0 : min(idxWin(end), i0+L-1);
late  = max(idxWin(end)-L+1, idxWin(1)) : idxWin(end);

muE = mean(S(:,early),2,'omitnan');
muL = mean(S(:,late), 2,'omitnan');
ratio = muL ./ (muE + eps);
is_bleach = ratio < ratio_th;
end

function make_scatter(x, y, band, xlab, ylab, out_png)
figure('Visible','off');
plot(x, y, 'o'); hold on;
mn = min([x(:);y(:)]); mx = max([x(:);y(:)]);
if ~isfinite(mn), mn=0; end; if ~isfinite(mx), mx=1; end
plot([mn mx],[mn mx],'k--','LineWidth',1);           % y=x
plot([mn mx],[mn*(1-band) mx*(1-band)],':','Color',[.6 .6 .6]); % -band
plot([mn mx],[mn*(1+band) mx*(1+band)],':','Color',[.6 .6 .6]); % +band
xlabel(xlab); ylabel(ylab);
xlim([0 300]); ylim([0 300]);
title(sprintf('Paired in-file LOW vs HIGH (non-bleach), N=%d', numel(x)));
% axis tight; 
% axis equal;
hold off;
saveas(gcf, out_png); close(gcf);
end

function make_overlay_hist(vLOW, vHIGH, nbins, xlab, out_png)
edges = linspace(min([vLOW;vHIGH]), max([vLOW;vHIGH]), nbins+1);
figure('Visible','off'); hold on;
histogram(vLOW,  edges, 'Normalization','probability', 'DisplayStyle','stairs');
histogram(vHIGH, edges, 'Normalization','probability', 'DisplayStyle','stairs');
legend({'LOW','HIGH'},'Location','best');
xlabel(xlab); ylabel('Probability'); title('LOW vs HIGH');
hold off; saveas(gcf, out_png); close(gcf);
end

function write_hist_counts(vals, nbins, out_csv)
vals = vals(:); vals = vals(isfinite(vals));
if isempty(vals), writematrix([], out_csv); return; end
[N, edges] = histcounts(vals, nbins);
centers = edges(1:end-1) + diff(edges)/2;
T = table(centers(:), N(:), 'VariableNames', {'bin_center','count'});
writetable(T, out_csv);
end
