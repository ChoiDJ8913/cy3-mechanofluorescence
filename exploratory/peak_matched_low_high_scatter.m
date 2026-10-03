function peak_matched_low_high_scatter()
% Pairs LOW/HIGH by FOV key, matches peaks (<= tol_px), EXCLUDES bleaching ROIs.
% Outputs: paired_points.csv (+ bleaching ratios), scatter plots, and debug CSVs.

%% ==== Parameters ====
tol_px              = 2.0;    % XY match tolerance (px)
discard_initial     = 0;      % exclude leading frames from the mean
discard_final       = 0;      % exclude trailing frames from the mean
use_file_relative   = true;   % also produce a scatter plot rescaled by the per-file baseline

% quality (as before)
snr_min        = 0.0;
abs_base_min   = 0.0;
baselineFrames = 1:30;

% >>> bleaching filter <<<
bleach_early_frac = 0.10;     % length fraction of the early/late segments
bleach_burnin     = 0;        % ignore the initial burn-in frames
bleach_ratio_th   = 0.80;     % treat late/early < 0.60 as bleaching

equiv_band     = 0.10;        % ±10% equivalence band

%% ==== IO ====
parentDir = uigetdir(pwd,'Select parent folder containing *_Output & *_peak.mat');
if parentDir==0, disp('Cancelled.'); return; end
outDir = fullfile(parentDir,'peak_match_results'); if ~exist(outDir,'dir'), mkdir(outDir); end
csvDir = fullfile(outDir,'csv'); if ~exist(csvDir,'dir'), mkdir(csvDir); end

%% ==== Collect LOW/HIGH peak mats by key ====
lowPk  = dir(fullfile(parentDir,'* low*.record_peak.mat'));
highPk = dir(fullfile(parentDir,'* high*.record_peak.mat'));

lowMap  = containers.Map('KeyType','char','ValueType','char');
highMap = containers.Map('KeyType','char','ValueType','char');
for k=1:numel(lowPk),  lowMap(extract_key(lowPk(k).name))  = fullfile(parentDir,lowPk(k).name); end
for k=1:numel(highPk), highMap(extract_key(highPk(k).name)) = fullfile(parentDir,highPk(k).name); end
keys = intersect(lowMap.keys, highMap.keys);
if isempty(keys), error('No matched LOW/HIGH peak files found under %s', parentDir); end

%% ==== Accumulators ====
rows = {};
x_raw = []; y_raw = []; x_rel = []; y_rel = [];
debug_missing = {}; debug_nomatch = {};
n_bleach_dropped = 0;

for ii = 1:numel(keys)
    key = keys{ii};

    % -- peaks --
    low_xy  = load_peak_xy(lowMap(key));
    high_xy = load_peak_xy(highMap(key));
    if isempty(low_xy) || isempty(high_xy)
        debug_missing(end+1,:) = {key,'peak_xy_empty'}; %#ok<AGROW>
        continue
    end

    % -- Fluor.mat (recursive, non-epi preferred) --
    lowFlu  = find_fluor_file(parentDir, key, 'low');
    highFlu = find_fluor_file(parentDir, key, 'high');
    if isempty(lowFlu) || isempty(highFlu)
        fprintf('[%s] Fluor.mat missing (low/high). Skip.\n', key);
        debug_missing(end+1,:) = {key,'fluor_missing'}; %#ok<AGROW>
        continue
    end

    % -- load Sgnl (+ optional ROI xy) --
    [S_low,  xy_low_F]  = load_sgnl_and_xy(lowFlu);
    [S_high, xy_high_F] = load_sgnl_and_xy(highFlu);
    if isempty(S_low) || isempty(S_high)
        debug_missing(end+1,:) = {key,'Sgnl_missing'}; %#ok<AGROW>
        continue
    end

    % -- quality + bleaching filter per file --
    [keepL, base_med_low,  bleachL]  = quality_mask_bleach( ...
        S_low, baselineFrames, snr_min, abs_base_min, ...
        bleach_early_frac, bleach_burnin, bleach_ratio_th);

    [keepH, base_med_high, bleachH]  = quality_mask_bleach( ...
        S_high, baselineFrames, snr_min, abs_base_min, ...
        bleach_early_frac, bleach_burnin, bleach_ratio_th);

    % -- averaging ranges (for the scatter values) --
    nL = size(S_low,2);  nH = size(S_high,2);
    Lrng = max(1,1+discard_initial) : max(1,nL-discard_final);
    Hrng = max(1,1+discard_initial) : max(1,nH-discard_final);

    % -- peak index -> Sgnl row mapping --
    idxL = map_peak_to_row(low_xy,  xy_low_F,  size(S_low,1));
    idxH = map_peak_to_row(high_xy, xy_high_F, size(S_high,1));

    % -- XY matching (mutual NN + median shift) --
    [pairs, rough_offset, dDiag] = match_xy_sets(low_xy, high_xy, tol_px);
    if isempty(pairs)
        fprintf('[%s] no matches within %.1f px (median NN dist=%.3g)\n', key, tol_px, dDiag.medDist);
        debug_nomatch(end+1,:) = {key, dDiag.nLow, dDiag.nHigh, dDiag.medDist}; %#ok<AGROW>
        continue
    end

    % -- compute means for matched, non-bleaching ROIs --
    for p = 1:size(pairs,1)
        iL = idxL(pairs(p,1)); iH = idxH(pairs(p,2));
        if isnan(iL) || isnan(iH), continue; end
        iL = int32(iL); iH = int32(iH);

        % drop if either bleaches or fails quality
        if ~(keepL(iL) && keepH(iH)) || (bleachL(iL) || bleachH(iH))
            n_bleach_dropped = n_bleach_dropped + 1;
            continue
        end

        mL = mean(S_low(iL,  Lrng), 'omitnan');
        mH = mean(S_high(iH, Hrng), 'omitnan');
        if ~isfinite(mL) || ~isfinite(mH), continue; end

        x_raw(end+1,1) = mL; %#ok<AGROW>
        y_raw(end+1,1) = mH; %#ok<AGROW>
        if use_file_relative
            x_rel(end+1,1) = mL / max(base_med_low,  eps);
            y_rel(end+1,1) = mH / max(base_med_high, eps);
        end

        rows(end+1,:) = {key, pairs(p,1), pairs(p,2), pairs(p,3), ...
                         mL, mH, ...
                         (use_file_relative)*(mL/max(base_med_low,eps)), ...
                         (use_file_relative)*(mH/max(base_med_high,eps)), ...
                         bleachL(iL), bleachH(iH)}; %#ok<AGROW>
    end
