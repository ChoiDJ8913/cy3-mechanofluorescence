function T = SegMeansMinimal(varargin)
% SegMeansMinimal
% - from *_segmeans_all.csv/.xlsx in the sub-folders
%   long_min : [src, f_mean, mean_sgnl, mean_bgnd, mean_raw]
%   wide_sgnl : [src, s1, s2, ...] (mean_sgnl per segment, widened per src)
%   wide_bgnd : [src, s1, s2, ...] (mean_bgnd)
%   wide_raw  : [src, s1, s2, ...] (mean_raw)
%   wide_all  : [src, s1_sgnl, s1_bgnd, s1_raw, s2_sgnl, ...]  <- combined sheet
%
% usage:
%   SegMeansMinimal;                                % pick a folder
%   SegMeansMinimal('D:\MT\batch');                 % specify the root
%   SegMeansMinimal('D:\MT\batch','OrderWithinSrc','seg');   % segment order (default)
%   SegMeansMinimal('D:\MT\batch','OrderWithinSrc','force'); % ascending f_mean
%
% options (Name-Value):
%   'OutFile'        : 'origin_minimal.xlsx'
%   'AlsoCSV'        : false  (true also writes the wide_* tables as CSV)
%   'Pattern'        : ["*_segmeans_all"]  (add patterns if needed)
%   'OrderWithinSrc' : 'seg' | 'force' | 'none'
%                       - 'seg'   : ascending seg if the file has a seg column, otherwise force
%                       - 'force' : ascending f_mean
%                       - 'none'  : original row order in the file
%   'SrcMode'        : 'id' | 'path'

% ---------------- options ----------------
p = inputParser;
addOptional( p, 'rootDir', "", @(s)isstring(s)||ischar(s));
addParameter(p, 'OutFile', 'origin_minimal.xlsx', @(s)isstring(s)||ischar(s));
addParameter(p, 'AlsoCSV', false, @(x)islogical(x)||ismember(x,[0,1]));
addParameter(p, 'Pattern', "*_segmeans_all", @(x)isstring(x)||iscellstr(x));
addParameter(p, 'OrderWithinSrc', 'seg', @(s)isstring(s)||ischar(s));
addParameter(p, 'SrcMode', 'id', @(s)isstring(s)||ischar(s));
parse(p, varargin{:});

rootDir  = string(p.Results.rootDir);
outFile  = string(p.Results.OutFile);
alsoCSV  = logical(p.Results.AlsoCSV);
patterns = string(p.Results.Pattern);
orderMode = lower(string(p.Results.OrderWithinSrc));
srcMode   = lower(string(p.Results.SrcMode));

if strlength(rootDir)==0 || ~isfolder(rootDir)
    d = uigetdir(pwd, 'Select ROOT folder containing *_segmeans_all.*');
    if isequal(d,0)
        error('No folder selected.');
    end
    rootDir = string(d);
end

% --------------- discover files ---------------
L = [];
for pat = patterns(:).'
    L = [L; dir(fullfile(rootDir, '**', pat + ".csv")); ...
             dir(fullfile(rootDir, '**', pat + ".xlsx"))]; %#ok<AGROW>
end
if isempty(L)
    error('No %s.(csv|xlsx) under: %s', strjoin(patterns, ' / '), rootDir);
end

% --------------- stack minimal LONG ---------------
T = table('Size',[0 5], ...
    'VariableTypes', {'string','double','double','double','double'}, ...
    'VariableNames', {'src','f_mean','mean_sgnl','mean_bgnd','mean_raw'});

for k = 1:numel(L)
    fp = fullfile(L(k).folder, L(k).name);
    Tk = readOne(fp);                     % keep every column (no warning)

    % --- decide the within-src ordering ---
    ord = 1:height(Tk);
    switch orderMode
        case "seg"
            if ismember("seg", string(Tk.Properties.VariableNames))
                [~,ord] = sort(double(Tk.seg), 'ascend');
            else
                [~,ord] = sort(double(Tk.f_mean), 'ascend');
            end
        case "force"
            [~,ord] = sort(double(Tk.f_mean), 'ascend');
        case "none"
            % keep the original order in the file
        otherwise
            error('Unknown OrderWithinSrc: %s', orderMode);
    end
    Tk = Tk(ord,:);

    % build src as a row vector (prefer id/roi, fall back to the relative path)
    srcVec = makeSrcVec(L(k).folder, L(k).name, Tk, rootDir, srcMode);

    % accumulate only the four needed columns (srcVec has the length of height(Tk))
    tadd = table( srcVec, ...
        double(Tk.f_mean), ...
        double(Tk.mean_sgnl), ...
        double(Tk.mean_bgnd), ...
        double(Tk.mean_raw), ...
        'VariableNames', T.Properties.VariableNames);
    T = [T; tadd]; %#ok<AGROW>
end

% --------------- build wide_* by src ---------------
[G, srcKeys] = findgroups(T.src);
counts = splitapply(@numel, T.f_mean, G);
Kmax   = max(counts);
segCols = compose('s%d', 1:Kmax);    % s1,s2,...

% common builder
buildWide = @(valCol) buildWideBySrc(T, G, srcKeys, Kmax, segCols, valCol);

