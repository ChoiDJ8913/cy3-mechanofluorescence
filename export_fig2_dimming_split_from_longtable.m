function export_fig2_dimming_split_from_longtable()
% export_fig2_dimming_split_from_longtable (MATLAB R2025a, UI-only)
% purpose:
%   from long_table_plateau_LOW_HIGH.xlsx (frame-level long table),
%   compute the ROI-level ratio = mean(sgnl_rel | HIGH) and
%     - dimming group (ratio < threshold)
%     - stable  group (ratio >= threshold)
%   split them accordingly, and
%   save Origin-friendly CSVs for the LOW/HIGH histograms of each group.
%
% input (UI):
%   - select the long_table_plateau_LOW_HIGH file (.xlsx/.csv)
%   - select the output folder
%   - enter the threshold (default 0.8)
%   - optionally save the per-frame provenance long file
%
% output (default):
%   - roi_summary_split.csv
%   - dimming_hist_abs_wide.csv / stable_hist_abs_wide.csv
%   - dimming_hist_rel_wide.csv / stable_hist_rel_wide.csv
%   - run_log.txt
%
% output (optional; large):
%   - dimming_values_long.csv / stable_values_long.csv

[fileName, fileDir] = uigetfile( ...
    {"*.xlsx;*.xls","Excel Files (*.xlsx, *.xls)";"*.csv","CSV Files (*.csv)"}, ...
    "Select long_table_plateau_LOW_HIGH file" ...
    );

if isequal(fileName, 0)
    disp("Cancelled.");
    return
end

inPath = fullfile(fileDir, fileName);

outDir = uigetdir(fileDir, "Select output folder");
if isequal(outDir, 0)
    disp("Cancelled.");
    return
end

thr = promptThreshold(0.8);
exportLong = promptExportLong();

T = readLongTable(inPath);
T = coerceRequiredTypes(T);
T = ensureFileKey(T);

maskLH = ismember(T.segment, ["LOW","HIGH"]);
T = T(maskLH, :);

maskInc = (T.is_excluded == 0) | isnan(T.is_excluded);
Tinc = T(maskInc, :);

roiSummary = buildRoiSummary(Tinc, thr);

writeSummary(outDir, roiSummary);
writeHistogramExports(outDir, Tinc, roiSummary);

if exportLong
    writeLongExports(outDir, Tinc, roiSummary);
end

writeRunLog(outDir, inPath, thr, exportLong, roiSummary);

fprintf("Done. Outputs saved to: %s\n", outDir);

end

% ===================== helpers =====================

function thr = promptThreshold(defaultThr)
thr = defaultThr;

answ = inputdlg( ...
    {"ROI split threshold (ratio_rel = mean(HIGH sgnl_rel); dimming if < thr):"}, ...
    "Threshold", ...
    1, ...
    {num2str(defaultThr)} ...
    );

if isempty(answ)
    return
end

v = str2double(answ{1});
if isfinite(v) && v > 0
    thr = v;
end
end

function exportLong = promptExportLong()
exportLong = false;

q = questdlg( ...
    "Also export per-frame provenance LONG CSVs? (large files)", ...
    "Export long values", ...
    "No", ...
    "Yes", ...
    "No" ...
    );

if strcmpi(q, "Yes")
    exportLong = true;
end
end

function T = readLongTable(inPath)
T = readtable(inPath);
end

function T = coerceRequiredTypes(T)
needVars = ["folder","fluor_path_rel","roi","frame","segment","sgnl_abs","sgnl_rel"];

for i = 1:numel(needVars)
    if ~ismember(needVars(i), string(T.Properties.VariableNames))
        error("Missing required column: %s", needVars(i));
    end
end

T.folder = string(T.folder);
T.fluor_path_rel = string(T.fluor_path_rel);

T.roi = double(T.roi);
T.frame = double(T.frame);

T.segment = string(T.segment);
T.sgnl_abs = double(T.sgnl_abs);
T.sgnl_rel = double(T.sgnl_rel);