end

%% ==== Save CSVs ====
varNames = {'key','low_peak_idx','high_peak_idx','dist_px', ...
            'mean_low_raw','mean_high_raw','mean_low_relfile','mean_high_relfile', ...
            'bleach_low','bleach_high'};
if ~isempty(rows)
    T = cell2table(rows,'VariableNames',varNames);
else
    T = cell2table(cell(0,numel(varNames)),'VariableNames',varNames);
end
writetable(T, fullfile(csvDir,'paired_points.csv'));

if ~isempty(debug_missing)
    writetable(cell2table(debug_missing,'VariableNames',{'key','reason'}), fullfile(csvDir,'debug_missing.csv'));
end
if ~isempty(debug_nomatch)
    writetable(cell2table(debug_nomatch,'VariableNames',{'key','nLow','nHigh','median_nn_dist'}), fullfile(csvDir,'debug_nomatch.csv'));
end

%% ==== Plots ====
if ~isempty(x_raw)
    make_scatter(x_raw, y_raw, equiv_band, 'LOW mean (raw, non-bleach)', 'HIGH mean (raw, non-bleach)', ...
                 fullfile(outDir,'scatter_raw_nonbleach.png'));
    if use_file_relative && ~isempty(x_rel)
        make_scatter(x_rel, y_rel, equiv_band, 'LOW mean (file-rel, non-bleach)', 'HIGH mean (file-rel, non-bleach)', ...
                     fullfile(outDir,'scatter_relfile_nonbleach.png'));
    end
else
    fprintf('No paired ROI after bleach/quality filters. See debug CSVs in %s\n', csvDir);
end

fprintf('Dropped due to bleaching/quality: %d\n', n_bleach_dropped);
fprintf('Done. Results in: %s\n', outDir);
end

%% ----------------- helpers -----------------
function key = extract_key(fname)
tok = regexp(lower(fname),'^\s*(\d+)','tokens','once');
if ~isempty(tok), key = tok{1}; else, key = regexp(lower(fname),'^[^ _-]+','match','once'); end
end

function xy = load_peak_xy(matpath)
xy = [];
try S = load(matpath); catch, return; end
if isfield(S,'Peaks'), v = S.Peaks; else, v = []; end
if isempty(v)
    fns = fieldnames(S);
    for i=1:numel(fns)
        vv = S.(fns{i});
        if isnumeric(vv) && ismatrix(vv)
            if size(vv,2)==2, v = vv; break; end
            if size(vv,1)==2, v = vv.'; break; end
        end
    end
end
if ~isempty(v) && isnumeric(v), xy = double(reshape(v,[],2)); end
end

function fluorMat = find_fluor_file(parent, key, tag)
cand = dir(fullfile(parent, sprintf('%s*%s*record_Output*', key, tag)));
names = {cand.name};
prio  = cellfun(@(s) contains(lower(s),' epi.'), names);
[~,ord]=sort(prio); cand=cand(ord);
for c=1:numel(cand)
    base = fullfile(parent, cand(c).name);
    hits = [ dir(fullfile(base,'Fluor.mat')); dir(fullfile(base,'**','Fluor.mat')); ...
             dir(fullfile(base,'fluor.mat')); dir(fullfile(base,'**','fluor.mat')) ];
    if ~isempty(hits)
        fluorMat = fullfile(hits(1).folder, hits(1).name); return
    end
