function MTFluorQC_GUI()
% MTFluorQC_GUI (UI-only, Pick List workflow)
% - Session-wide pick ledger (fileKey -> ROIs, first-added timestamps)
% - UI shows picks for CURRENT file only
% - Saves:
%   (1) per_file_selected_rois.csv
%   (2) per_roi_trace_table.csv        (ONLY LOW/HIGH frames; selected ROIs)
%   (3) per_file_frame_table.csv       (force/mag/mask/segment; once per file per session)

state = struct();

state.datasetId = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));

state.parentDir = '';
state.targetMatName = 'Fluor.mat';
state.sgnlVarName = 'Sgnl';

state.forcePattern = '*record_force*.dat';
state.magPattern = '*record_magnet_position*.dat';

state.params = defaultParams();
state.paramsHash = computeParamsHash(state.params);

state.files = struct([]);
state.currIdx = 0;

state.curr = struct();
state.curr.folder = '';
state.curr.fluorPath = '';
state.curr.forcePath = '';
state.curr.magPath = '';

state.curr.Sgnl = [];
state.curr.force = [];
state.curr.magpos = [];
state.curr.maskExcluded = [];
state.curr.segments = struct([]);
state.curr.segLow = 0;
state.curr.segHigh = 0;
state.curr.roiMetrics = table();

state.curr.selectedMetricRows = [];

% --- Pick ledger (session-wide) ---
% key: fileKey = [folder filesep Fluor.mat] (relative to parentDir)
% value: struct with fields:
%   rois : uint16 column vector
%   ts   : double datenum column vector (first-added only)
state.pickMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

% per-file meta snapshot (updated when file is active)
% value: struct with fields:
%   lowFrames, highFrames  (uint32)
%   lowStr, highStr        (char)
%   forceLow, forceHigh    (double)
%   segLow, segHigh        (double)
%   nExcluded              (double)
%   paramsHash             (char)
state.pickMetaMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

% saving de-dup keys for per_file_frame_table
state.savedFileFrameKeys = {};

state.outDir = '';
state.outSelCsv = '';
state.outTraceCsv = '';
state.outFileFrameCsv = '';

state.ui = buildUI();

guidata(state.ui.fig, state);

pickParentDirOrExit(state.ui.fig);
initializeApp(state.ui.fig);

end

function p = defaultParams()
p = struct();
p.F_thr = 0.01;
p.Z_thr = 1e-4;
p.pad = 5;
p.minPlateauLen = 10;
end

function ui = buildUI()
ui = struct();

ui.fig = uifigure('Name', 'MT Fluor QC GUI (Pick List)', 'Position', [50 50 1350 820]);

gl = uigridlayout(ui.fig, [2 2]);
gl.RowHeight = {340, '1x'};
gl.ColumnWidth = {'1.25x', '1x'};
gl.Padding = [8 8 8 8];
gl.RowSpacing = 8;
gl.ColumnSpacing = 8;

ui.axForce = uiaxes(gl);
ui.axForce.Layout.Row = 1;
ui.axForce.Layout.Column = 1;
title(ui.axForce, 'Force / Magnet Position');
xlabel(ui.axForce, 'Frame');
ylabel(ui.axForce, 'Force (pN)');
grid(ui.axForce, 'on');

ui.axTrace = uiaxes(gl);
ui.axTrace.Layout.Row = 2;
ui.axTrace.Layout.Column = 1;
title(ui.axTrace, 'ROI Trace (Sgnl)');
xlabel(ui.axTrace, 'Frame');
ylabel(ui.axTrace, 'Sgnl');
grid(ui.axTrace, 'on');

right = uigridlayout(gl, [3 1]);
right.Layout.Row = [1 2];
right.Layout.Column = 2;
right.RowHeight = {260, 140, '1x'};
right.ColumnWidth = {'1x'};
right.RowSpacing = 8;
right.Padding = [0 0 0 0];

% ---- Controls ----
ctrl = uigridlayout(right, [9 6]);
ctrl.Layout.Row = 1;
ctrl.Layout.Column = 1;
ctrl.RowHeight = {26, 26, 26, 26, 26, 26, 26, 26, 26};
ctrl.ColumnWidth = {120, 120, 120, 120, 120, '1x'};
ctrl.ColumnSpacing = 6;
ctrl.RowSpacing = 6;
ctrl.Padding = [0 0 0 0];

ui.btnSelectDir = uibutton(ctrl, 'Text', 'Select ParentDir');
ui.btnSelectDir.Layout.Row = 1;
ui.btnSelectDir.Layout.Column = [1 2];
ui.btnSelectDir.ButtonPushedFcn = @onSelectDir;

ui.lblDir = uilabel(ctrl, 'Text', '(no dir)');
ui.lblDir.Layout.Row = 1;
ui.lblDir.Layout.Column = [3 6];
ui.lblDir.Interpreter = 'none';

