function MT_export_long_table_plateau_LOW_HIGH()
% MT_export_long_table_plateau_LOW_HIGH (MATLAB R2025a)
% UI-only exporter that builds a long-format table for histogram/scatter.
%
% Inputs (in a chosen folder):
%   - per_roi_trace_table.csv
%   - per_file_frame_table.csv
%   - per_file_selected_rois.csv
%
% Output:
%   - long_table_plateau_LOW_HIGH.xlsx   (fallback: .csv)
%
% Definitions:
%   - segment_frame is plateau label from per_file_frame_table.csv (LOW/HIGH/OTHER)
%   - Export keeps only LOW/HIGH rows
%   - low_mean_abs(ROI) = mean(sgnl_abs | segment_frame=="LOW" & is_excluded==0)
%   - sgnl_rel = sgnl_abs / low_mean_abs
%
% Sorting (requested):
%   - Rows are sorted by: folder, fluor_path_rel, roi, frame

rootDir = uigetdir(pwd, "Select folder containing per_*_table.csv files");
if isequal(rootDir, 0)
    disp("Cancelled.");
    return
end

tracePath = fullfile(rootDir, "per_roi_trace_table.csv");
framePath = fullfile(rootDir, "per_file_frame_table.csv");
selPath = fullfile(rootDir, "per_file_selected_rois.csv");

if ~isfile(tracePath)
    error("Missing file: %s", tracePath);
end

if ~isfile(framePath)
    error("Missing file: %s", framePath);
end

if ~isfile(selPath)
    error("Missing file: %s", selPath);
end

Ttrace = readCsvSelected(tracePath, ...
    ["dataset_id","folder","fluor_path_rel","roi","frame","segment","sgnl"]);

Tframe = readCsvSelected(framePath, ...
    ["dataset_id","folder","fluor_path_rel","frame","segment","is_excluded","force_pN","magpos"]);

Tsel = readCsvSelected(selPath, ...
    ["dataset_id","folder","fluor_path_rel","roi"]);

Ttrace = normalizeTypesTrace(Ttrace);
Tframe = normalizeTypesFrame(Tframe);
Tsel = normalizeTypesSelected(Tsel);

% Rename before joins (avoid suffix dependence)
if ismember("segment", string(Ttrace.Properties.VariableNames))
    Ttrace = renamevars(Ttrace, "segment", "segment_trace");
end

if ismember("segment", string(Tframe.Properties.VariableNames))
    Tframe = renamevars(Tframe, "segment", "segment_frame");
end

% Keep only selected ROIs
Ttrace = innerjoin(Ttrace, Tsel, "Keys", ["dataset_id","folder","fluor_path_rel","roi"]);

% Join frame metadata (plateau labels are source-of-truth)
T = innerjoin(Ttrace, Tframe, "Keys", ["dataset_id","folder","fluor_path_rel","frame"]);

% Optional sanity check: segment agreement
if ismember("segment_trace", string(T.Properties.VariableNames))
    segTrace = string(T.segment_trace);
    segFrame = string(T.segment_frame);
    mismatch = ~strcmp(segTrace, segFrame);
    if any(mismatch)
        warning("Segment mismatch in %d rows. Using segment_frame as source-of-truth.", sum(mismatch));
    end
end

% Keep only LOW/HIGH plateau rows
seg = string(T.segment_frame);
isLH = (seg == "LOW") | (seg == "HIGH");
T = T(isLH, :);

sgnlAbs = double(T.sgnl);
isExcluded = double(T.is_excluded);

% Compute per-ROI LOW baseline (exclude is_excluded==1)
G = findgroups(T.dataset_id, T.folder, T.fluor_path_rel, T.roi);

lowMeanByGroup = splitapply( ...
    @(segLocal, exLocal, yLocal) meanLowBaseline(segLocal, exLocal, yLocal), ...
    T.segment_frame, ...
    isExcluded, ...
    sgnlAbs, ...
    G);

lowMeanAbs = lowMeanByGroup(G);

sgnlRel = nan(size(sgnlAbs));
ok = isfinite(lowMeanAbs) & (lowMeanAbs > 0);
sgnlRel(ok) = sgnlAbs(ok) ./ lowMeanAbs(ok);

% Build output long table
Tout = table();

Tout.folder = string(T.folder);
Tout.fluor_path_rel = string(T.fluor_path_rel);
Tout.file_key = Tout.folder + "|" + Tout.fluor_path_rel;

