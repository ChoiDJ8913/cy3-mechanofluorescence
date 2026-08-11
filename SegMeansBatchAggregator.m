function out = SegMeansBatchAggregator(rootDir, varargin)
% SegMeansBatchAggregator
% - recursively collects *_segmeans_all.csv(.xlsx) files and
%   merges them into an Origin-friendly wide table (rows = traces, columns = force steps).
%
% Usage:
%   SegMeansBatchAggregator();              % folder dialog
%   SegMeansBatchAggregator('D:\MT\data');  % specify the root
%
% Name-Value options (all optional):
%   'NormMode'     : 'fl'(default) | 'first' | 'last' | 'none'
%   'ForceRound'   : 0.5  (rounding step for the force used in column names, pN)
%   'OutBase'      : 'origin_ready'  (base name of the output file)
%   'AlsoCSV'      : false | true    (also save the three wide tables as CSV)
%
% schema of the input files (column names):
%   id, roi, seg, start, end, len, f_mean,
%   mean_sgnl, sd_sgnl, mean_bgnd, sd_bgnd, mean_raw, sd_raw

% ------------------- options -------------------
p = inputParser; p.FunctionName = mfilename;
addOptional(p, 'rootDir', "", @(s)isstring(s)||ischar(s));
addParameter(p, 'NormMode',   'fl',    @(s)isstring(s)||ischar(s));
addParameter(p, 'ForceRound', 0.5,     @(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p, 'OutBase',    'origin_ready', @(s)isstring(s)||ischar(s));
addParameter(p, 'AlsoCSV',    false,   @(x)islogical(x)||ismember(x,[0,1]));
parse(p, rootDir, varargin{:});

rootDir     = string(p.Results.rootDir);
normMode    = lower(string(p.Results.NormMode));
dr          = double(p.Results.ForceRound);
outBase     = string(p.Results.OutBase);
alsoCSV     = logical(p.Results.AlsoCSV);

if strlength(rootDir)==0 || ~isfolder(rootDir)
    d = uigetdir(pwd, 'Select ROOT folder containing *_segmeans_all.csv');
    if isequal(d,0), error('No folder selected.'); end
    rootDir = string(d);
end

% ------------------- discover files -------------------
pat1 = dir(fullfile(rootDir, '**', '*_segmeans_all.csv'));
pat2 = dir(fullfile(rootDir, '**', '*_segmeans_all.xlsx'));
files = [pat1(:); pat2(:)];
if isempty(files), error('No *_segmeans_all.(csv|xlsx) found under %s', rootDir); end

% ------------------- read & stack (LONG) -------------------
LONG = table('Size',[0 13], ...
    'VariableTypes', {'string','uint16','uint16','uint32','uint32','uint32','double', ...
                      'double','double','double','double','double','double'}, ...
    'VariableNames', {'id','roi','seg','start','end','len','f_mean', ...
                      'mean_sgnl','sd_sgnl','mean_bgnd','sd_bgnd','mean_raw','sd_raw'});

for k = 1:numel(files)
    fp = fullfile(files(k).folder, files(k).name);
    T = safeReadSegMeans(fp);
    LONG = [LONG; T]; %#ok<AGROW>
end

% helper: infer the trace direction (increasing/decreasing)
grp = findgroups(LONG.id, LONG.roi);
dirLab = repmat("undetermined", height(LONG), 1);
for g = 1:max(grp)
    idx = (grp==g);
    seg  = double(LONG.seg(idx));
    fval = double(LONG.f_mean(idx));
    if numel(seg) >= 2
        r = corr(seg(:), fval(:), 'rows','complete');
        if isfinite(r)
            dirLab(idx) = tern(r>=0, "up", "down");
        end
    end
end

% normalisation (relative Sgnl)
rel = nan(height(LONG),1);
K = findgroups(LONG.id, LONG.roi);
for g = 1:max(K)
    m = (K==g);
    s = LONG.mean_sgnl(m);
    switch normMode
        case "fl"    % mean of first and last
            % sort by segment, then average the first and the last
            [~,ord] = sort(LONG.seg(m), 'ascend');
            s2 = s(ord);
            if numel(s2)>=2
                base = mean([s2(1), s2(end)], 'omitnan');
            else
                base = mean(s2, 'omitnan');
            end
        case "first"
            [~,ord] = sort(LONG.seg(m), 'ascend'); base = s(ord(1));
        case "last"
            [~,ord] = sort(LONG.seg(m), 'ascend'); base = s(ord(end));
        case "none"
            base = 1;
        otherwise
            error('Unknown NormMode: %s', normMode);
    end
    if ~isfinite(base) || base==0, base = 1; end
    rel(m) = s / base;
end

LONG.dir = dirLab;
LONG.rel_sgnl = rel;

% ------------------- build WIDE tables -------------------
% round the force -> column name
f_round = round(LONG.f_mean/dr)*dr;
fkeys = unique(f_round); fkeys = sort(fkeys,'ascend');

% build the column name (format F_5p0)
fnames = arrayfun(@(x) sprintf('F_%s', strrep(num2str(x,'%.10g'),'.','p')), fkeys, 'uni',0);

% group = (id, roi, dir)
G = findgroups(LONG.id, LONG.roi, LONG.dir);
keys = splitapply(@(a,b,c) {string(a(1)), uint16(b(1)), string(c(1))}, ...
                  LONG.id, LONG.roi, LONG.dir, G);
Ngrp = max(G);

% helper: pivot function
wide_rel = newWide(keys, fnames);
wide_bg  = newWide(keys, fnames);
wide_rw  = newWide(keys, fnames);

for g = 1:Ngrp
    m = (G==g);
    % average duplicates in the same force cell (ideally there is only one)
    [vals_rel, vals_bg, vals_rw] = accumToVector(f_round(m), LONG.rel_sgnl(m), ...
                                                 LONG.mean_bgnd(m), LONG.mean_raw(m), ...
                                                 fkeys);
    wide_rel{g,4:end} = num2cell(vals_rel(:)');
    wide_bg{g,4:end}  = num2cell(vals_bg(:)');
    wide_rw{g,4:end}  = num2cell(vals_rw(:)');
end

% ------------------- write outputs -------------------
outXlsx = fullfile(rootDir, outBase + ".xlsx");
writetable(LONG,     outXlsx, 'Sheet','long_all',       'WriteMode','overwritesheet');
writetable(wide_rel, outXlsx, 'Sheet','wide_rel_sgnl',  'WriteMode','overwritesheet');
writetable(wide_bg,  outXlsx, 'Sheet','wide_mean_bgnd', 'WriteMode','overwritesheet');
writetable(wide_rw,  outXlsx, 'Sheet','wide_mean_raw',  'WriteMode','overwritesheet');

if alsoCSV
    writetable(wide_rel, fullfile(rootDir, outBase + "_wide_rel_sgnl.csv"));
    writetable(wide_bg,  fullfile(rootDir, outBase + "_wide_mean_bgnd.csv"));
    writetable(wide_rw,  fullfile(rootDir, outBase + "_wide_mean_raw.csv"));
end

% return struct
out = struct('xlsx', outXlsx, ...
             'wide_rel_sgnl', wide_rel, ...
             'wide_mean_bgnd', wide_bg, ...
             'wide_mean_raw',  wide_rw, ...
             'long_all', LONG);

fprintf('[OK] Wrote %s (sheets: long_all, wide_rel_sgnl, wide_mean_bgnd, wide_mean_raw)\n', outXlsx);

% ================= helpers =================
function T = safeReadSegMeans(fp)
    [~,~,ext] = fileparts(fp);
    switch lower(ext)
        case '.csv'
            T = readtable(fp, 'TextType','string');
        case {'.xlsx','.xls'}
            T = readtable(fp, 'TextType','string');
        otherwise
            error('Unsupported file: %s', fp);
    end
    % force the schema to a canonical form
    need = ["id","roi","seg","start","end","len","f_mean", ...
            "mean_sgnl","sd_sgnl","mean_bgnd","sd_bgnd","mean_raw","sd_raw"];
    for i=1:numel(need)
        if ~ismember(need(i), string(T.Properties.VariableNames))
            error('Missing column %s in %s', need(i), fp);
        end
    end
    % fix the types
    T = table( string(T.id), ...
               uint16(T.roi), uint16(T.seg), ...
               uint32(T.start), uint32(T.end), uint32(T.len), ...
               double(T.f_mean), ...
               double(T.mean_sgnl), double(T.sd_sgnl), ...
               double(T.mean_bgnd), double(T.sd_bgnd), ...
               double(T.mean_raw),  double(T.sd_raw), ...
        'VariableNames', need);
end

function t = newWide(keys, fnames)
    t = cell2table(cell(0, 3+numel(fnames)), ...
        'VariableNames', ['id','roi','dir', fnames]);
    for ii = 1:numel(keys)
        t(ii,1:3) = { keys{ii}{1}, keys{ii}{2}, keys{ii}{3} };
    end
end

function [vr, vb, vw] = accumToVector(fx, rel_s, bg, rw, fkey)
    % aggregate the means onto fkey (1 x M)
    M = numel(fkey);
    vr = nan(1,M); vb = nan(1,M); vw = nan(1,M);
    for j = 1:M
        m = (fx==fkey(j));
        if any(m)
            vr(j) = mean(rel_s(m), 'omitnan');
            vb(j) = mean(bg(m),     'omitnan');
            vw(j) = mean(rw(m),     'omitnan');
        end
    end
end

function y = tern(c,a,b), if c, y=a; else, y=b; end, end
end