W_sgnl = buildWide('mean_sgnl');
W_bgnd = buildWide('mean_bgnd');
W_raw  = buildWide('mean_raw');

% new combined sheet: wide_all (sgnl/bgnd/raw in one tab)
W_all = buildWideAll(W_sgnl, W_bgnd, W_raw, segCols);

% --------------- save ---------------
outX = fullfile(rootDir, outFile);

writetable(T,      outX, 'Sheet','long_min',  'WriteMode','overwritesheet');
writetable(W_sgnl, outX, 'Sheet','wide_sgnl', 'WriteMode','overwritesheet');
writetable(W_bgnd, outX, 'Sheet','wide_bgnd', 'WriteMode','overwritesheet');
writetable(W_raw,  outX, 'Sheet','wide_raw',  'WriteMode','overwritesheet');
writetable(W_all,  outX, 'Sheet','wide_all',  'WriteMode','overwritesheet');

if alsoCSV
    outBase = erase(outFile, '.xlsx');
    writetable(W_sgnl, fullfile(rootDir, outBase + "_wide_sgnl.csv"));
    writetable(W_bgnd, fullfile(rootDir, outBase + "_wide_bgnd.csv"));
    writetable(W_raw,  fullfile(rootDir, outBase + "_wide_raw.csv"));
    writetable(W_all,  fullfile(rootDir, outBase + "_wide_all.csv"));
end

fprintf(['[OK] Wrote %s (sheets: long_min, wide_sgnl, ', ...
         'wide_bgnd, wide_raw, wide_all)\n'], outX);

% =========================================================
% ---- helper: build wide (brace assignment + NaN initialisation) ----
% =========================================================
function W = buildWideBySrc(Tin, Gid, srcKeysLocal, KmaxLocal, segColsLocal, valName)
    W = table('Size', [numel(srcKeysLocal) 1+KmaxLocal], ...
              'VariableTypes', [{'string'} repmat({'double'},1,KmaxLocal)], ...
              'VariableNames', ['src', segColsLocal]);

    W.src = srcKeysLocal;

    % fill the empty cells with NaN rather than 0
    if KmaxLocal > 0
        W{:, 2:end} = NaN;
    end

    for i = 1:numel(srcKeysLocal)
        m = (Gid == i);
        v = double(Tin.(valName)(m));
        v = v(:).';                               % 1×N row
        W{i, 2:(1+numel(v))} = v;                 % leave the rest as NaN
    end
end

% =========================================================
% ---- helper: build wide_all (the three values combined) ----
% =========================================================
function W_allLocal = buildWideAll(Ws, Wb, Wr, segColsLocal)
    % assumes the three wide tables share the same src ordering
    W_allLocal = table(Ws.src, 'VariableNames', {'src'});

    % ---- 1) sgnl block (s1_sgnl, s2_sgnl, ...) ----
    for j = 1:numel(segColsLocal)
        colName = char(segColsLocal(j));     % e.g. 's1'
        varName = [colName '_sgnl'];         % 's1_sgnl'
        W_allLocal.(varName) = Ws.(colName);
    end

    % ---- 2) bgnd block (s1_bgnd, s2_bgnd, ...) ----
    for j = 1:numel(segColsLocal)
        colName = char(segColsLocal(j));
        varName = [colName '_bgnd'];         % 's1_bgnd'
        W_allLocal.(varName) = Wb.(colName);
    end

    % ---- 3) raw block (s1_raw, s2_raw, ...) ----
    for j = 1:numel(segColsLocal)
        colName = char(segColsLocal(j));
        varName = [colName '_raw'];          % 's1_raw'
        W_allLocal.(varName) = Wr.(colName);
    end
end


% =========================================================
% --------- helpers: read a file / build the src string --------
% =========================================================
function Tk = readOne(fp)
    Tk = readtable(fp, 'TextType','string', 'VariableNamingRule','preserve');
    need = ["f_mean","mean_sgnl","mean_bgnd","mean_raw"];
    miss = need(~ismember(need, string(Tk.Properties.VariableNames)));
    if ~isempty(miss)
        error('Missing column(s) %s in %s', strjoin(miss,','), fp);
    end
end

function srcVec = makeSrcVec(folderPath, fileName, Tk, rootDirLocal, srcModeLocal)
    n = height(Tk);
    names = string(Tk.Properties.VariableNames);

    % base: id when present, otherwise the relative path (file base name)
    if srcModeLocal == "id" && ismember("id", names)
        baseVec = string(Tk.id);          % n x 1 (the id exactly as stored in the file)
    else
        relFolder = erase(string(folderPath), rootDirLocal);
        if strlength(relFolder)==0
            relFolder = "/";
        end
        relFolder = strrep(relFolder, filesep, '/');
        baseSingle = relFolder + string(erase(fileName, {'_segmeans_all.csv','_segmeans_all.xlsx'}));
        baseVec = repmat(baseSingle, n, 1);  % replicate to n x 1
    end

    % ROI suffix (per row when present)
    if ismember("roi", names)
        roiSuffix = "/roi" + string(Tk.roi);
    else
        roiSuffix = strings(n,1);
    end

    % concatenate and strip the leading '/'
    srcVec = baseVec + roiSuffix;
    srcVec = regexprep(srcVec, '^/', '');
end

end
