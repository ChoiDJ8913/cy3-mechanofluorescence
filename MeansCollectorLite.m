function MeansCollectorLite()
% Means Collector (Lite)
% - file Prev/Next navigation + keyboard shortcuts (left/right, PgUp/PgDn, Home/End)
% - selected ROIs always visible (list), multi-selection shown
% - preview/save dialogs made robust
% - type-safe comparison for mixed ROI types (roiMask)

%% ----------------------- STATE -----------------------------------------
st = struct();
st.root   = pwd;
st.files  = struct('path',{},'id',{},'T',{});  % table for each file
st.idx    = 1;
st.visRois = [];                               % list of ROIs to show on the plot

%% ----------------------- UI --------------------------------------------
fig = uifigure('Name','Means Collector (Lite)', ...
    'Position',[100 100 1200 720], 'AutoResizeChildren','on');
fig.WindowKeyPressFcn = @onKey;  % <- keyboard navigation

% main 3x2 grid (top bar / body / bottom bar)
GL  = uigridlayout(fig,[3 2]);
GL.RowHeight   = {36,'1x',36};
GL.ColumnWidth = {'1x','1x'};
GL.Padding     = [8 8 8 8];
GL.RowSpacing  = 8; GL.ColumnSpacing = 8;

% -- top bar ------------------------------------------------------------
TB = uigridlayout(GL,[1 10]); TB.Layout.Row=1; TB.Layout.Column=[1 2];
TB.ColumnWidth = {96,'1x',64,64,64,48,120,84,80,80};
TB.RowHeight   = {34};                             % fixed row height
TB.Padding = [0 0 0 0];

uibutton(TB,'Text','Select folder...','ButtonPushedFcn',@pickFolder);
st.lblLoaded = uilabel(TB,'Text','Loaded 0/0');

uipanel(TB,'BorderType','none');  % spacer

% file navigation (Prev / Next / index edit / total count)
st.btnPrev = uibutton(TB,'Text','Prev','ButtonPushedFcn',@(~,~)nav(-1));
st.btnNext = uibutton(TB,'Text','Next','ButtonPushedFcn',@(~,~)nav(+1));
st.edIdx   = uieditfield(TB,'numeric','Limits',[1 Inf],'Value',1, ...
    'ValueDisplayFormat','%.0f','ValueChangedFcn',@jumpTo);
st.lblN    = uilabel(TB,'Text','/ 0');

% include file / save / rescan
st.cbIncludeAll = uicheckbox(TB,'Text','Include this file','Value',false, ...
    'ValueChangedFcn',@toggleIncludeFile);
uibutton(TB,'Text','Save sel.','ButtonPushedFcn',@saveSelected);
uibutton(TB,'Text','Rescan','ButtonPushedFcn',@(~,~)scanAndLoad(st.root));

% -- left: table (scroll-safe) -----------------------------------------
LP = uipanel(GL,'Scrollable','on'); LP.Layout.Row=2; LP.Layout.Column=1;
LPGL = uigridlayout(LP,[1 1]); LPGL.RowHeight={'1x'}; LPGL.ColumnWidth={'1x'};
LPGL.Padding=[0 0 0 0]; LPGL.RowSpacing=0; LPGL.ColumnSpacing=0;

st.tbl = uitable(LPGL,'Data',table(),'RowStriping','on');
st.tbl.Layout.Row=1; st.tbl.Layout.Column=1;
st.tbl.ColumnEditable = false;
st.tbl.CellEditCallback = @tableEdited;

% -- right: file/ROI/plot (scroll-safe) --------------------------------
RP = uipanel(GL,'Title','File / ROI','Scrollable','on');
RP.Layout.Row=2; RP.Layout.Column=2;

% rows: file label (2) + toolbar (1) + plot (1x) + ROI list (120 px) + bottom margin
RG = uigridlayout(RP,[6 1]);
RG.RowHeight = {'fit','fit',26,'1x',120,'fit'};
RG.Padding   = [8 8 8 8];
RG.RowSpacing= 6;