ui.btnPrev = uibutton(ctrl, 'Text', 'Prev File');
ui.btnPrev.Layout.Row = 2;
ui.btnPrev.Layout.Column = 1;
ui.btnPrev.ButtonPushedFcn = @onPrevFile;

ui.btnNext = uibutton(ctrl, 'Text', 'Next File');
ui.btnNext.Layout.Row = 2;
ui.btnNext.Layout.Column = 2;
ui.btnNext.ButtonPushedFcn = @onNextFile;

ui.lblFile = uilabel(ctrl, 'Text', '(no file)');
ui.lblFile.Layout.Row = 2;
ui.lblFile.Layout.Column = [3 6];
ui.lblFile.Interpreter = 'none';

ui.ddLow = uidropdown(ctrl, 'Items', {'(none)'});
ui.ddLow.Layout.Row = 3;
ui.ddLow.Layout.Column = [1 3];
ui.ddLow.ValueChangedFcn = @onSegChanged;

ui.ddHigh = uidropdown(ctrl, 'Items', {'(none)'});
ui.ddHigh.Layout.Row = 3;
ui.ddHigh.Layout.Column = [4 6];
ui.ddHigh.ValueChangedFcn = @onSegChanged;

ui.lblLow = uilabel(ctrl, 'Text', 'LOW segment');
ui.lblLow.Layout.Row = 4;
ui.lblLow.Layout.Column = [1 3];

ui.lblHigh = uilabel(ctrl, 'Text', 'HIGH segment');
ui.lblHigh.Layout.Row = 4;
ui.lblHigh.Layout.Column = [4 6];

ui.spFthr = uispinner(ctrl, 'Limits', [1e-6 5], 'Value', 0.01, 'Step', 0.005);
ui.spFthr.Layout.Row = 5;
ui.spFthr.Layout.Column = 1;
ui.spFthr.ValueChangedFcn = @onParamsChanged;

ui.lblFthr = uilabel(ctrl, 'Text', 'F_thr (ΔF)');
ui.lblFthr.Layout.Row = 5;
ui.lblFthr.Layout.Column = 2;

ui.spZthr = uispinner(ctrl, 'Limits', [1e-8 1], 'Value', 1e-4, 'Step', 1e-4);
ui.spZthr.Layout.Row = 5;
ui.spZthr.Layout.Column = 3;
ui.spZthr.ValueChangedFcn = @onParamsChanged;

ui.lblZthr = uilabel(ctrl, 'Text', 'Z_thr (ΔZ)');
ui.lblZthr.Layout.Row = 5;
ui.lblZthr.Layout.Column = 4;

ui.spPad = uispinner(ctrl, 'Limits', [0 50], 'Value', 5, 'Step', 1);
ui.spPad.Layout.Row = 5;
ui.spPad.Layout.Column = 5;
ui.spPad.ValueChangedFcn = @onParamsChanged;

ui.lblPad = uilabel(ctrl, 'Text', 'pad');
ui.lblPad.Layout.Row = 5;
ui.lblPad.Layout.Column = 6;

ui.spMinLen = uispinner(ctrl, 'Limits', [2 200], 'Value', 10, 'Step', 1);
ui.spMinLen.Layout.Row = 6;
ui.spMinLen.Layout.Column = 1;
ui.spMinLen.ValueChangedFcn = @onParamsChanged;

ui.lblMinLen = uilabel(ctrl, 'Text', 'min plateau len');
ui.lblMinLen.Layout.Row = 6;
ui.lblMinLen.Layout.Column = [2 3];

ui.btnRecompute = uibutton(ctrl, 'Text', 'Recompute');
ui.btnRecompute.Layout.Row = 6;
ui.btnRecompute.Layout.Column = [4 6];
ui.btnRecompute.ButtonPushedFcn = @onRecompute;

ui.btnAdd = uibutton(ctrl, 'Text', 'Add Selected');
ui.btnAdd.Layout.Row = 7;
ui.btnAdd.Layout.Column = [1 2];
ui.btnAdd.ButtonPushedFcn = @onAddSelected;

ui.btnRemove = uibutton(ctrl, 'Text', 'Remove Selected');
ui.btnRemove.Layout.Row = 7;
ui.btnRemove.Layout.Column = [3 4];
ui.btnRemove.ButtonPushedFcn = @onRemoveSelected;

ui.btnClear = uibutton(ctrl, 'Text', 'Clear This File Picks');
ui.btnClear.Layout.Row = 7;
ui.btnClear.Layout.Column = [5 6];
ui.btnClear.ButtonPushedFcn = @onClearThisFile;

ui.btnSave = uibutton(ctrl, 'Text', 'Save CSVs');
ui.btnSave.Layout.Row = 8;
ui.btnSave.Layout.Column = [1 3];
ui.btnSave.ButtonPushedFcn = @onSave;

ui.btnOpenOut = uibutton(ctrl, 'Text', 'Open OutDir');
ui.btnOpenOut.Layout.Row = 8;
ui.btnOpenOut.Layout.Column = [4 5];
ui.btnOpenOut.ButtonPushedFcn = @onOpenOutDir;

