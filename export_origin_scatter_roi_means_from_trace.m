function export_origin_scatter_roi_means_from_trace()
% export_origin_scatter_roi_means_from_trace
% - Input : per_roi_trace_table.csv
% - Output: ROI-level means for scatter (Origin-friendly)
%   Columns:
%     low_mean_abs, high_mean_abs, low_mean_rel(=1), high_mean_rel,
%     folder, fluor_path_rel, roi
% - Normalization baseline: per ROI LOW mean (same as low_mean_abs)
% - UI-only, memory-aware streaming using datastore

[fn, fp] = uigetfile({'*.csv','CSV files (*.csv)'}, 'Select per_roi_trace_table.csv');
if isequal(fn, 0)
    disp('Cancelled.');
    return
end
inPath = fullfile(fp, fn);

defaultOut = fullfile(fp, 'origin_scatter_roi_means.csv');
[ofn, ofp] = uiputfile({'*.csv','CSV files (*.csv)'}, 'Save ROI-mean scatter CSV', defaultOut);
if isequal(ofn, 0)
    disp('Cancelled.');
    return
end
outPath = fullfile(ofp, ofn);

ds = makeTraceDatastore(inPath);

% Map: key -> struct(sumL,cntL,sumH,cntH,folder,fluor,roi)
M = containers.Map('KeyType', 'char', 'ValueType', 'any');

reset(ds);
while hasdata(ds)
    T = read(ds);

    folder = cellstr(T.folder);
    fluor = cellstr(T.fluor_path_rel);
    roi = double(T.roi);
    seg = cellstr(T.segment);
    y = double(T.sgnl);

    n = height(T);
    for i = 1:n
        key = makeKey(folder{i}, fluor{i}, roi(i));

        if isKey(M, key)
            v = M(key);
        else
            v = struct();
            v.sumL = 0;
            v.cntL = 0;
            v.sumH = 0;
            v.cntH = 0;
            v.folder = folder{i};
            v.fluor = fluor{i};
            v.roi = roi(i);
        end

        if strcmp(seg{i}, 'LOW')
            v.sumL = v.sumL + y(i);
            v.cntL = v.cntL + 1;
        end

        if strcmp(seg{i}, 'HIGH')
            v.sumH = v.sumH + y(i);
            v.cntH = v.cntH + 1;
        end

        M(key) = v;
    end
end

keys = M.keys;
m = numel(keys);

low_mean_abs = nan(m, 1);
high_mean_abs = nan(m, 1);
low_mean_rel = nan(m, 1);
high_mean_rel = nan(m, 1);

folderOut = cell(m, 1);
fluorOut = cell(m, 1);
roiOut = nan(m, 1);

k2 = 0;
for i = 1:m
    v = M(keys{i});

    if v.cntL < 1
        continue
    end

    if v.cntH < 1
        continue
    end

    base = v.sumL / v.cntL;
    if ~(isfinite(base) && base > 0)
        continue
    end

    k2 = k2 + 1;

    low_mean_abs(k2, 1) = base;
    high_mean_abs(k2, 1) = v.sumH / v.cntH;

    low_mean_rel(k2, 1) = 1.0;
    high_mean_rel(k2, 1) = high_mean_abs(k2, 1) / base;

    folderOut{k2, 1} = v.folder;
    fluorOut{k2, 1} = v.fluor;
    roiOut(k2, 1) = v.roi;
end

low_mean_abs = low_mean_abs(1:k2, 1);
high_mean_abs = high_mean_abs(1:k2, 1);
low_mean_rel = low_mean_rel(1:k2, 1);
high_mean_rel = high_mean_rel(1:k2, 1);

folderOut = folderOut(1:k2, 1);
fluorOut = fluorOut(1:k2, 1);
roiOut = roiOut(1:k2, 1);

Tout = table(low_mean_abs, high_mean_abs, low_mean_rel, high_mean_rel, ...
    folderOut, fluorOut, roiOut, ...
    'VariableNames', { ...
        'low_mean_abs', 'high_mean_abs', 'low_mean_rel', 'high_mean_rel', ...
        'folder', 'fluor_path_rel', 'roi' ...
    });

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