st.lblFile = uilabel(RG,'Text','File: -','Interpreter','none');
try, st.lblFile.WordWrap = 'on'; end
st.lblID   = uilabel(RG,'Text','ID: -','Interpreter','none');

% ROI toolbar (slim)
ROIrow = uigridlayout(RG,[1 9]); ROIrow.Layout.Row=3;
ROIrow.ColumnWidth = {'fit',80,8,'fit','fit','fit','1x','fit','fit'};
ROIrow.RowHeight   = {26};
ROIrow.Padding     = [0 0 0 0]; ROIrow.ColumnSpacing=6;

uilabel(ROIrow,'Text','ROI:','HorizontalAlignment','right','FontSize',10);
st.ddRoi = uidropdown(ROIrow,'Items',{'-'},'Value','-', ...
    'ValueChangedFcn',@(~,~)refreshPlot(),'FontSize',10);
uipanel(ROIrow,'BorderType','none'); % spacer
uibutton(ROIrow,'Text','Use',   'Tooltip','Set use=on for all rows of the selected ROI', ...
    'ButtonPushedFcn',@(~,~)setUseForROI(true,false),'FontSize',10);
uibutton(ROIrow,'Text','Clear', 'Tooltip','Set use=off for all rows of the selected ROI', ...
    'ButtonPushedFcn',@(~,~)setUseForROI(false,false),'FontSize',10);
uibutton(ROIrow,'Text','Only',  'Tooltip','	Turn on the selected ROI only, others off', ...
    'ButtonPushedFcn',@(~,~)setUseForROI(true,true),'FontSize',10);
uipanel(ROIrow,'BorderType','none'); % right margin
uibutton(ROIrow,'Text','◀','Tooltip','Prev ROI','FontSize',10, ...
    'ButtonPushedFcn',@(~,~)stepROI(-1));
uibutton(ROIrow,'Text','▶','Tooltip','Next ROI','FontSize',10, ...
    'ButtonPushedFcn',@(~,~)stepROI(+1));

% plot
st.ax = uiaxes(RG); st.ax.Layout.Row=4;
disableDefaultInteractivity(st.ax);
st.ax.Interactions = [panInteraction zoomInteraction];
axtoolbar(st.ax,{'pan','zoomin','zoomout','restoreview'});
title(st.ax,'Means per SEG (all ROIs shown, selected ROI highlighted)');
xlabel(st.ax,'SEG'); ylabel(st.ax,'mean');

% ROI list (visible/used)
LS = uigridlayout(RG,[1 2]); LS.Layout.Row=5;
LS.ColumnWidth = {'1x','1x'}; LS.ColumnSpacing = 8; LS.Padding=[0 0 0 0];

gp1 = uipanel(LS,'Title','Visible ROIs (multi-select)');
g1  = uigridlayout(gp1,[1 1]); g1.RowHeight={'1x'}; g1.ColumnWidth={'1x'}; g1.Padding=[4 4 4 4];
st.lbVis = uilistbox(g1,'Items',{},'Value',{},'Multiselect','on', ...
    'ValueChangedFcn',@(~,~)onVisChanged());

gp2 = uipanel(LS,'Title','Used ROIs (auto)');
g2  = uigridlayout(gp2,[1 1]); g2.RowHeight={'1x'}; g2.ColumnWidth={'1x'}; g2.Padding=[4 4 4 4];
st.lbUsed = uilistbox(g2,'Items',{},'Value',{}, ...
    'ValueChangedFcn',@(~,~)onUsedPick());