if ismember("is_excluded", string(T.Properties.VariableNames))
    T.is_excluded = double(T.is_excluded);
else
    T.is_excluded = zeros(height(T), 1);
end

end

function T = ensureFileKey(T)
if ismember("file_key", string(T.Properties.VariableNames))
    T.file_key = string(T.file_key);
else
    T.file_key = T.folder + "|" + T.fluor_path_rel;
end
end

function S = buildRoiSummary(Tinc, thr)
% group at the ROI level
G = findgroups(Tinc.file_key, Tinc.roi);

lowMeanAbs = splitapply(@(seg, y) meanBySeg(seg, y, "LOW"), Tinc.segment, Tinc.sgnl_abs, G);
highMeanAbs = splitapply(@(seg, y) meanBySeg(seg, y, "HIGH"), Tinc.segment, Tinc.sgnl_abs, G);

lowMeanRel = splitapply(@(seg, y) meanBySeg(seg, y, "LOW"), Tinc.segment, Tinc.sgnl_rel, G);
highMeanRel = splitapply(@(seg, y) meanBySeg(seg, y, "HIGH"), Tinc.segment, Tinc.sgnl_rel, G);

nLow = splitapply(@(seg) sum(string(seg) == "LOW"), Tinc.segment, G);
nHigh = splitapply(@(seg) sum(string(seg) == "HIGH"), Tinc.segment, G);

key = splitapply(@(x) string(x(1)), Tinc.file_key, G);
roi = splitapply(@(x) double(x(1)), Tinc.roi, G);

ratioAbs = highMeanAbs ./ lowMeanAbs;
ratioRel = highMeanRel;

cls = repmat("stable", numel(ratioRel), 1);
cls(ratioRel < thr) = "dimming";

S = table();
S.file_key = string(key);
S.roi = double(roi);

S.n_low = double(nLow);
S.n_high = double(nHigh);

S.low_mean_abs = double(lowMeanAbs);
S.high_mean_abs = double(highMeanAbs);
S.ratio_abs = double(ratioAbs);

S.low_mean_rel = double(lowMeanRel);
S.high_mean_rel = double(highMeanRel);
S.ratio_rel = double(ratioRel);

S.class = string(cls);
S.threshold = repmat(double(thr), height(S), 1);

S = addFolderPathColumns(S);
S = sortrows(S, ["folder","fluor_path_rel","roi"]);
end

function S = addFolderPathColumns(S)
tok = split(S.file_key, "|");

folder = tok(:, 1);
fluor = strings(size(folder));

if size(tok, 2) >= 2
    fluor = tok(:, 2);
end

S.folder = folder;
S.fluor_path_rel = fluor;

S = movevars(S, ["folder","fluor_path_rel"], "Before", "file_key");
end

function writeSummary(outDir, roiSummary)
outPath = fullfile(outDir, "roi_summary_split.csv");
writetable(roiSummary, outPath);
end

function writeHistogramExports(outDir, Tinc, roiSummary)
% --- IMPORTANT FIX ---
% file_key and roi must be pinned as a "pair_key"; do not run ismember on them independently.
pairAll = makePairKey(Tinc.file_key, Tinc.roi);

pairD = makePairKey(roiSummary.file_key(roiSummary.class == "dimming"), roiSummary.roi(roiSummary.class == "dimming"));
pairS = makePairKey(roiSummary.file_key(roiSummary.class == "stable"),  roiSummary.roi(roiSummary.class == "stable"));

maskD = ismember(pairAll, pairD);
maskS = ismember(pairAll, pairS);

Td = Tinc(maskD, :);
Ts = Tinc(maskS, :);

[lowAbsD, highAbsD] = collectLowHigh(Td, "sgnl_abs");
[lowAbsS, highAbsS] = collectLowHigh(Ts, "sgnl_abs");

[lowRelD, highRelD] = collectLowHigh(Td, "sgnl_rel");
[lowRelS, highRelS] = collectLowHigh(Ts, "sgnl_rel");