Tout.roi = double(T.roi);
Tout.frame = double(T.frame);

Tout.segment = string(T.segment_frame);
Tout.sgnl_abs = asColumn(sgnlAbs);

Tout.low_mean_abs = asColumn(lowMeanAbs);
Tout.sgnl_rel = asColumn(sgnlRel);

if ismember("force_pN", string(T.Properties.VariableNames))
    Tout.force_pN = double(T.force_pN);
end

if ismember("magpos", string(T.Properties.VariableNames))
    Tout.magpos = double(T.magpos);
end

Tout.is_excluded = double(T.is_excluded);

% === Sorting patch (requested): file -> roi -> frame ===
Tout = sortrows(Tout, ["folder","fluor_path_rel","roi","frame"]);

defaultOut = fullfile(rootDir, "long_table_plateau_LOW_HIGH.xlsx");
[ofn, ofp] = uiputfile({"*.xlsx","Excel (*.xlsx)";"*.csv","CSV (*.csv)"}, "Save long table", defaultOut);
if isequal(ofn, 0)
    disp("Cancelled.");
    return
end

outPath = fullfile(ofp, ofn);

try
    writetable(Tout, outPath);
    fprintf("Saved: %s\n", outPath);
catch ME
    warning("Failed to write %s (%s). Writing CSV fallback in root folder.", outPath, ME.message);
    outCsv = fullfile(rootDir, "long_table_plateau_LOW_HIGH.csv");
    writetable(Tout, outCsv);
    fprintf("Saved: %s\n", outCsv);
end

end

% ================= helpers =================

function T = readCsvSelected(path, wantedVars)
opts = detectImportOptions(path);

have = string(opts.VariableNames);
wantedVars = string(wantedVars);

keep = intersect(have, wantedVars, "stable");
if isempty(keep)
    error("None of the requested variables exist in %s", path);
end

opts.SelectedVariableNames = cellstr(keep);

% IMPORTANT: do not pass "TextType" to readtable here (caused error)
T = readtable(path, opts);
end

function T = normalizeTypesTrace(T)
req = ["dataset_id","folder","fluor_path_rel","roi","frame","sgnl"];
for i = 1:numel(req)
    if ~ismember(req(i), string(T.Properties.VariableNames))
        error("per_roi_trace_table.csv missing required column: %s", req(i));
    end
end

T.dataset_id = categorical(string(T.dataset_id));
T.folder = categorical(string(T.folder));
T.fluor_path_rel = categorical(string(T.fluor_path_rel));

T.roi = double(T.roi);
T.frame = double(T.frame);
T.sgnl = double(T.sgnl);

if ismember("segment", string(T.Properties.VariableNames))
    T.segment = categorical(string(T.segment));
end
end

function T = normalizeTypesFrame(T)
req = ["dataset_id","folder","fluor_path_rel","frame","segment","is_excluded"];
for i = 1:numel(req)
    if ~ismember(req(i), string(T.Properties.VariableNames))
        error("per_file_frame_table.csv missing required column: %s", req(i));
    end
end

T.dataset_id = categorical(string(T.dataset_id));
T.folder = categorical(string(T.folder));
T.fluor_path_rel = categorical(string(T.fluor_path_rel));

T.frame = double(T.frame);
T.segment = categorical(string(T.segment));
T.is_excluded = double(T.is_excluded);

if ismember("force_pN", string(T.Properties.VariableNames))
    T.force_pN = double(T.force_pN);
end

if ismember("magpos", string(T.Properties.VariableNames))
    T.magpos = double(T.magpos);
end
end

function T = normalizeTypesSelected(T)
req = ["dataset_id","folder","fluor_path_rel","roi"];
for i = 1:numel(req)
    if ~ismember(req(i), string(T.Properties.VariableNames))
        error("per_file_selected_rois.csv missing required column: %s", req(i));
    end
end

T.dataset_id = categorical(string(T.dataset_id));
T.folder = categorical(string(T.folder));
T.fluor_path_rel = categorical(string(T.fluor_path_rel));

T.roi = double(T.roi);
end

function m = meanLowBaseline(seg, ex, y)
seg = categorical(string(seg));
ex = double(ex);
y = double(y);

mask = (seg == "LOW") & (ex == 0);

if any(mask)
    m = mean(y(mask), "omitnan");
else
    m = NaN;
end
end

function x = asColumn(x)
x = x(:);
end