% -- bottom button row --------------------------------------------------
BB = uigridlayout(GL,[1 4]); BB.Layout.Row=3; BB.Layout.Column=[1 2];
BB.ColumnWidth = {70, 70, 120, 150};   % [All on, All off, Export summary, Export wide]
BB.RowHeight   = {34};
BB.ColumnSpacing = 12; BB.Padding = [0 0 0 0];
uibutton(BB,'Text','All on','ButtonPushedFcn',@(~,~)bulkUse(true));
uibutton(BB,'Text','All off','ButtonPushedFcn',@(~,~)bulkUse(false));
uibutton(BB,'Text','Export summary','ButtonPushedFcn',@exportSummary);
uibutton(BB,'Text','Export merged (wide)','ButtonPushedFcn',@exportMergedWide);


%% ----------------------- CALLBACKS / LOGIC ------------------------------
    function pickFolder(~,~)
        d = uigetdir(st.root,'Select root folder'); if isequal(d,0), return; end
        st.root = d; scanAndLoad(d);
    end

    function scanAndLoad(root)
        st.files = readAllMeans(root);
        n = numel(st.files);
        st.idx = min(max(1, st.idx), max(1,n));
        st.lblLoaded.Text = sprintf('Loaded %d/%d', st.idx, n);
        st.lblN.Text = sprintf('/ %d', n);
        st.edIdx.Limits = [1 max(1,n)]; st.edIdx.Value = st.idx;
        st.cbIncludeAll.Value = false;
        loadIdx(st.idx);
    end

    function nav(d)
        % move to previous/next file, wrap around
        if isempty(st.files), return; end
        n = numel(st.files);
        st.idx = mod(st.idx - 1 + d, n) + 1;  % cycle 1..n
        st.edIdx.Value = st.idx;
        st.lblLoaded.Text = sprintf('Loaded %d/%d', st.idx, n);
        loadIdx(st.idx);
    end

    function onKey(~,evt)
        % file navigation by keyboard
        switch evt.Key
            case {'rightarrow','pagedown'}, nav(+1);
            case {'leftarrow','pageup'},    nav(-1);
            case 'home',                    st.idx = 1; st.edIdx.Value=1; loadIdx(1);
            case 'end',                     st.idx = max(1,numel(st.files)); st.edIdx.Value=st.idx; loadIdx(st.idx);
        end
    end

    function jumpTo(~,~)
        if isempty(st.files), return; end
        st.idx = max(1, min(numel(st.files), round(st.edIdx.Value)));
        st.lblLoaded.Text = sprintf('Loaded %d/%d', st.idx, numel(st.files));
        loadIdx(st.idx);
    end

    function stepROI(d)
        if isempty(st.files) || isempty(st.ddRoi.Items), return; end
        items = st.ddRoi.Items; if isempty(items) || strcmp(items{1},'-'), return; end
        i = find(strcmp(items, st.ddRoi.Value), 1);
        i = max(1, min(numel(items), i + d));
        st.ddRoi.Value = items{i};
        refreshPlot();
    end

    function loadIdx(i)
        if isempty(st.files), clearView(); return; end
        F = st.files(i);
        st.lblFile.Text = "File: " + F.path;
        st.lblID.Text   = "ID:   " + F.id;

        T = F.T;
        if ~ismember('use',T.Properties.VariableNames), T.use = false(height(T),1); end
        T.use = logical(T.use);
        T = movevars(T,'use','Before',1);
        st.tbl.Data = T;
        st.tbl.ColumnName = T.Properties.VariableNames;
        ce = false(1,numel(st.tbl.ColumnName));
        iu = find(strcmp(st.tbl.ColumnName,'use'),1); if ~isempty(iu), ce(iu)=true; end
        st.tbl.ColumnEditable = ce;

        rois = unique(T.roi,'stable'); items = cellstr(string(rois)); if isempty(items), items = {'-'}; end
        st.ddRoi.Items = items; st.ddRoi.Value = items{1};

        updateRoiLists();
        refreshPlot();
    end

    function clearView()
        st.tbl.Data = table();
        st.ddRoi.Items = {'-'}; st.ddRoi.Value='-';
        st.lbVis.Items = {}; st.lbVis.Value = {};
        st.lbUsed.Items = {}; st.lbUsed.Value = {};
        st.visRois = [];
        cla(st.ax); title(st.ax,'Means per SEG (all ROIs shown, selected ROI highlighted)');
        st.lblFile.Text = 'File: -'; st.lblID.Text='ID: -';
    end

    function tableEdited(~,evt)
        if isempty(st.files), return; end
        if ~strcmp(st.tbl.ColumnName{evt.Indices(2)},'use'), return; end
        T = st.tbl.Data;
        st.files(st.idx).T = movevars(T,'use','After','std');
        updateRoiLists();
        refreshPlot();
    end

    function toggleIncludeFile(~,evt)
        if isempty(st.files), return; end
        on = evt.Value;
        T = ensureUseCol(st.tbl.Data, on);
        st.tbl.Data = T;
        st.files(st.idx).T = movevars(T,'use','After','std');
        updateRoiLists();
        refreshPlot();
    end

    function setUseForROI(turnOn, onlyThis)
        if isempty(st.files) || isempty(st.tbl.Data), return; end
        roiSel = st.ddRoi.Value;
        T = ensureUseCol(st.tbl.Data);
        if onlyThis, T.use(:) = false; end
        mask = roiMask(T.roi, roiSel);
        T.use(mask) = logical(turnOn);
        st.tbl.Data = T;
        st.files(st.idx).T = movevars(T,'use','After','std');
        updateRoiLists();
        refreshPlot();
    end

    function bulkUse(onoff)
        if isempty(st.files), return; end
        T = ensureUseCol(st.tbl.Data, onoff);
        st.tbl.Data = T;
        st.files(st.idx).T = movevars(T,'use','After','std');
        updateRoiLists();
        refreshPlot();
    end

    function onVisChanged()
        st.visRois = str2double(string(st.lbVis.Value));  % plot only the multi-selected ROIs
        refreshPlot();
    end

    function onUsedPick()
        v = st.lbUsed.Value;
        if isempty(v), return; end
        st.ddRoi.Value = v{1};
        refreshPlot();
    end

    function refreshPlot()
        cla(st.ax);
        if isempty(st.files) || isempty(st.tbl.Data), return; end
        T = st.tbl.Data;
        if isempty(st.ddRoi.Value) || strcmp(st.ddRoi.Value,'-'), return; end
        roiSel = st.ddRoi.Value;

        % visible ROIs: all of them when nothing is selected
        if isempty(st.lbVis.Value)
            visList = st.lbVis.Items;
        else
            visList = st.lbVis.Value;
        end

        hold(st.ax,'on');

        % grey: visible ROIs
        for k = 1:numel(visList)
            r = visList{k};
            m = roiMask(T.roi, r);
            if ~any(m), continue; end
            R = sortrows(T(m, {'seg','mean','std'}), 'seg');
            errorbar(st.ax, double(R.seg), double(R.mean), double(R.std), ...
                'o-','Color',[0.80 0.80 0.80],'LineWidth',0.9,'MarkerSize',4,'CapSize',4);
        end

        % highlighted: selected ROI
        mSel = roiMask(T.roi, roiSel);
        Rsel = sortrows(T(mSel, {'seg','mean','std','use'}), 'seg');
        if ~isempty(Rsel)
            errorbar(st.ax, double(Rsel.seg), double(Rsel.mean), double(Rsel.std), ...
                'o-','LineWidth',1.8,'MarkerSize',5,'CapSize',5);
            if any(Rsel.use)
                plot(st.ax, double(Rsel.seg(Rsel.use)), double(Rsel.mean(Rsel.use)), ...
                    'o','MarkerSize',6,'LineWidth',1.8,'Color',[0.1 0.1 0.1]);
            end
            title(st.ax, sprintf('Means per SEG (ROI %s)  —  used: %d/%d', ...
                string(roiSel), nnz(Rsel.use), height(Rsel)));
        else
            title(st.ax, 'Means per SEG (all ROIs shown, selected ROI highlighted)');
        end

        grid(st.ax,'on'); xlabel(st.ax,'SEG'); ylabel(st.ax,'mean');
        hold(st.ax,'off');
    end

    function saveSelected(~,~)
        if isempty(st.files), return; end
        rows = gatherSelected(st.files);
        if isempty(rows)
            uialert(fig,'No rows selected.','Save'); return;
        end
        openPreviewExport(rows, 'merged_means_selected.csv', 'Selected rows', defaultSaveDir(), fig);
    end

    function exportSummary(~,~)
        if isempty(st.files), return; end
        rows = gatherSelected(st.files);
        if isempty(rows)
            uialert(fig,'No rows selected.','Export summary'); return;
        end
        G = groupsummary(rows, {'id','roi','seg'}, {'mean','std','numel'}, 'mean');
        S = table(G.id, G.roi, G.seg, G.mean_mean, G.std_mean, G.numel_mean, ...
            'VariableNames', {'id','roi','seg','mean','sd','N'});
        S.sem = S.sd ./ max(1, sqrt(S.N));
        openPreviewExport(S, 'summary_by_segment.csv', 'Summary by SEG', defaultSaveDir(), fig);
    end