writeWide(outDir, "dimming_hist_abs_wide.csv", lowAbsD, highAbsD, "low_abs", "high_abs");
writeWide(outDir, "stable_hist_abs_wide.csv",  lowAbsS, highAbsS, "low_abs", "high_abs");

writeWide(outDir, "dimming_hist_rel_wide.csv", lowRelD, highRelD, "low_rel", "high_rel");
writeWide(outDir, "stable_hist_rel_wide.csv",  lowRelS, highRelS, "low_rel", "high_rel");
end

function writeLongExports(outDir, Tinc, roiSummary)
pairAll = makePairKey(Tinc.file_key, Tinc.roi);

pairD = makePairKey(roiSummary.file_key(roiSummary.class == "dimming"), roiSummary.roi(roiSummary.class == "dimming"));
pairS = makePairKey(roiSummary.file_key(roiSummary.class == "stable"),  roiSummary.roi(roiSummary.class == "stable"));

maskD = ismember(pairAll, pairD);
maskS = ismember(pairAll, pairS);

Td = Tinc(maskD, :);
Ts = Tinc(maskS, :);

vars = ["folder","fluor_path_rel","file_key","roi","frame","segment","sgnl_abs","sgnl_rel","is_excluded"];

Td = Td(:, vars);
Ts = Ts(:, vars);


Td = sortrows(Td, ["folder","fluor_path_rel","roi","frame"]);
Ts = sortrows(Ts, ["folder","fluor_path_rel","roi","frame"]);

Td.class = repmat("dimming", height(Td), 1);
Ts.class = repmat("stable", height(Ts), 1);

Td = movevars(Td, "class", "Before", "folder");
Ts = movevars(Ts, "class", "Before", "folder");

writetable(Td, fullfile(outDir, "dimming_values_long.csv"));
writetable(Ts, fullfile(outDir, "stable_values_long.csv"));
end

function writeRunLog(outDir, inPath, thr, exportLong, roiSummary)
nRoi = height(roiSummary);
nD = sum(roiSummary.class == "dimming");
nS = sum(roiSummary.class == "stable");

txt = strings(0, 1);

txt(end+1, 1) = "export_fig2_dimming_split_from_longtable run log";
txt(end+1, 1) = "---------------------------------------------";
txt(end+1, 1) = "Input: " + string(inPath);
txt(end+1, 1) = "Threshold (ratio_rel): " + string(thr);
txt(end+1, 1) = "Export per-frame long: " + string(exportLong);
txt(end+1, 1) = "ROI total: " + string(nRoi);
txt(end+1, 1) = "ROI dimming: " + string(nD);
txt(end+1, 1) = "ROI stable: " + string(nS);

outPath = fullfile(outDir, "run_log.txt");
writelines(txt, outPath);
end

function m = meanBySeg(seg, y, whichSeg)
seg = string(seg);
y = double(y);

mask = (seg == whichSeg);

if any(mask)
    m = mean(y(mask), "omitnan");
else
    m = NaN;
end
end

function [vLow, vHigh] = collectLowHigh(T, varName)
seg = string(T.segment);
y = double(T.(varName));

vLow = y(seg == "LOW");
vHigh = y(seg == "HIGH");

vLow = vLow(isfinite(vLow));
vHigh = vHigh(isfinite(vHigh));
end

function writeWide(outDir, fileName, vLow, vHigh, lowCol, highCol)
nL = numel(vLow);
nH = numel(vHigh);

n = max(nL, nH);

A = nan(n, 2);

if nL > 0
    A(1:nL, 1) = vLow(:);
end

if nH > 0
    A(1:nH, 2) = vHigh(:);
end

% --- FIX: VariableNames must be string array or cellstr(char) ---
names = string([lowCol, highCol]);
names = strtrim(names);

if any(strlength(names) == 0)
    error("Empty VariableNames encountered in writeWide.");
end

Tw = array2table(A, "VariableNames", names);

outPath = fullfile(outDir, fileName);
writetable(Tw, outPath);
end

function pair = makePairKey(fileKey, roi)
fileKey = string(fileKey);
roi = double(roi);

pair = fileKey + "||" + string(roi);
end