ui.lblStatus = uilabel(ctrl, 'Text', '');
ui.lblStatus.Layout.Row = 9;
ui.lblStatus.Layout.Column = [1 6];
ui.lblStatus.Interpreter = 'none';

% ---- Pick list table (current file only) ----
ui.tblPick = uitable(right);
ui.tblPick.Layout.Row = 2;
ui.tblPick.Layout.Column = 1;
ui.tblPick.ColumnSortable = true;
ui.tblPick.Multiselect = 'on';
ui.tblPick.CellSelectionCallback = @onPickTableSelect;

% ---- Metrics table (current file) ----
ui.tblMetric = uitable(right);
ui.tblMetric.Layout.Row = 3;
ui.tblMetric.Layout.Column = 1;
ui.tblMetric.ColumnSortable = true;
ui.tblMetric.Multiselect = 'on';
ui.tblMetric.CellSelectionCallback = @onMetricTableSelect;

end

function pickParentDirOrExit(fig)
state = guidata(fig);

p = uigetdir(pwd, 'Select parent folder containing subfolders with Fluor.mat');
if p == 0
    delete(fig);
    return;
end

state.parentDir = p;

guidata(fig, state);

end

function initializeApp(fig)
if ~isvalid(fig)
    return;
end

state = guidata(fig);

state = setOutputPaths(state);
state = refreshFileList(state);

state.currIdx = 0;
state.savedFileFrameKeys = {};

guidata(fig, state);

updateHeader(fig);

if ~isempty(state.files)
    state.currIdx = 1;
    guidata(fig, state);
    loadCurrentFile(fig);
end

end

function state = setOutputPaths(state)
state.outDir = fullfile(state.parentDir, 'QC_outputs');
if ~exist(state.outDir, 'dir')
    mkdir(state.outDir);
end

state.outSelCsv = fullfile(state.outDir, 'per_file_selected_rois.csv');
state.outTraceCsv = fullfile(state.outDir, 'per_roi_trace_table.csv');
state.outFileFrameCsv = fullfile(state.outDir, 'per_file_frame_table.csv');

end

function state = refreshFileList(state)
D = dir(state.parentDir);

isDir = [D.isdir];
names = {D.name};
isDot = strcmp(names, '.') | strcmp(names, '..');
subs = D(isDir & ~isDot);

files = struct([]);
n = 0;

for k = 1:numel(subs)
    folder = subs(k).name;

    fluorPath = fullfile(state.parentDir, folder, state.targetMatName);
    if ~exist(fluorPath, 'file')
        continue;
    end

    dForce = dir(fullfile(state.parentDir, folder, state.forcePattern));
    dMag = dir(fullfile(state.parentDir, folder, state.magPattern));

    if isempty(dForce)
        continue;
    end

    if isempty(dMag)
        continue;
    end

    n = n + 1;
    files(n).folder = folder;
    files(n).fluorPath = fluorPath;
    files(n).forcePath = fullfile(dForce(1).folder, dForce(1).name);
    files(n).magPath = fullfile(dMag(1).folder, dMag(1).name);
end

state.files = files;

end

function updateHeader(fig)
state = guidata(fig);

state.ui.lblDir.Text = state.parentDir;

if state.currIdx >= 1 && state.currIdx <= numel(state.files)
    f = state.files(state.currIdx);
    state.ui.lblFile.Text = sprintf('[%d/%d] %s', state.currIdx, numel(state.files), f.folder);
else
    state.ui.lblFile.Text = '(no file)';
end

[filePickCount, sessionPickCount] = countPicks(state);
state.ui.lblStatus.Text = sprintf('This file picked: %d | Session picked: %d | ParamsHash: %s', ...
    filePickCount, sessionPickCount, state.paramsHash);

guidata(fig, state);

end

function [filePickCount, sessionPickCount] = countPicks(state)
filePickCount = 0;
sessionPickCount = 0;

keys = state.pickMap.keys;
for i = 1:numel(keys)
    v = state.pickMap(keys{i});
    sessionPickCount = sessionPickCount + numel(v.rois);
end

fileKey = currentFileKey(state);
if ~isempty(fileKey)
    if ~isempty(fileKey)
        if isKey(state.pickMap, fileKey)
            v = state.pickMap(fileKey);

            roi = double(v.rois(:));
            ts = v.ts(:);

            tsChar = cell(numel(ts), 1);
            for k = 1:numel(ts)
                tsChar{k} = datestr(ts(k), 'yyyy-mm-dd HH:MM:SS');
            end

            Tp = table(roi, tsChar, 'VariableNames', {'roi','selected_ts'});
        end
    end
end

end

function key = currentFileKey(state)
key = '';
if state.currIdx < 1
    return;
end
if state.currIdx > numel(state.files)
    return;
end
folder = state.files(state.currIdx).folder;
key = fullfile(folder, state.targetMatName);
end

function loadCurrentFile(fig)
state = guidata(fig);

if isempty(state.files)
    return;
end