%% ----------------------- HELPERS ---------------------------------------
    function T = enforceSingleRoiForCurrentSession(T)
        % in the current file (session) only the ROI matching ddRoiM.Value may have use=true
        if isempty(T) || strcmp(st.ddRoiM.Value,'-') || st.data.rois<1
            return;
        end
        curRoi = uint16(clamp(round(str2double(string(st.ddRoiM.Value))),1,st.data.rois));
        T = ensureUseCol(T);
        otherOn = (uint16(T.roi) ~= curRoi) & T.use;
        if any(otherOn)
            T.use(otherOn) = false;          % switch off automatically if another ROI is on in the table
        end
    end

    function rows = gatherSelected(files)
        rows = table();
        for k=1:numel(files)
            if isempty(files(k).T), continue; end
            T = files(k).T;
            if ~ismember('use', T.Properties.VariableNames), T.use = false; end
            U = T(T.use==true, :);
            if isempty(U), continue; end
            cols = intersect({'id','roi','seg','len','mean','std','use'}, U.Properties.VariableNames,'stable');
            U = U(:, cols);
            rows = [rows; U]; %#ok<AGROW>
        end
    end

    function updateRoiLists()
        if isempty(st.tbl.Data)
            st.lbVis.Items = {}; st.lbVis.Value = {};
            st.lbUsed.Items = {}; st.lbUsed.Value = {};
            st.visRois = [];
            return;
        end
        T = ensureUseCol(st.tbl.Data);   % make sure the use column exists

        % all ROI items
        allR = cellstr(string(unique(T.roi,'stable')));
        st.lbVis.Items = allR;

        % keep the intersection with the previous selection; select all if empty
        cur = intersect(st.lbVis.Value, allR, 'stable');
        if isempty(cur), cur = allR; end
        st.lbVis.Value = cur;
        st.visRois = str2double(string(st.lbVis.Value));  % (for reference)

        % automatic list of used ROIs
        usedR = cellstr(unique(string(T.roi(T.use==true)),'stable'));
        st.lbUsed.Items = usedR;
        if ~isempty(usedR)
            if any(strcmp(usedR, char(string(st.ddRoi.Value))))
                st.lbUsed.Value = {char(string(st.ddRoi.Value))};
            else
                st.lbUsed.Value = usedR(1);
            end
        else
            st.lbUsed.Value = {};
        end
    end

    function exportMergedWide(~,~)
        % gather the rows with use=true into one line per (id, roi)
        % and export as s1_mean, s1_sd, s2_mean, s2_sd, ... (empty cells as "")
        rows = gatherSelected(st.files);
        if isempty(rows)
            uialert(fig,'No rows selected.','Export merged (wide)');
            return;
        end

        % safe sort
        rows = sortrows(rows, {'id','roi','seg'});

        % highest segment number overall
        maxSeg = max(double(rows.seg));
        if ~isfinite(maxSeg) || maxSeg < 1
            maxSeg = 1;
        end
        mnNames = compose('s%d_mean', 1:maxSeg);
        sdNames = compose('s%d_sd',   1:maxSeg);
        varNames = ['fn','id','roi', mnNames, sdNames];

        % empty table with every column typed as string (so blanks print as blanks)
        out = table('Size',[0 numel(varNames)], ...
            'VariableTypes', repmat({'string'},1,numel(varNames)), ...
            'VariableNames', varNames);

        % one row per (id, roi) group
        keys = unique(string(rows.id) + "|" + string(rows.roi), 'stable');
        for k = 1:numel(keys)
            pr = split(keys(k), "|");
            idk  = pr(1);
            roik = pr(2);

            msk = (string(rows.id)==idk) & (string(rows.roi)==roik);
            R = rows(msk,:);

            % mean per segment (aggregate duplicates by averaging)
            segIdx = double(R.seg);
            [grpSeg,~,grpIdx] = unique(segIdx);
            mm = accumarray(grpIdx, double(R.mean), [], @mean);
            ss = accumarray(grpIdx, double(R.std),  [], @mean);

            % fill as a string vector (missing segments become "")
            rowMean = strings(1, maxSeg);
            rowSd   = strings(1, maxSeg);
            for t = 1:numel(grpSeg)
                s = grpSeg(t);
                if s>=1 && s<=maxSeg
                    rowMean(s) = compose('%.6g', mm(t));
                    rowSd(s)   = compose('%.6g', ss(t));
                end
            end

            % build the one-row table: fn, id, roi + sK_mean/sK_sd
            row = table( ...
                string(sprintf('%s_%s', idk, roik)), idk, roik, ...
                'VariableNames', {'fn','id','roi'});

            % append the segment columns
            for s = 1:maxSeg
                row.(sprintf('s%d_mean',s)) = rowMean(s);
            end
            for s = 1:maxSeg
                row.(sprintf('s%d_sd',s))   = rowSd(s);
            end

            out = [out; row]; %#ok<AGROW>
        end

        % preview -> save (default save path: the root folder)
        openPreviewExport(out, fullfile(st.root,'merged_wide.csv'), ...
            'Merged means (wide; fn=row, sK_mean/sK_sd; blanks for missing)', defaultSaveDir(), fig);
    end

    function defp = defaultSaveDir()
        % always save to the root folder the user picked with pickFolder
        defp = st.root;
    end