end
fluorMat = '';
end

function [S, xy] = load_sgnl_and_xy(fluorMat)
S=[]; xy=[];
try D=load(fluorMat); catch, return; end
if isfield(D,'Sgnl'), S=double(D.Sgnl);
elseif isfield(D,'Signal'), S=double(D.Signal); else, return; end
cands={'Peaks','XY','coords','centers','roiXY'};
for i=1:numel(cands)
    if isfield(D,cands{i})
        v=D.(cands{i});
        if isnumeric(v)&&ismatrix(v)
            if size(v,2)==2, xy=double(v); break; end
            if size(v,1)==2, xy=double(v.'); break; end
        end
    end
end
end

function [keep, base_med, is_bleach] = quality_mask_bleach(S, baseIdx, snr_min, abs_min, early_frac, burnin, ratio_th)
% base quality (SNR/brightness) + bleaching test
nF = size(S,2);
idx = intersect(baseIdx,1:nF); if isempty(idx), idx=1:min(30,nF); end
mu = mean(S(:,idx),2,'omitnan'); sd = std(S(:,idx),0,2,'omitnan');
snr = mu ./ (sd + eps);
keep = isfinite(mu) & mu>abs_min & isfinite(snr) & snr>=snr_min;
base_med = median(mu(keep),'omitnan'); if ~isfinite(base_med) || base_med<=0, base_med = mean(mu(keep),'omitnan'); end

% bleaching: early vs late
L = max(5, round(early_frac*nF));
i0 = min(nF, 1+max(0,burnin));
early_idx = i0 : min(nF, i0+L-1);
late_idx  = max(1, nF-L+1) : nF;
mu_early = mean(S(:,early_idx),2,'omitnan');
mu_late  = mean(S(:,late_idx), 2,'omitnan');
ratio    = mu_late ./ (mu_early + eps);
is_bleach = ratio < ratio_th;

% the final keep does not yet exclude bleaching (returned separately so both sides of a pair can be checked)
end

function idx_row = map_peak_to_row(xy_peak, xy_fluor, nRows)
if ~isempty(xy_fluor) && size(xy_fluor,1)==nRows
    kd = createns(xy_fluor,'NSMethod','kdtree'); %#ok<CREATENS>
    [j,d] = knnsearch(kd, xy_peak, 'K',1);
    idx_row = nan(size(xy_peak,1),1); idx_row(d<=1.0) = j(d<=1.0);
else
    m = min(size(xy_peak,1), nRows); idx_row = (1:m).';
    if numel(idx_row) < size(xy_peak,1), idx_row(end+1:size(xy_peak,1)) = NaN; end
end
end

function [pairs, rough_offset, diagOut] = match_xy_sets(low_xy, high_xy, tol_px)
if isempty(low_xy) || isempty(high_xy)
    pairs=[]; rough_offset=[0 0]; diagOut=struct('nLow',0,'nHigh',0,'medDist',NaN); return
end
MdlH = createns(high_xy,'NSMethod','kdtree'); %#ok<CREATENS>
[j1,d1] = knnsearch(MdlH, low_xy, 'K',1);
rough_offset = median(high_xy(j1,:) - low_xy, 1);

low_al = low_xy + rough_offset;
MdlH2 = createns(high_xy,'NSMethod','kdtree'); %#ok<CREATENS>
[jH,dLH] = knnsearch(MdlH2, low_al, 'K',1);
MdlL2 = createns(low_al,'NSMethod','kdtree'); %#ok<CREATENS>
[iL,dHL] = knnsearch(MdlL2, high_xy, 'K',1);

pairs = [];
for i=1:size(low_xy,1)
    j = jH(i); d = dLH(i);
    if d <= tol_px && iL(j)==i && dHL(j) <= tol_px
        pairs(end+1,:) = [i, j, d]; %#ok<AGROW>
    end
end
diagOut = struct('nLow',size(low_xy,1),'nHigh',size(high_xy,1),'medDist',median(dLH));
end

function make_scatter(x,y,band,xlab,ylab,outpng)
figure('Visible','off'); plot(x,y,'o'); hold on;
mn = min([x(:);y(:)]); mx = max([x(:);y(:)]); if ~isfinite(mn), mn=0; end; if ~isfinite(mx), mx=1; end
plot([mn mx],[mn mx],'k--','LineWidth',1);
plot([mn mx],[mn*(1-band) mx*(1-band)],':','Color',[.6 .6 .6]);
plot([mn mx],[mn*(1+band) mx*(1+band)],':','Color',[.6 .6 .6]);
xlabel(xlab); ylabel(ylab);
title(sprintf('Paired molecules (non-bleach, N=%d)',numel(x)));
axis tight; axis equal; hold off; saveas(gcf,outpng); close;
end