if state.currIdx < 1
    state.currIdx = 1;
end

if state.currIdx > numel(state.files)
    state.currIdx = numel(state.files);
end

f = state.files(state.currIdx);

state.curr.folder = f.folder;
state.curr.fluorPath = f.fluorPath;
state.curr.forcePath = f.forcePath;
state.curr.magPath = f.magPath;

Sgnl = loadSgnl(f.fluorPath, state.sgnlVarName);
force = readVecDat(f.forcePath);
magpos = readVecDat(f.magPath);

nFrame = size(Sgnl, 2);

force = resizeVecToN(force, nFrame);
magpos = resizeVecToN(magpos, nFrame);

state.curr.Sgnl = Sgnl;
state.curr.force = force(:);
state.curr.magpos = magpos(:);

state = syncParamsFromUI(state);
state.paramsHash = computeParamsHash(state.params);

maskExcluded = computeTransitionMask(state.curr.force, state.curr.magpos, state.params.F_thr, state.params.Z_thr, state.params.pad);
state.curr.maskExcluded = maskExcluded;

segments = computeStableSegments(~maskExcluded, state.params.minPlateauLen);
state.curr.segments = segments;

[segLow, segHigh] = defaultLowHighSegments(segments);
state.curr.segLow = segLow;
state.curr.segHigh = segHigh;

state.curr.roiMetrics = computeRoiMetrics(state);

state.curr.selectedMetricRows = [];

state = updatePickMetaForCurrentFile(state);

guidata(fig, state);

populateSegmentDropdowns(fig);
renderAll(fig);

end

function state = syncParamsFromUI(state)
state.params.F_thr = state.ui.spFthr.Value;
state.params.Z_thr = state.ui.spZthr.Value;
state.params.pad = round(state.ui.spPad.Value);
state.params.minPlateauLen = round(state.ui.spMinLen.Value);
end

function Sgnl = loadSgnl(fluorPath, varName)
tmp = load(fluorPath, varName);
Sgnl = double(tmp.(varName));

[n1, n2] = size(Sgnl);
if n2 < n1
    Sgnl = Sgnl.';
end

end

function v = readVecDat(path)
if isstring(path)
    path = char(path);
end

fid = fopen(path, 'r');
if fid < 0
    v = [];
    return;
end

c = textscan(fid, '%f', 'CollectOutput', true);
fclose(fid);

v = double(c{1}(:));
end

function v = resizeVecToN(v, n)
v = v(:);

if isempty(v)
    v = nan(n, 1);
    return;
end

if numel(v) >= n
    v = v(1:n);
    return;
end

lastVal = v(end);
v(end+1:n, 1) = lastVal;

end

function mask = computeTransitionMask(force, magpos, F_thr, Z_thr, pad)
n = numel(force);

move = ~isfinite(force(:)) | ~isfinite(magpos(:));

dF = abs(diff(force));
dZ = abs(diff(magpos));

move(2:end) = move(2:end) | (dF > F_thr) | (dZ > Z_thr);

if pad > 0
    idx = find(move);
    for k = 1:numel(idx)
        a = max(1, idx(k) - pad);
        b = min(n, idx(k) + pad);
        move(a:b) = true;
    end
end

mask = move;

end

function segs = computeStableSegments(stableMask, minLen)
stableMask = stableMask(:);

d = diff([false; stableMask; false]);
starts = find(d == 1);
ends = find(d == -1) - 1;

keep = (ends - starts + 1) >= minLen;
starts = starts(keep);
ends = ends(keep);

segs = struct('start', {}, 'stop', {}, 'len', {});
for i = 1:numel(starts)
    segs(i).start = starts(i);
    segs(i).stop = ends(i);
    segs(i).len = ends(i) - starts(i) + 1;
end

end

function [iLow, iHigh] = defaultLowHighSegments(segs)
iLow = 0;
iHigh = 0;

if isempty(segs)
    return;
end

iLow = 1;
iHigh = numel(segs);

end

function populateSegmentDropdowns(fig)
state = guidata(fig);

items = {};
if ~isempty(state.curr.segments)
    for i = 1:numel(state.curr.segments)
        s = state.curr.segments(i);
        items{end+1,1} = sprintf('Seg %d: %d-%d (n=%d)', i, s.start, s.stop, s.len);
    end
else
    items = {'(none)'};
end

state.ui.ddLow.Items = items;
state.ui.ddHigh.Items = items;

if state.curr.segLow >= 1 && state.curr.segLow <= numel(state.curr.segments)
    state.ui.ddLow.Value = items{state.curr.segLow};
else
    state.ui.ddLow.Value = items{1};
end

if state.curr.segHigh >= 1 && state.curr.segHigh <= numel(state.curr.segments)
    state.ui.ddHigh.Value = items{state.curr.segHigh};
else
    state.ui.ddHigh.Value = items{1};
end

guidata(fig, state);

end

function T = computeRoiMetrics(state)
S = state.curr.Sgnl;
maskEx = state.curr.maskExcluded(:);