end

%% ======================= I/O: read all means ============================
function files = readAllMeans(root)
files = struct('path',{},'id',{},'T',{});
if isempty(root) || ~isfolder(root), return; end
d = dir(fullfile(root,'**','*_means.csv'));
if isempty(d), return; end
for i=1:numel(d)
    fp = fullfile(d(i).folder, d(i).name);
    T  = safeReadMeans(fp);
    if isempty(T), continue; end
    id = T.id(1);
    files(end+1) = struct('path',fp,'id',string(id),'T',T); %#ok<AGROW>
end
end

function T = safeReadMeans(fp)
T = table();
try
    R = readtable(fp,'VariableNamingRule','preserve');
catch
    try, R = readtable(fp); catch, return; end
end
rawNames  = string(R.Properties.VariableNames);
normNames = lower(regexprep(strtrim(rawNames),'\s+',''));
getVar = @(aliases) pickVar(R, rawNames, normNames, aliases);

id_   = getVar({'id','name','fileid'});
roi_  = getVar({'roi'});
seg_  = getVar({'seg','segment','plateau','pl'});
mean_ = getVar({'mean','avg','mu','mean(norm=1)','mean_norm'});
std_  = getVar({'std','sd','stdev','sigma'});

if isempty(id_) || isempty(roi_) || isempty(seg_) || isempty(mean_) || isempty(std_)
    return
