function export_origin_low_high_from_trace()
% export_origin_low_high_from_trace
% - Input : per_roi_trace_table.csv (must include: folder, fluor_path_rel, roi, segment, sgnl)
% - Output: Origin-friendly 4-column CSV:
%           [low_abs, high_abs, low_rel, high_rel]  (NaN padded)
% - Normalization: per (folder, fluor_path_rel, roi), baseline = mean(LOW sgnl)
% - UI-only
% - Memory-aware: 2-pass streaming + preallocation

[fn, fp] = uigetfile({'*.csv','CSV files (*.csv)'}, 'Select per_roi_trace_table.csv');
if isequal(fn, 0)
    disp('Cancelled.');
    return
end

inPath = fullfile(fp, fn);

defaultOut = fullfile(fp, 'origin_low_high_abs_rel.csv');
[ofn, ofp] = uiputfile({'*.csv','CSV files (*.csv)'}, 'Save 4-column (abs/rel) CSV', defaultOut);
if isequal(ofn, 0)
    disp('Cancelled.');
    return
end

outPath = fullfile(ofp, ofn);

ds = makeTraceDatastore(inPath);

sumMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
cntMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

lowN = 0;
highN = 0;

% -------- PASS 1: count LOW/HIGH and build baseline sums for LOW --------
reset(ds);
while hasdata(ds)
    T = read(ds);

    seg = cellstr(T.segment);
    isL = strcmp(seg, 'LOW');
    isH = strcmp(seg, 'HIGH');

    lowN = lowN + sum(isL);
    highN = highN + sum(isH);

    if any(isL)
        folder = cellstr(T.folder);
        fluor = cellstr(T.fluor_path_rel);
        roi = double(T.roi);
        y = double(T.sgnl);

        idx = find(isL);
        for k = 1:numel(idx)
            i = idx(k);
            key = makeKey(folder{i}, fluor{i}, roi(i));

            if isKey(sumMap, key)
                sumMap(key) = sumMap(key) + y(i);
                cntMap(key) = cntMap(key) + 1;
            else
                sumMap(key) = y(i);
                cntMap(key) = 1;
            end
        end
    end
end

if lowN == 0 && highN == 0
    error('No LOW/HIGH rows found. Check segment values in the input CSV.');
end

meanMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
keys = sumMap.keys;

for i = 1:numel(keys)
    key = keys{i};
    m = sumMap(key) ./ max(cntMap(key), 1);
    meanMap(key) = m;
end

% -------- PASS 2: fill abs/rel vectors (skip rows with invalid baseline) --------
lowAbs = nan(lowN, 1);
highAbs = nan(highN, 1);
lowRel = nan(lowN, 1);
highRel = nan(highN, 1);

iL = 0;
iH = 0;

reset(ds);
while hasdata(ds)
    T = read(ds);

    folder = cellstr(T.folder);
    fluor = cellstr(T.fluor_path_rel);
    roi = double(T.roi);

    seg = cellstr(T.segment);
    y = double(T.sgnl);

    for i = 1:height(T)
        key = makeKey(folder{i}, fluor{i}, roi(i));

        if ~isKey(meanMap, key)
            continue
        end

        base = meanMap(key);
        if ~(isfinite(base) && base > 0)
            continue
        end

        if strcmp(seg{i}, 'LOW')
            iL = iL + 1;
            lowAbs(iL, 1) = y(i);
            lowRel(iL, 1) = y(i) ./ base;
        end

        if strcmp(seg{i}, 'HIGH')
            iH = iH + 1;
            highAbs(iH, 1) = y(i);
            highRel(iH, 1) = y(i) ./ base;
        end
    end
end

if iL < numel(lowAbs)
    lowAbs = lowAbs(1:iL, 1);
    lowRel = lowRel(1:iL, 1);
end

if iH < numel(highAbs)
    highAbs = highAbs(1:iH, 1);
    highRel = highRel(1:iH, 1);
end

n = max(numel(lowAbs), numel(highAbs));

colLowAbs = nan(n, 1);
colHighAbs = nan(n, 1);
colLowRel = nan(n, 1);
colHighRel = nan(n, 1);

if ~isempty(lowAbs)
    colLowAbs(1:numel(lowAbs), 1) = lowAbs;
    colLowRel(1:numel(lowRel), 1) = lowRel;
end

if ~isempty(highAbs)
    colHighAbs(1:numel(highAbs), 1) = highAbs;
    colHighRel(1:numel(highRel), 1) = highRel;
end

Tout = table(colLowAbs, colHighAbs, colLowRel, colHighRel, ...
    'VariableNames', {'low_abs','high_abs','low_rel','high_rel'});

writetable(Tout, outPath);

fprintf('Done.\nInput : %s\nOutput: %s\n', inPath, outPath);

end

function ds = makeTraceDatastore(inPath)
ds = tabularTextDatastore(inPath);
ds.Delimiter = ',';
ds.ReadSize = 200000;
ds.SelectedVariableNames = {'folder','fluor_path_rel','roi','segment','sgnl'};
end

function key = makeKey(folder, fluor, roi)
key = [folder '|' fluor '|' num2str(roi)];
end