nROI = size(S, 1);
nFrame = size(S, 2);

lowIdx = getSegmentFrames(state, state.curr.segLow);
highIdx = getSegmentFrames(state, state.curr.segHigh);

lowIdx = lowIdx(~maskEx(lowIdx));
highIdx = highIdx(~maskEx(highIdx));

muL = mean(S(:, lowIdx), 2, 'omitnan');
sdL = std(S(:, lowIdx), 0, 2, 'omitnan');
muH = mean(S(:, highIdx), 2, 'omitnan');
sdH = std(S(:, highIdx), 0, 2, 'omitnan');

snrL = muL ./ (sdL + eps);

firstN = max(5, round(0.1 * nFrame));
lastN = firstN;

muFirst = mean(S(:, 1:firstN), 2, 'omitnan');
muLast = mean(S(:, max(1, nFrame-lastN+1):nFrame), 2, 'omitnan');
bleachRatio = muLast ./ (muFirst + eps);

roi = (1:nROI).';

T = table();
T.roi = roi;
T.mu_low_abs = muL;
T.mu_high_abs = muH;
T.ratio_abs = muH ./ max(muL, eps);
T.snr_low = snrL;
T.bleach_ratio = bleachRatio;
T.nExcluded = repmat(sum(maskEx), nROI, 1);

T.low_frames_used = repmat({framesToStr(lowIdx)}, nROI, 1);
T.high_frames_used = repmat({framesToStr(highIdx)}, nROI, 1);

end

function idx = getSegmentFrames(state, segIdx)
idx = zeros(0,1);

if isempty(state.curr.segments)
    return;
end

if segIdx < 1
    return;
end

if segIdx > numel(state.curr.segments)
    return;
end

s = state.curr.segments(segIdx);
idx = (s.start:s.stop).';

end

function s = framesToStr(idx)
if isempty(idx)
    s = '';
    return;
end

idx = idx(:);
s = sprintf('%d-%d (n=%d)', idx(1), idx(end), numel(idx));

end

function state = updatePickMetaForCurrentFile(state)
fileKey = currentFileKey(state);
if isempty(fileKey)
    return;
end

lowIdx = getSegmentFrames(state, state.curr.segLow);
highIdx = getSegmentFrames(state, state.curr.segHigh);

maskEx = state.curr.maskExcluded(:);
lowIdx = lowIdx(~maskEx(lowIdx));
highIdx = highIdx(~maskEx(highIdx));

meta = struct();
meta.lowFrames = uint32(lowIdx(:));
meta.highFrames = uint32(highIdx(:));
meta.lowStr = framesToStr(lowIdx);
meta.highStr = framesToStr(highIdx);

if isempty(lowIdx)
    meta.forceLow = nan;
else
    meta.forceLow = mean(state.curr.force(lowIdx), 'omitnan');
end

if isempty(highIdx)
    meta.forceHigh = nan;
else
    meta.forceHigh = mean(state.curr.force(highIdx), 'omitnan');
end

meta.segLow = state.curr.segLow;
meta.segHigh = state.curr.segHigh;
meta.nExcluded = sum(maskEx);
meta.paramsHash = state.paramsHash;

state.pickMetaMap(fileKey) = meta;

end

function renderAll(fig)
state = guidata(fig);

renderForceAxes(state.ui.axForce, state.curr.force, state.curr.magpos, state.curr.maskExcluded);
renderPickTable(fig);
renderMetricTable(fig);

updateHeader(fig);

end

function renderForceAxes(ax, force, magpos, maskEx)
cla(ax);

n = numel(force);
x = (1:n).';

yyaxis(ax, 'left');
plot(ax, x, force, '-');
ylabel(ax, 'Force (pN)');

hold(ax, 'on');

yyaxis(ax, 'right');
plot(ax, x, magpos, '-');
ylabel(ax, 'MagPos');

shadeExcluded(ax, maskEx);

title(ax, 'Force / Magnet Position (excluded shaded)');
xlabel(ax, 'Frame');
grid(ax, 'on');

hold(ax, 'off');

end

function shadeExcluded(ax, maskEx)
maskEx = maskEx(:);

if ~any(maskEx)
    return;
end

yl = ax.YLim;

d = diff([false; maskEx; false]);
starts = find(d == 1);
ends = find(d == -1) - 1;

for i = 1:numel(starts)
    a = starts(i);
    b = ends(i);
    patch(ax, [a b b a], [yl(1) yl(1) yl(2) yl(2)], [0.9 0.9 0.9], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.3);
end

end

function renderMetricTable(fig)
state = guidata(fig);

T = state.curr.roiMetrics;
state.ui.tblMetric.Data = T;
state.ui.tblMetric.ColumnName = T.Properties.VariableNames;

guidata(fig, state);

end

function renderPickTable(fig)
state = guidata(fig);

fileKey = currentFileKey(state);

Tp = table(zeros(0,1), cell(0,1), 'VariableNames', {'roi','selected_ts'});