end
start_ = getVar({'start','begin'}); end_ = getVar({'end','stop','finish'});
if ~isempty(start_) && ~isempty(end_)
    len_ = max(0, double(end_) - double(start_) + 1);
else
    len_ = NaN(height(R),1);
end
T = table( string(id_), uint16(roi_), uint16(seg_), ...
    len_, double(mean_), double(std_), ...
    false(height(R),1), ...
    'VariableNames', {'id','roi','seg','len','mean','std','use'});
end

function col = pickVar(R, rawNames, normNames, aliases)
col = [];
for a = string(aliases)
    key = lower(regexprep(strtrim(a),'\s+',''));
    idx = find(normNames==key, 1);
    if isempty(idx), idx = find(contains(normNames, key), 1); end
    if ~isempty(idx)
        col = R.(rawNames(idx));
        return
    end
end
end

function T = ensureUseCol(T, val)
if ~ismember('use', T.Properties.VariableNames)
    T.use = false(height(T),1);
else
    T.use = logical(T.use(:));
end
if nargin>1
    T.use(:) = logical(val);
end
end

function mask = roiMask(roiCol, r)
% type-safe comparison: always compare as strings
mask = string(roiCol) == string(r);
end

function openPreviewExport(T, defaultName, titleStr, defDir, parentFig)
if isempty(T)
    uialert(parentFig,'No data to export.','Preview');
    return;
end
if nargin < 4 || isempty(defDir)
    defDir = pwd;                 % <- no longer depends on st
end

% defaultName may or may not contain a path, so split it
[p0,f0,e0] = fileparts(defaultName);
if ~isempty(p0)
    baseDir  = p0;
    baseFile = [f0 e0];
else
    baseDir  = defDir;
    baseFile = defaultName;
end

PREVIEW_MAX = 2000;
showT = T(1:min(PREVIEW_MAX, height(T)), :);

dlg = uifigure('Name','Preview export', ...
    'Position',[100 100 880 560], 'WindowStyle','modal');

GL = uigridlayout(dlg,[3 1]);
GL.RowHeight   = {'fit','1x','fit'};
GL.ColumnWidth = {'1x'};
GL.Padding     = [8 8 8 8];

uilabel(GL,'Text',sprintf('%s — rows: %d, cols: %d (preview limited to %d rows)', ...
    titleStr, height(T), width(T), PREVIEW_MAX),'FontWeight','bold');

ut = uitable(GL,'Data',showT,'RowStriping','on');
ut.Layout.Row = 2; ut.Layout.Column = 1;

BR = uigridlayout(GL,[1 4]);
BR.Layout.Row=3;
BR.ColumnWidth = {'fit','1x','fit','fit'};
BR.Padding=[0 0 0 0];

uilabel(BR,'Text',sprintf('Preview shows %d rows; saving writes all %d rows.', ...
    height(showT), height(T)));
uipanel(BR,'BorderType','none');

uibutton(BR,'Text','Copy table', 'ButtonPushedFcn', @(~,~)copyAll());
uibutton(BR,'Text','Export to CSV...', 'ButtonPushedFcn', @(~,~)doExport());

    function copyAll()
        try
            tmp = [tempname '.csv'];
            writetable(T,tmp);
            C = fileread(tmp);
            delete(tmp);
            clipboard('copy', C);
            uialert(dlg,'Copied CSV to clipboard.','Copied','Icon','success');
        catch ME
            uialert(dlg, ME.message, 'Copy failed');
        end
    end

    function doExport()
        % set the default folder and file name explicitly
        [f,p] = uiputfile({'*.csv','CSV file'}, 'Save as', fullfile(baseDir, baseFile));
        if isequal(f,0), return; end
        try
            writetable(T, fullfile(p,f));
            close(dlg);
            uialert(parentFig, sprintf('Saved\n%s', fullfile(p,f)), 'Saved');
        catch ME
            uialert(dlg, ME.message, 'Save failed');
        end
    end
end