if ~isempty(fileKey)
    if ~isempty(fileKey)
        if isKey(state.pickMap, fileKey)
            v = state.pickMap(fileKey);

            roi = double(v.rois(:));
            ts = v.ts(:);

            tsChar = cell(numel(ts), 1);
            for k = 1:numel(ts)
                tsChar{k} = datestr(ts(k), 'yyyy-mm-dd HH:MM:SS');
            end

            Tp = table(roi, tsChar, 'VariableNames', {'roi','selected_ts'});
        end
    end
end

state.ui.tblPick.Data = Tp;
state.ui.tblPick.ColumnName = {'roi', 'selected_ts'};

guidata(fig, state);

end

function renderTraceAxes(ax, S, maskEx, roi)
cla(ax);

if isempty(S)
    return;
end

nFrame = size(S, 2);
x = 1:nFrame;

y = S(roi, :);
plot(ax, x, y, '-');

hold(ax, 'on');
shadeExcluded(ax, maskEx);
hold(ax, 'off');

title(ax, sprintf('ROI %d trace', roi));
xlabel(ax, 'Frame');
ylabel(ax, 'Sgnl');
grid(ax, 'on');

end

function paramsHash = computeParamsHash(params)
txt = sprintf('F=%g|Z=%g|pad=%d|minLen=%d', params.F_thr, params.Z_thr, params.pad, params.minPlateauLen);
paramsHash = sha1Text(txt);
end

function h = sha1Text(txt)
md = java.security.MessageDigest.getInstance('SHA-1');
md.update(uint8(txt));
hash = typecast(md.digest, 'uint8');
h = lower(reshape(dec2hex(hash).', 1, []));
end

% ---------------- Callbacks ----------------

function onSelectDir(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

p = uigetdir(state.parentDir, 'Select parent folder containing subfolders with Fluor.mat');
if p == 0
    return;
end

state.parentDir = p;
state = setOutputPaths(state);
state = refreshFileList(state);

state.currIdx = 0;

guidata(fig, state);

updateHeader(fig);

if ~isempty(state.files)
    state.currIdx = 1;
    guidata(fig, state);
    loadCurrentFile(fig);
end

end

function onPrevFile(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

if isempty(state.files)
    return;
end

state.currIdx = max(1, state.currIdx - 1);
guidata(fig, state);

loadCurrentFile(fig);

end

function onNextFile(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

if isempty(state.files)
    return;
end

state.currIdx = min(numel(state.files), state.currIdx + 1);
guidata(fig, state);

loadCurrentFile(fig);

end

function onSegChanged(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

if isempty(state.curr.segments)
    return;
end

lowSel = find(strcmp(state.ui.ddLow.Items, state.ui.ddLow.Value), 1, 'first');
highSel = find(strcmp(state.ui.ddHigh.Items, state.ui.ddHigh.Value), 1, 'first');

if isempty(lowSel)
    lowSel = state.curr.segLow;
end

if isempty(highSel)
    highSel = state.curr.segHigh;
end

state.curr.segLow = lowSel;
state.curr.segHigh = highSel;

state.curr.roiMetrics = computeRoiMetrics(state);
state = updatePickMetaForCurrentFile(state);

guidata(fig, state);

renderAll(fig);

end

function onParamsChanged(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

state = syncParamsFromUI(state);
state.paramsHash = computeParamsHash(state.params);

guidata(fig, state);

updateHeader(fig);

end

function onRecompute(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

if isempty(state.curr.force)
    return;
end

state = syncParamsFromUI(state);
state.paramsHash = computeParamsHash(state.params);

maskExcluded = computeTransitionMask(state.curr.force, state.curr.magpos, state.params.F_thr, state.params.Z_thr, state.params.pad);
state.curr.maskExcluded = maskExcluded;

segments = computeStableSegments(~maskExcluded, state.params.minPlateauLen);
state.curr.segments = segments;

[segLow, segHigh] = defaultLowHighSegments(segments);
state.curr.segLow = segLow;
state.curr.segHigh = segHigh;

state.curr.roiMetrics = computeRoiMetrics(state);
state = updatePickMetaForCurrentFile(state);

guidata(fig, state);

populateSegmentDropdowns(fig);
renderAll(fig);

end

function onMetricTableSelect(src, evt)
fig = ancestor(src, 'figure');
state = guidata(fig);

state.curr.selectedMetricRows = [];

if isempty(evt.Indices)
    guidata(fig, state);
    return;
end

rows = unique(evt.Indices(:, 1));
rows = rows(:);
state.curr.selectedMetricRows = rows;

guidata(fig, state);

T = state.ui.tblMetric.Data;
if isempty(T)
    return;
end

r0 = rows(1);
if r0 < 1
    return;
end

if r0 > height(T)
    return;
end

roi = T.roi(r0);
renderTraceAxes(state.ui.axTrace, state.curr.Sgnl, state.curr.maskExcluded, roi);

end

function onPickTableSelect(src, evt)
fig = ancestor(src, 'figure');
state = guidata(fig);

if isempty(evt.Indices)
    return;
end

rows = unique(evt.Indices(:, 1));
rows = rows(:);

Tp = state.ui.tblPick.Data;
if isempty(Tp)
    return;
end

r0 = rows(1);
if r0 < 1
    return;
end

if r0 > height(Tp)
    return;
end

roi = Tp.roi(r0);
renderTraceAxes(state.ui.axTrace, state.curr.Sgnl, state.curr.maskExcluded, roi);

end

function onAddSelected(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

rows = state.curr.selectedMetricRows;
if isempty(rows)
    return;
end

T = state.ui.tblMetric.Data;
if isempty(T)
    return;
end

rows = rows(rows >= 1);
rows = rows(rows <= height(T));

roiSel = unique(uint16(T.roi(rows)));

fileKey = currentFileKey(state);
if isempty(fileKey)
    return;
end

if isKey(state.pickMap, fileKey)
    v = state.pickMap(fileKey);
else
    v = struct();
    v.rois = uint16([]);
    v.ts = [];
end

for i = 1:numel(roiSel)
    roi = roiSel(i);
    if ~any(v.rois == roi)
        v.rois(end+1,1) = roi;
        v.ts(end+1,1) = now; %#ok<AGROW>  % first-add timestamp
    end
end

[~, ord] = sort(double(v.rois));
v.rois = v.rois(ord);
v.ts = v.ts(ord);

state.pickMap(fileKey) = v;

state = updatePickMetaForCurrentFile(state);

guidata(fig, state);

renderPickTable(fig);
updateHeader(fig);

end

function onRemoveSelected(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

rows = state.curr.selectedMetricRows;
if isempty(rows)
    return;
end

T = state.ui.tblMetric.Data;
if isempty(T)
    return;
end

rows = rows(rows >= 1);
rows = rows(rows <= height(T));

roiSel = unique(uint16(T.roi(rows)));

fileKey = currentFileKey(state);
if isempty(fileKey)
    return;
end

if ~isKey(state.pickMap, fileKey)
    return;
end

v = state.pickMap(fileKey);

keepMask = true(size(v.rois));
for i = 1:numel(roiSel)
    keepMask = keepMask & (v.rois ~= roiSel(i));
end

v.rois = v.rois(keepMask);
v.ts = v.ts(keepMask);

state.pickMap(fileKey) = v;

guidata(fig, state);

renderPickTable(fig);
updateHeader(fig);

end

function onClearThisFile(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

fileKey = currentFileKey(state);
if isempty(fileKey)
    return;
end

if isKey(state.pickMap, fileKey)
    remove(state.pickMap, fileKey);
end

guidata(fig, state);

renderPickTable(fig);
updateHeader(fig);

end

function onSave(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

state = setOutputPaths(state);

if isfile(state.outTraceCsv)
    delete(state.outTraceCsv)
end

if isfile(state.outFileFrameCsv)
    delete(state.outFileFrameCsv)
end

state.savedFileFrameKeys = {};

saveTs = datestr(now, 'yyyy-mm-dd HH:MM:SS');

writeSelectedLedger(state, saveTs);
state = writePerFileFrameTables(state, saveTs);
writePerRoiTraceTables(state, saveTs);

guidata(fig, state);

uialert(fig, 'Saved CSVs under QC_outputs.', 'Saved');

end


function writeSelectedLedger(state, saveTs)
keys = state.pickMap.keys;

rows = {};

for i = 1:numel(keys)
    fileKey = keys{i};
    v = state.pickMap(fileKey);

    if isKey(state.pickMetaMap, fileKey)
        meta = state.pickMetaMap(fileKey);
    else
        meta = struct();
        meta.lowStr = '';
        meta.highStr = '';
        meta.forceLow = nan;
        meta.forceHigh = nan;
        meta.paramsHash = state.paramsHash;
    end

    folder = fileparts(fileKey);
    fluorRel = fileKey;

    for k = 1:numel(v.rois)
        roi = double(v.rois(k));
        ts0 = datestr(v.ts(k), 'yyyy-mm-dd HH:MM:SS');

        rows(end+1,:) = { ...
            state.datasetId, ...
            folder, ...
            fluorRel, ...
            roi, ...
            ts0, ...
            meta.paramsHash, ...
            meta.lowStr, ...
            meta.highStr, ...
            meta.forceLow, ...
            meta.forceHigh, ...
            saveTs ...
            }; %#ok<AGROW>
    end
end

Tsel = cell2table(rows, 'VariableNames', { ...
    'dataset_id', 'folder', 'fluor_path_rel', 'roi', 'selected_ts', 'qc_param_hash', ...
    'low_frames_used', 'high_frames_used', 'force_low_pN', 'force_high_pN', 'save_ts' ...
    });

writetable(Tsel, state.outSelCsv);

end

function state = writePerFileFrameTables(state, saveTs)
keys = state.pickMap.keys;

for i = 1:numel(keys)
    fileKey = keys{i};
    if ~isKey(state.pickMetaMap, fileKey)
        continue;
    end
    meta = state.pickMetaMap(fileKey);

    kdup = [state.datasetId '|' fileKey '|' meta.paramsHash];
    if any(strcmp(state.savedFileFrameKeys, kdup))
        continue;
    end

    folder = fileparts(fileKey);
    idx = find(strcmp({state.files.folder}, folder), 1, 'first');
    if isempty(idx)
        continue;
    end

    f = state.files(idx);

    Sgnl = loadSgnl(f.fluorPath, state.sgnlVarName);
    nFrame = size(Sgnl, 2);

    force = resizeVecToN(readVecDat(f.forcePath), nFrame);
    magpos = resizeVecToN(readVecDat(f.magPath), nFrame);

    maskEx = computeTransitionMask(force, magpos, state.params.F_thr, state.params.Z_thr, state.params.pad);

    segment = repmat({'OTHER'}, nFrame, 1);

    lowFrames = double(meta.lowFrames(:));
    highFrames = double(meta.highFrames(:));

    segment(lowFrames) = {'LOW'};
    segment(highFrames) = {'HIGH'};

    frame = (1:nFrame).';

    T = table();
    T.dataset_id = repmat({state.datasetId}, nFrame, 1);
    T.folder = repmat({folder}, nFrame, 1);
    T.fluor_path_rel = repmat({fileKey}, nFrame, 1);
    T.frame = frame;
    T.force_pN = force(:);
    T.magpos = magpos(:);
    T.is_excluded = double(maskEx(:));
    T.segment = segment;
    T.qc_param_hash = repmat({meta.paramsHash}, nFrame, 1);
    T.save_ts = repmat({saveTs}, nFrame, 1);

    if ~isfile(state.outFileFrameCsv)
        writetable(T, state.outFileFrameCsv);
    else
        writetable(T, state.outFileFrameCsv, 'WriteMode', 'append', 'WriteVariableNames', false);
    end

    state.savedFileFrameKeys{end+1,1} = kdup; %#ok<AGROW>
end

end

function writePerRoiTraceTables(state, saveTs)
keys = state.pickMap.keys;

for i = 1:numel(keys)
    fileKey = keys{i};
    v = state.pickMap(fileKey);

    if isempty(v.rois)
        continue;
    end

    if ~isKey(state.pickMetaMap, fileKey)
        continue;
    end
    meta = state.pickMetaMap(fileKey);

    folder = fileparts(fileKey);
    idx = find(strcmp({state.files.folder}, folder), 1, 'first');
    if isempty(idx)
        continue;
    end

    f = state.files(idx);

    Sgnl = loadSgnl(f.fluorPath, state.sgnlVarName);
    nFrame = size(Sgnl, 2);

    lowFrames = double(meta.lowFrames(:));
    highFrames = double(meta.highFrames(:));

    if isempty(lowFrames) && isempty(highFrames)
        continue;
    end

    if ~isfile(state.outTraceCsv)
        writeTraceHeader(state.outTraceCsv);
    end

    for k = 1:numel(v.rois)
        roi = double(v.rois(k));

        writeTraceBlock(state.outTraceCsv, state.datasetId, folder, fileKey, roi, ...
            lowFrames, highFrames, Sgnl(roi, :), meta.paramsHash, saveTs);
    end
end

end

function writeTraceHeader(path)
fid = fopen(path, 'w');
fprintf(fid, 'dataset_id,folder,fluor_path_rel,roi,frame,segment,sgnl,qc_param_hash,save_ts\n');
fclose(fid);
end

function writeTraceBlock(path, datasetId, folder, fluorRel, roi, lowFrames, highFrames, yRow, paramsHash, saveTs)
fid = fopen(path, 'a');

% LOW
for j = 1:numel(lowFrames)
    fr = lowFrames(j);
    fprintf(fid, '%s,%s,%s,%d,%d,%s,%.15g,%s,%s\n', ...
        esc(datasetId), esc(folder), esc(fluorRel), roi, fr, 'LOW', yRow(fr), esc(paramsHash), esc(saveTs));
end

% HIGH
for j = 1:numel(highFrames)
    fr = highFrames(j);
    fprintf(fid, '%s,%s,%s,%d,%d,%s,%.15g,%s,%s\n', ...
        esc(datasetId), esc(folder), esc(fluorRel), roi, fr, 'HIGH', yRow(fr), esc(paramsHash), esc(saveTs));
end

fclose(fid);
end

function s = esc(x)
% minimal CSV escaping for fields that are expected to be simple (no commas in your keys)
if ischar(x)
    s = x;
else
    s = char(x);
end
end

function onOpenOutDir(src, ~)
fig = ancestor(src, 'figure');
state = guidata(fig);

state = setOutputPaths(state);
guidata(fig, state);

if exist(state.outDir, 'dir')
    if ispc
        winopen(state.outDir);
    elseif ismac
        system(sprintf('open "%s"', state.outDir));
    else
        system(sprintf('xdg-open "%s"', state.outDir));
    end
end

end
