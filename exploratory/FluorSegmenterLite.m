function FluorSegmenterLite
% FluorSegmenter (Lite)
% - loads Fluor.mat (S.Sgnl) and the force file, detects transitions/plateaus automatically
% - transition = change point (findchangepts) + fallback (|dF| threshold x thr)
% - Params panel rebuilt as a fixed-width grid (scrollable)
% - exports plateau/transition and mean/SD as CSV

%% ----------------------- STATE -----------------------------------------
st = struct();
st.root   = pwd;
st.data   = struct('frames',0,'rois',0,'hasF',false,'F',[],'Sgnl',[],'id',"");
st.sessions = table(); st.idx = 1;
st.segPl  = uint32(zeros(0,2));
st.segTr  = uint32(zeros(0,2));
st.excl   = {};                 % per-ROI list of exclude rectangles
st.diag   = struct();           % auxiliary information (|dF| etc.)
st.selRow = 0;                  % rows selected in the table
st.customRefRows = [];   % reference plateau row numbers chosen by the user
st.selRowsLast   = [];   % last rows selected in the table (multiple allowed)

%% ----------------------- UI SHELL --------------------------------------
st.fig = uifigure('Name','Fluor Segmenter (Lite)', ...
    'Position',[100 100 1220 740], 'AutoResizeChildren','on');

GL = uigridlayout(st.fig,[2 2]);
GL.RowHeight   = {40,'1x'};
GL.ColumnWidth = {'1x', 420};       % fixed width of the right sidebar

% ── Toolbar ─────────────────────────────────────────────────────────────
% ── Toolbar ─────────────────────────────────────────────────────────────
TB = uigridlayout(GL,[1 6]);
TB.Layout.Row = 1;
TB.Layout.Column = [1 2];
TB.ColumnWidth = {'1x','fit','fit','fit','fit','fit'};
TB.Padding = [6 4 6 4];

st.btnPick = uibutton(TB,'Text','Select folder ...','ButtonPushedFcn',@pickFolder);
st.btnPick.Layout.Column = 1;

st.ddSes = uidropdown(TB,'Items',{'(select a folder)'},'Value','(select a folder)');
st.ddSes.Layout.Column = 2;
st.ddSes.ValueChangedFcn = @sessionChanged;

st.btnLoad = uibutton(TB,'Text','Load','ButtonPushedFcn',@(~,~)loadSession());
st.btnLoad.Layout.Column = 3;

st.btnAuto = uibutton(TB,'Text','Auto Detect','ButtonPushedFcn',@(~,~)autoDetect());
st.btnAuto.Layout.Column = 4;

st.btnLoadF = uibutton(TB,'Text','Load Force...','ButtonPushedFcn',@(~,~)loadForceManual());
st.btnLoadF.Layout.Column = 5;

spacer = uipanel(TB,'BorderType','none');  % <- here
spacer.Layout.Row = 1;
spacer.Layout.Column = 6;

% -- left: plot area --------------------------------------------------
L = uigridlayout(GL,[4 1]); L.Layout.Row=2; L.Layout.Column=1;
L.RowHeight = {280,'1x',160, 46}; L.Padding=[8 8 8 8];

st.axF = uiaxes(L); title(st.axF,'Force');  xlabel(st.axF,'Frame'); ylabel(st.axF,'Force');
st.axS = uiaxes(L); title(st.axS,'Signal'); xlabel(st.axS,'Frame');  ylabel(st.axS,'Intensity');
for ax=[st.axF st.axS]
    disableDefaultInteractivity(ax);
    ax.Interactions = [panInteraction zoomInteraction];
    axtoolbar(ax,{'pan','zoomin','zoomout','restoreview'});
end
% new relative-brightness axis
st.axR = uiaxes(L);  title(st.axR,'Relative intensity');
xlabel(st.axR,'Plateau #'); ylabel(st.axR,'Rel. mean (norm=1)');

BC = uigridlayout(L,[1 5]); BC.ColumnWidth={'fit','1x','fit','fit','fit'};
BC.Layout.Row = 4;

st.btnPrev = uibutton(BC,'Text','Prev','ButtonPushedFcn',@(~,~)stepROI(-1));
st.sldROI  = uislider(BC,'Limits',[1 2],'Value',1,'Enable','off'); st.sldROI.ValueChangedFcn=@onRoiSlide;
st.btnNext = uibutton(BC,'Text','Next','ButtonPushedFcn',@(~,~)stepROI(+1));
st.cbExcl  = uicheckbox(BC,'Text','Exclude','ValueChangedFcn',@toggleExclude);
uipanel(BC,'BorderType','none'); % spacer

% -- right: sidebar ---------------------------------------------------
R = uigridlayout(GL,[2 1]); R.Layout.Row=2; R.Layout.Column=2;
R.RowHeight = {'fit','1x'};

% Params panel (scrollable, fixed-width grid)
pp = uipanel(R,'Title','Params & Modes','Scrollable','on'); pp.Layout.Row=1;
gp = uigridlayout(pp,[7 4]);           % 6 rows x 4 columns
gp.ColumnWidth = {100,70,100,70};
gp.RowHeight   = {24,24,24,24,24,24,24};
gp.Padding=[8 6 8 6]; gp.RowSpacing=6; gp.ColumnSpacing=8;

% Row1: Lag / pctFloor
uilabel(gp,'Text','Lag (frames)','HorizontalAlignment','right');
st.edLag = uieditfield(gp,'numeric','Limits',[-500 500],'Value',0,'ValueChangedFcn',@(~,~)applyLag());
uilabel(gp,'Text','pctFloor (%)','HorizontalAlignment','right');
st.edPct = uieditfield(gp,'numeric','Limits',[50 99],'Value',90,'ValueChangedFcn',@paramChanged);

% Row2: minDwell / trim
uilabel(gp,'Text','minDwell','HorizontalAlignment','right');
st.edMinDw = uieditfield(gp,'numeric','Limits',[1 2000],'Value',80,'ValueChangedFcn',@paramChanged);
uilabel(gp,'Text','trim','HorizontalAlignment','right');
st.edTrim  = uieditfield(gp,'numeric','Limits',[0 100],'Value',0,'ValueChangedFcn',@paramChanged);

% Row3: smoothWin / thr×
uilabel(gp,'Text','smoothWin','HorizontalAlignment','right');
st.edSmooth = uieditfield(gp,'numeric','Limits',[3 101],'Value',10,'ValueChangedFcn',@paramChanged);
uilabel(gp,'Text','thr×','HorizontalAlignment','right');
st.edThr = uieditfield(gp,'numeric','Limits',[0.50 3.00], ...
    'Value',1.0,'ValueDisplayFormat','%.2f','ValueChangedFcn',@paramChanged);

% Row4: pad(frames) / Show |dF|
uilabel(gp,'Text','pad (frames)','HorizontalAlignment','right');
st.edPad = uieditfield(gp,'numeric','Limits',[1 200],'Value',5,'ValueChangedFcn',@paramChanged);
st.cbDF = uicheckbox(gp,'Text','Show |dF| on Force','Value',false,'ValueChangedFcn',@(~,~)refreshPlots());
st.cbDF.Layout.Column = [3 4];

% Row5: Auto update / thr label
st.cbAuto = uicheckbox(gp,'Text','Auto update','Value',true);
st.cbAuto.Layout.Column=[1 2];
st.lblStats = uilabel(gp,'Text','thr: -, T=0, P=0','HorizontalAlignment','right');
st.lblStats.Layout.Column=[3 4];
st.cbAuto.ValueChangedFcn = @onAutoToggle;
% Row6: Relative normalization reference
lblRel = uilabel(gp,'Text','Rel. norm ref','HorizontalAlignment','right');
lblRel.Layout.Row    = 6;
lblRel.Layout.Column = 1;
st.ddNorm = uidropdown(gp, ...
    'Items',     {'first&last','first','last','custom'}, ...
    'ItemsData', {'fl','first','last','custom'}, ...
    'Value','fl', ...
    'ValueChangedFcn', @(~,~)updateRelPlot());
st.ddNorm.Layout.Row    = 6;
st.ddNorm.Layout.Column = 2;

st.btnUseSel = uibutton(gp,'Text','Use selection', ...
    'Tooltip','Use the rows selected in the Segments table as the normalisation reference', ...
    'ButtonPushedFcn', @(~,~)setCustomRefFromTable());
st.btnUseSel.Layout.Row    = 6;
st.btnUseSel.Layout.Column = [3 4];

% Segments panel (table + fine adjustment + Export)
sp = uipanel(R,'Title','Segments','Scrollable','on'); sp.Layout.Row=2;
sg = uigridlayout(sp,[4 1]); sg.RowHeight={'1x',40,40}; sg.Padding=[9 6 9 6]; sg.RowSpacing=6;
st.tbl = uitable(sg,'Data',table(uint32([]),uint32([]),'VariableNames',{'start','end'}), ...
    'ColumnEditable',[true true]); st.tbl.Layout.Row=1; st.tbl.ColumnWidth={80,80};
st.tbl.CellEditCallback=@tblEdited; st.tbl.CellSelectionCallback=@tblSelected;

adj = uigridlayout(sg,[1 6]); adj.Layout.Row=2;
adj.ColumnWidth={'fit',40,40,40,40,40};
uilabel(adj,'Text','Step:','HorizontalAlignment','right');
st.edStep = uieditfield(adj,'numeric','Limits',[1 500],'Value',1,'HorizontalAlignment','center');
uibutton(adj,'Text','start-','ButtonPushedFcn',@(~,~)nudge(-1,0));
uibutton(adj,'Text','start+','ButtonPushedFcn',@(~,~)nudge(+1,0));
uibutton(adj,'Text','end-','ButtonPushedFcn',  @(~,~)nudge(0,-1));
uibutton(adj,'Text','end+','ButtonPushedFcn',  @(~,~)nudge(0,+1));
% uibutton(adj,'Text','± grow','ButtonPushedFcn',   @(~,~)growShrink(+1));
% uibutton(adj,'Text','± shrink','ButtonPushedFcn', @(~,~)growShrink(-1));

btnRow = uigridlayout(sg,[1 5]); btnRow.Layout.Row=3; btnRow.ColumnWidth={'1x','1x','1x','1x','1x'};
uibutton(btnRow,'Text','Delete','ButtonPushedFcn',@(~,~)deleteSelected());
uibutton(btnRow,'Text','Exp. Plateau','ButtonPushedFcn',@(~,~)exportCSV('plateau'));
uibutton(btnRow,'Text','Exp. Transit','ButtonPushedFcn',@(~,~)exportCSV('transition'));
uibutton(btnRow,'Text','Exp. Means','ButtonPushedFcn',@(~,~)exportMeans());
uibutton(btnRow,'Text','Exp. Trace','ButtonPushedFcn',@(~,~)exportTrace());

% commit the exclude rectangle (right mouse click)
try iptaddcallback(st.axS,'ButtonDownFcn',@(~,~)maybeCommit()); end %#ok<TRYNC>

%% ----------------------- CALLBACKS ------------------------------------
    function pickFolder(~,~)
        d = uigetdir(st.root,'Select the session root'); if isequal(d,0), return; end
        st.root = d; [tbl,msg] = scanSessions(d);
        if isempty(tbl), uialert(st.fig,sprintf('Fluor.mat not found\n%s',msg),'Not Found'); return; end
        st.sessions = tbl; st.idx = 1;
        st.ddSes.Items = tbl.label; st.ddSes.Value = tbl.label{1};
    end

    function sessionChanged(~,~)
        if isempty(st.sessions), return; end
        ii = find(strcmp(st.ddSes.Value, st.sessions.label),1);
        if ~isempty(ii), st.idx = ii; end
    end

    function loadSession()
        if isempty(st.sessions), return; end
        pth = st.sessions.path{st.idx};
        [ok, D, idStr, err] = loadFluorMat(pth);
        if ~ok, uialert(st.fig,err,'Load Error'); return; end
        st.data = D; st.data.id = idStr; st.excl = cell(1,D.rois);
        if D.rois>=2, st.sldROI.Limits=[1 D.rois]; st.sldROI.Value=1; st.sldROI.Enable='on';
        else,        st.sldROI.Limits=[1 2];      st.sldROI.Value=1; st.sldROI.Enable='off'; end
        [hasF,F] = loadForceAuto(pth, D.frames);
        st.data.hasF=hasF; st.data.F=F(:)';
        st.segPl = uint32(zeros(0,2)); st.segTr=uint32(zeros(0,2));
        refreshPlots(); if hasF, autoDetect(); end
    end

    function refreshPlots()
        % Force
        cla(st.axF);
        if st.data.hasF
            x=1:st.data.frames; y=st.data.F;
            if numel(y)~=st.data.frames, y=interp1(1:numel(y),y,x,'linear','extrap'); end
            hF = plot(st.axF,x,y,'LineWidth',1,'Color',[0.85 0.35 0.15]); hold(st.axF,'on');
            noPick(hF);
        else
            text(st.axF,0.5,0.5,'Force file not found','Units','normalized','HorizontalAlignment','center');
        end

        % Signal
        cla(st.axS);
        if st.data.rois<1, drawnow; return; end
        rid = max(1,min(st.data.rois,round(st.sldROI.Value)));
        hS = plot(st.axS,1:st.data.frames, st.data.Sgnl(:,rid),'LineWidth',1); hold(st.axS,'on');
        title(st.axS,sprintf('Signal (ROI %d)',rid));
        noPick(hS)
        % Overlays
        if st.data.hasF
            showSegsForce(st.axF, st.segPl, st.data.F);
            showSegs(st.axF, st.segTr, [0.85 0.85 0.85]);
            showSegsForce(st.axS, st.segPl, st.data.F);
            showSegs(st.axS, st.segTr, [0.85 0.85 0.85]);
        else
            showSegs(st.axS, st.segPl, [0.85 0.85 0.2]);
            showSegs(st.axS, st.segTr, [0.85 0.85 0.85]);
        end

        % Excludes
        if ~isempty(st.excl) && numel(st.excl)>=rid && ~isempty(st.excl{rid})
            showSegs(st.axS, st.excl{rid}, [1 0.4 0.4]);
        end

        if st.cbDF.Value && st.data.hasF ...
                && isfield(st,'diag') && isstruct(st.diag) ...
                && isfield(st.diag,'dF') && ~isempty(st.diag.dF)

            thrVal = [];
            if isfield(st.diag,'thr') && ~isempty(st.diag.thr) && isnumeric(st.diag.thr)
                thrVal = st.diag.thr;
            end

            % overlay while preserving the current hold state
            wasHold = ishold(st.axF);
            hold(st.axF, 'on');
            overlayDF(st.axF, st.diag.dF, thrVal);
            if ~wasHold, hold(st.axF, 'off'); end
        end
        hold(st.axF,'off');
        hold(st.axS,'off');
        % refresh the table on the right
        st.tbl.Data = array2table(st.segPl, 'VariableNames',{'start','end'});

        % refresh the new relative-brightness plot
        updateRelPlot();

    end

    function updateRelPlot()
        cla(st.axR);
        if st.data.rois<1 || isempty(st.segPl), return; end

        rid = max(1, min(st.data.rois, round(st.sldROI.Value)));
        seg = double(st.segPl);

        % apply per-ROI excludes
        if numel(st.excl)>=rid && ~isempty(st.excl{rid})
            seg = minusSeg(seg, double(st.excl{rid}), st.data.frames);
        end
        if isempty(seg), return; end

        S  = st.data.Sgnl(:, rid);
        Pn = size(seg,1);
        mu = nan(Pn,1); sd = nan(Pn,1);
        for i=1:Pn
            a = seg(i,1); b = seg(i,2);
            v = S(a:b);
            mu(i) = mean(v,'omitnan');
            sd(i) = std(v,0,'omitnan');
        end

        % ---- choose the normalisation reference ----
        mode = st.ddNorm.Value;   % 'fl' | 'first' | 'last' | 'custom'
        switch mode
            case 'fl'
                idx = unique([1, Pn]);                % mean of first and last
            case 'first'
                idx = 1;
            case 'last'
                idx = Pn;
            case 'custom'
                idx = st.customRefRows;
                idx = idx(idx>=1 & idx<=Pn);          % validity
                if isempty(idx)                       % fall back to a safe default when empty
                    idx = unique([1, Pn]);
                end
        end
        baseline = mean(mu(idx),'omitnan');
        if ~isfinite(baseline) || baseline==0, baseline = 1; end

        muN = mu / baseline;
        sdN = sd / baseline;

        x = 1:Pn;
        he =errorbar(st.axR, x, muN, sdN, 'o-', 'LineWidth', 1.2);
        xlim(st.axR, [0.5, Pn+0.5]); grid(st.axR,'on');
        ylim(st.axR, [-0.1 1.5]);
        title(st.axR, sprintf('Relative intensity (ROI %d), ref=%s', rid, mode));
        xlabel(st.axR,'Plateau #'); ylabel(st.axR,'Rel. mean (norm=1)');
        noPick(he);
        noPick(allchild(he));
    end


    function autoDetect()
        if ~st.data.hasF, uialert(st.fig,'A force file is required.','No Force'); return; end
        % ---- UI values as given, only a sensible lower bound ----
        P.smoothWin = max(3,  round(st.edSmooth.Value));   % at least 3
        P.pad       = max(1,  round(st.edPad.Value));      % at least 1
        P.minDwell  = max(1,  round(st.edMinDw.Value));    % at least 1
        P.trim      = max(0,  round(st.edTrim.Value));     % at least 0
        P.pctFloor  = max(10, min(99, round(st.edPct.Value)));   % 10~99
        P.thrScale  = max(0.2, min(3,  st.edThr.Value));         % 0.2~3

        % enforce a minimum dwell so transitions are not eaten by pad/trim
        need = 2*P.pad + 2*P.trim + 3;
        if P.minDwell < need
            P.minDwell = need;
            st.edMinDw.Value = P.minDwell;          % keep the UI in sync
        end

        [pl,tr,diag] = detectByChangePoint(st.data.F, P);
        st.segPl = pl; st.segTr = tr; st.diag = diag;

        st.lblStats.Text = sprintf('thr:%.6g  T=%d, P=%d', ...
            diag.thrH, size(st.segTr,1), size(st.segPl,1));
        applyLag();
    end

    function [pl, tr, diag] = detectByChangePoint(F, P)
        % adaptive threshold + hysteresis + prominence + area criterion
        F = F(:); N = numel(F);
        W = max(3, round(P.smoothWin));
        L = 2*floor(W/2)+1;

        % smoothing and slope
        Ff  = fillmissing(F,'linear','EndValues','nearest');
        Fs  = sgolayfilt(Ff, 3, L);
        dF0 = abs(gradient(Fs));
        % smooth |dF| slightly to stabilise the peaks
        dF  = movmean(dF0, max(3, round(L/5)));

        % adaptive threshold from a global percentile plus local noise (MAD)
        sigma = 1.4826 * mad(dF, 1);                  % robust sigma
        thr0  = prctile(dF, max(10, min(99, P.pctFloor)));
        thrH  = max(P.thrScale * thr0, 2.5*sigma);    % upper threshold for acceptance
        thrL  = 0.55 * thrH;                           % lower threshold for linking

        % minimum spacing / maximum count
        minDist = max(P.minDwell, ceil(0.6*W));
        maxChg  = min(50, max(3, floor(N / max(1, P.minDwell))));

        % -- seed 1: changepts
        cidx = [];
        try
            cidx = findchangepts(Fs,'Statistic','mean', ...
                'MinDistance',minDist,'MaxNumChanges',maxChg);
        catch, cidx = []; end

        % -- seed 2: |dF| peaks (using prominence)
        prom = max(1.5*sigma, 0.2*thrH);
        sep  = max(1, round(minDist/2));
        pk   = islocalmax(dF,'MinSeparation',sep,'MinProminence',prom);
        pidx = find(pk);

        % collect seeds (if none, use the centre of the supra-threshold interval)
        seeds = unique([cidx(:); pidx(:)]);
        if isempty(seeds)
            msk = dF >= thrH;
            d   = diff([false; msk; false]);
            s   = find(d== 1); e = find(d==-1)-1;
            seeds = round((s+e)/2);
        end

        % hysteresis: widen with thrL, then pad; accept on peak or area
        mskLo = dF >= thrL;
        cand  = zeros(0,2);
        for k = 1:numel(seeds)
            s = seeds(k);
            % find where the signal falls off to left and right
            l = s; while l>1   && mskLo(l-1), l=l-1; end
            r = s; while r<N   && mskLo(r+1), r=r+1; end
            if r<l, continue; end

            % pad extension
            a = max(1, l - P.pad);
            b = min(N, r + P.pad);

            % acceptance: peak height or area above baseline
            pmax  = max(dF(l:r));
            area  = sum(max(0, dF(l:r) - thrL));
            areaT = max(thrH * max(1, P.pad*0.8), 2.0*sigma * (r-l+1));

            if (pmax >= thrH) || (area >= areaT)
                cand(end+1,:) = [a b]; %#ok<AGROW>
            end
        end

        % merge candidates
        if isempty(cand)
            tr = uint32(zeros(0,2));
        else
            gap = max(1, round(min(W, P.pad)));     % merge if too close
            tr  = uint32(mergeClose(double(cand), gap));
        end

        % complement -> plateau, then apply trim / minDwell
        if isempty(tr), base = [1 N];
        else,            base = complementSeg(double(tr), N);
        end
        seg = zeros(0,2);
        for i=1:size(base,1)
            a = base(i,1) + P.trim;
            b = base(i,2) - P.trim;
            if b - a + 1 >= P.minDwell
                seg(end+1,:) = [a b]; %#ok<AGROW>
            end
        end
        pl = uint32(guardSeg(seg, N));

        % diagnostics (for the overlay)
        diag = struct('thrH',thrH,'thrL',thrL,'thr0',thr0,'sigma',sigma, ...
            'dF',dF(:),'seeds',seeds(:));
    end

    function applyLag()
        lag = round(st.edLag.Value); N = st.data.frames;
        if isempty(st.segPl) && isempty(st.segTr), refreshPlots(); return; end
        st.segPl = shiftClamp(st.segPl, lag, N);
        st.segTr = shiftClamp(st.segTr, lag, N);
        refreshPlots();
    end

    function onRoiSlide(~,~), refreshPlots(); end
    function stepROI(d)
        if st.data.rois<1, return; end
        v = round(st.sldROI.Value)+d; v=max(1,min(v,st.data.rois));
        st.sldROI.Value=v; refreshPlots();
    end

    function toggleExclude(~,evt)
        if evt.Value
            R = drawrectangle(st.axS,'FaceAlpha',0.15,'Color',[1 0 0]);
            st.currRect = R; st.exclMode=true;
        else
            st.exclMode=false;
            if isfield(st,'currRect') && ~isempty(st.currRect) && isvalid(st.currRect), delete(st.currRect); end
        end
    end

    function maybeCommit(~,~)
        if ~st.exclMode || ~isfield(st,'currRect') || isempty(st.currRect) || ~isvalid(st.currRect), return; end
        xs = st.currRect.Position(1); xe = xs + st.currRect.Position(3);
        s = max(1,floor(xs)); e = min(st.data.frames,ceil(xe));
        rid = max(1,min(st.data.rois,round(st.sldROI.Value)));
        if numel(st.excl)<rid || isempty(st.excl{rid}), st.excl{rid}=uint32([s e]);
        else, st.excl{rid}(end+1,:) = uint32([s e]); end
        st.excl{rid} = mergeSeg(st.excl{rid});
        delete(st.currRect); st.currRect=[]; st.cbExcl.Value=false; refreshPlots();
    end

    function tblEdited(~,~)
        T = st.tbl.Data;
        if isempty(T), st.segPl = uint32(zeros(0,2));
        else,         st.segPl = uint32(table2array(T));
        end
        st.segPl = guardSeg(st.segPl, st.data.frames);
        st.segTr = uint32(complementSeg(double(st.segPl), st.data.frames));
        refreshPlots();
    end

    function deleteSelected()
        T = st.tbl.Data; if isempty(T) || height(T)==0, return; end
        idx = st.tbl.Selection; if isempty(idx), return; end
        T(idx(1),:) = []; st.tbl.Data = T;
        st.segPl = uint32(table2array(T));
        st.segPl = guardSeg(st.segPl, st.data.frames);
        st.segTr = uint32(complementSeg(double(st.segPl), st.data.frames));
        refreshPlots();
    end

    function exportCSV(kind)
        if st.data.rois<1, uialert(st.fig,'No ROI','Export'); return; end

        [defPl, defTr, ~] = defaultSaveNames();
        isPlateau = strcmpi(kind,'plateau');
        defPath   = tern(isPlateau, defPl, defTr);  % default suggested path and file name

        [f,p] = uiputfile(defPath, sprintf('Save %s CSV', kind));
        if isequal(f,0), return; end
        fd = fullfile(p,f);

        rows = cell(0,4);
        for r = 1:st.data.rois
            seg = tern(isPlateau, st.segPl, st.segTr);
            segD = double(seg); if isempty(segD), continue; end
            if numel(st.excl)>=r && ~isempty(st.excl{r})
                segD = minusSeg(segD, double(st.excl{r}), st.data.frames);
            end
            for i=1:size(segD,1)
                rows(end+1,:) = {st.data.id, r, segD(i,1), segD(i,2)}; %#ok<AGROW>
            end
        end
        if isempty(rows), uialert(st.fig,'No segment to export.','Export'); return; end

        T = cell2table(rows,'VariableNames',{'id','roi','start','end'});
        if exist(fd,'file')==2
            try
                T0=readtable(fd); T=unique([T0;T],'rows');
            end
        end
        writetable(T,fd);
        uialert(st.fig, sprintf('Saved\n%s', fd), 'Saved');
    end

    function y = tern(cond,a,b), if cond, y=a; else, y=b; end, end

    function exportMeans()
        if st.data.rois<1, uialert(st.fig,'No ROI','Export'); return; end

        [~, ~, defMn] = defaultSaveNames();
        [f,p] = uiputfile(defMn, 'Save Plateau Means CSV');
        if isequal(f,0), return; end
        fd = fullfile(p,f);

        rows = cell(0,7);  % id, roi, seg_idx, start, end, mean, std
        for r=1:st.data.rois
            seg = double(st.segPl); if isempty(seg), continue; end
            S = st.data.Sgnl(:,r);
            for i=1:size(seg,1)
                a=seg(i,1); b=seg(i,2);
                v = S(a:b); mu = mean(v,'omitnan'); sd = std(v,0,'omitnan');
                rows(end+1,:) = {st.data.id, r, i, a, b, mu, sd}; %#ok<AGROW>
            end
        end
        if isempty(rows), uialert(st.fig,'No plateau found.','Export'); return; end

        T = cell2table(rows,'VariableNames',{'id','roi','seg','start','end','mean','std'});
        writetable(T,fd);
        uialert(st.fig, sprintf('Saved\n%s', fd), 'Saved');
    end
    function setCustomRefFromTable()
        if isempty(st.selRowsLast)
            uialert(st.fig,'Select at least one row in the Segments table to use as the reference.','No selection');
            return;
        end
        st.customRefRows = st.selRowsLast(:)';     % remember
        st.ddNorm.Value  = 'custom';               % switch the mode to custom
        updateRelPlot();
    end

    function loadForceManual()
        if st.data.frames<1, uialert(st.fig,'Load a session first','Load Force'); return; end
        [f,p] = uigetfile({'*.dat;*.txt;*.csv','Force file'},'Select force file', st.root);
        if isequal(f,0), return; end
        F = readForce(fullfile(p,f), st.data.frames);
        if isempty(F), uialert(st.fig,'Could not read the file','Force'); return; end
        st.data.hasF = true; st.data.F = F(:)'; refreshPlots();
    end

%% ----------------------- HELPERS --------------------------------------
    function [ok, D, idStr, err] = loadFluorMat(matPath)
        ok=false; D=struct(); err=''; idStr = makeId(matPath);
        try
            S = load(fullfile(matPath,'Fluor.mat'));
            S1 = S.Sgnl; if size(S1,1) < size(S1,2), S1 = S1'; end
            D.Sgnl = S1; D.frames = size(S1,1); D.rois = size(S1,2); ok=true;
        catch ME, err=ME.message; end
    end

    function [tbl,msg] = scanSessions(root)
        msg=''; d = dir(fullfile(root,'**','Fluor.mat'));
        if isempty(d), tbl=table(); msg='no Fluor.mat'; return; end
        paths = arrayfun(@(x)x.folder,d,'uni',0);
        label = cellfun(@makeId,paths,'uni',0);
        tbl = table(paths',label','VariableNames',{'path','label'});
    end

    function id = makeId(p)
        [~,id] = fileparts(p); id = regexprep(id,'_Output$','');
    end

    function [hasF,F] = loadForceAuto(matPath, frames)
        hasF=false; F=[]; id=makeId(matPath); dirp=matPath;
        cand = {fullfile(dirp,sprintf('%s_force.dat',id)), ...
            fullfile(dirp,sprintf('%s_force.txt',id)), ...
            fullfile(dirp,sprintf('%s_force.csv',id))};
        cand = cand(cellfun(@(f)exist(f,'file')==2,cand));
        if isempty(cand)
            D=[dir(fullfile(dirp,'*force*.dat')); dir(fullfile(dirp,'*force*.txt')); dir(fullfile(dirp,'*force*.csv'))];
            if ~isempty(D), [~,ix]=max([D.datenum]); cand={fullfile(D(ix).folder,D(ix).name)}; end
        end
        for k=1:numel(cand)
            F = readForce(cand{k}, frames); if ~isempty(F), hasF=true; return; end
        end
        mp = fullfile(dirp,sprintf('%s_magnet_position.dat',id));
        if exist(mp,'file')==2, F=readForce(mp,frames); hasF=~isempty(F); end
    end

    function F = readForce(fp, frames)
        F=[]; T=[];
        try, T = readmatrix(fp); catch, T=[]; end
        if isempty(T) || ~isnumeric(T)
            try
                opts = detectImportOptions(fp,'Delimiter',{' ','	',','});
                vt = opts.VariableTypes; keep = ismember(vt,{'double','single'});
                if any(keep), opts.SelectedVariableNames = opts.VariableNames(keep); end
                T = table2array(readtable(fp,opts));
            catch, T=[]; end
        end
        if isempty(T), return; end
        nf = sum(isfinite(T),1); if all(nf<2), return; end
        cand=find(nf>=2); v=zeros(size(cand));
        for i=1:numel(cand), c=T(:,cand(i)); c=c(isfinite(c)); v(i)=var(c,0,'omitnan'); end
        [~,ix]=max(v); f=T(:,cand(ix)); idx=find(isfinite(f)); if numel(idx)<2, return; end
        x=idx(:); f=f(idx); if any(diff(x)<=0), x=(1:numel(f))'; end
        try
            F = interp1(x,f,(1:frames)','linear','extrap');
            F = fillmissing(F,'linear','EndValues','nearest'); F=F(:)';
        catch, F=[]; end
    end
    function exportTrace()
        if st.data.rois<1
            uialert(st.fig,'No ROI','Export');
            return;
        end

        % default save location/name: session folder/<id>_trace.csv
        [~,~,~, defTrc] = defaultSaveNames();
        [f,p] = uiputfile(defTrc, 'Save Frame Trace CSV');
        if isequal(f,0), return; end
        fd = fullfile(p,f);

        rows = cell(0,8);   % id, roi, frame, intensity, rel, phase, pl_idx, tr_idx

        for r = 1:st.data.rois
            N = st.data.frames;
            S = st.data.Sgnl(:,r);

            % --- label plateau / transition
            pl = double(st.segPl);
            tr = double(st.segTr);

            % rebuild plateaus with per-ROI excludes applied (used for the mean and the normalisation)
            pl_for_mu = pl;
            if numel(st.excl)>=r && ~isempty(st.excl{r})
                pl_for_mu = minusSeg(pl_for_mu, double(st.excl{r}), N);
            end

            % plateau/transition index vectors
            pl_idx = zeros(N,1,'uint16');
            for i=1:size(pl,1), pl_idx(pl(i,1):pl(i,2)) = i; end
            tr_idx = zeros(N,1,'uint16');
            for i=1:size(tr,1), tr_idx(tr(i,1):tr(i,2)) = i; end

            % exclude mask (per ROI)
            excl = false(N,1);
            if numel(st.excl)>=r && ~isempty(st.excl{r})
                for i=1:size(st.excl{r},1)
                    a = max(1, double(st.excl{r}(i,1)));
                    b = min(N, double(st.excl{r}(i,2)));
                    excl(a:b) = true;
                end
            end

            % phase label (priority: excluded > plateau > transition > none)
            phase = repmat("none", N, 1);
            phase(tr_idx>0) = "transition";
            phase(pl_idx>0) = "plateau";
            phase(excl)     = "excluded";

            % --- normalisation reference (reflects the current UI setting)
            baseline = 1.0;
            if ~isempty(pl_for_mu)
                mu = nan(size(pl_for_mu,1),1);
                for i=1:size(pl_for_mu,1)
                    a = pl_for_mu(i,1); b = pl_for_mu(i,2);
                    mu(i) = mean(S(a:b), 'omitnan');
                end

                mode = st.ddNorm.Value;   % 'fl' | 'first' | 'last' | 'custom'
                Pn   = size(pl_for_mu,1);
                switch mode
                    case 'fl',    idx = unique([1, Pn]);
                    case 'first', idx = 1;
                    case 'last',  idx = Pn;
                    case 'custom'
                        idx = st.customRefRows;
                        idx = idx(idx>=1 & idx<=Pn);
                        if isempty(idx), idx = unique([1, Pn]); end
                end
                b = mean(mu(idx), 'omitnan');
                if isfinite(b) && b~=0, baseline = b; end
            end

            % --- accumulate rows (all frames of ROI r)
            rel = S / baseline;   % relative intensity
            idstr = string(st.data.id);
            for n = 1:N
                rows(end+1,:) = { idstr, r, n, S(n), rel(n), char(phase(n)), pl_idx(n), tr_idx(n) }; %#ok<AGROW>
            end
        end

        T = cell2table(rows, 'VariableNames', ...
            {'id','roi','frame','intensity','rel','phase','pl_idx','tr_idx'});
        writetable(T, fd);
        uialert(st.fig, sprintf('Saved\n%s', fd), 'Saved');
    end

% ---- segments utilities
    function seg = runs(mask, minw)
        if ~any(mask), seg=zeros(0,2); return; end
        d = diff([0 mask(:)' 0]); s=find(d==1); e=find(d==-1)-1; L=e-s+1; keep=L>=minw; seg=[s(keep)' e(keep)'];
    end
    function seg = mergeClose(seg, gap)
        if isempty(seg), return; end
        seg = sortrows(seg,1); out = seg(1,:);
        for i=2:size(seg,1)
            if seg(i,1) <= out(end,2)+gap, out(end,2)=max(out(end,2),seg(i,2));
            else, out(end+1,:) = seg(i,:); end %#ok<AGROW>
        end, seg=out;
    end
    function seg = mergeSeg(seg)
        if isempty(seg), seg=uint32(zeros(0,2)); return; end
        seg = sortrows(double(seg),1); out = seg(1,:);
        for i=2:size(seg,1)
            if seg(i,1) <= out(end,2)+1, out(end,2)=max(out(end,2),seg(i,2));
            else, out(end+1,:) = seg(i,:); end %#ok<AGROW>
        end, seg=uint32(out);
    end
    function seg = complementSeg(seg, N)
        if isempty(seg), seg=[1 N]; return; end
        seg = sortrows(double(seg),1); out=[]; s=1;
        for i=1:size(seg,1)
            if seg(i,1)>s, out(end+1,:)=[s seg(i,1)-1]; end %#ok<AGROW>
            s = seg(i,2)+1;
        end
        if s<=N, out(end+1,:)=[s N]; end, seg=out;
    end
    function seg = guardSeg(seg, N)
        if isempty(seg), seg=uint32(zeros(0,2)); return; end
        seg(:,1)=max(1,seg(:,1)); seg(:,2)=min(N,seg(:,2)); seg=seg(seg(:,2)>=seg(:,1),:);
    end
    function seg = shiftClamp(seg, lag, N)
        if isempty(seg), return; end
        seg = int64(seg)+lag; seg = uint32(max(1,min(N,seg))); seg=seg(seg(:,2)>=seg(:,1),:);
    end
    function showSegs(ax, seg, color)
        if isempty(seg), return; end
        yl=ylim(ax); h=yl(2)-yl(1); y0=yl(1);
        for i=1:size(seg,1)
            x=double([seg(i,1) seg(i,2)]); w=x(2)-x(1)+1; if w<=0, continue; end
            p = patch(ax,[x(1) x(2) x(2) x(1)],[y0 y0 y0+h y0+h],color,'FaceAlpha',0.22,'EdgeColor','none');
            noPick(p);
        end
    end
    function showSegsForce(ax, seg, F)
        if isempty(seg) || isempty(F), return; end
        F = F(:)'; Fmin=min(F); Fmax=max(F); nbins=7; cmap=parula(nbins); alpha=0.18;
        yl=ylim(ax); h=yl(2)-yl(1); y0=yl(1);
        for i=1:size(seg,1)
            s=double(seg(i,1)); e=double(seg(i,2)); if e<s, continue; end
            fmean=mean(F(s:e),'omitnan');
            t=(fmean-Fmin)/(Fmax-Fmin+eps); bin=1+floor(t*(nbins-1)); bin=max(1,min(nbins,bin));
            c=cmap(bin,:);
            p = patch(ax,[s e e s],[y0 y0 y0+h y0+h],c,'FaceAlpha',alpha,'EdgeColor','none');
            noPick(p);
        end
    end
    function seg = minusSeg(seg, exc, N)
        if isempty(seg) || isempty(exc), return; end
        N = max([N, seg(:)' exc(:)']);
        mask=false(1,N); for i=1:size(seg,1), mask(seg(i,1):seg(i,2))=true; end
        for i=1:size(exc,1), s=max(1,exc(i,1)); e=min(N,exc(i,2)); mask(s:e)=false; end
        seg = runs(mask,1);
    end

    function paramChanged(~,~)
        if st.cbAuto.Value && st.data.hasF
            autoDetect();
        else
            refreshPlots();
        end
    end

    function tblSelected(~,evt)
        if isempty(evt.Indices)
            st.selRow = 0;
            st.selRowsLast = [];
        else
            st.selRow       = evt.Indices(1);            % the first row is for fine adjustment
            st.selRowsLast  = unique(evt.Indices(:,1));  % candidate normalisation references (multiple)
        end
        if strcmp(st.ddNorm.Value,'custom'), updateRelPlot(); end
    end

    function i = getSelRow()
        if st.selRow<1 || st.selRow>size(st.segPl,1)
            i=[]; uialert(st.fig,'Select the plateau to adjust in the table first.','Select segment');
        else
            i=st.selRow;
        end
    end
    function nudge(dStart,dEnd)
        i=getSelRow(); if isempty(i), return; end
        step=max(1,round(st.edStep.Value)); N=st.data.frames; seg=double(st.segPl);
        seg(i,1)=max(1, seg(i,1)+dStart*step);
        seg(i,2)=min(N, seg(i,2)+dEnd*step);
        if seg(i,2)<seg(i,1), seg(i,2)=seg(i,1); end
        st.segPl=uint32(sortrows(seg,1)); st.tbl.Data=array2table(st.segPl,'VariableNames',{'start','end'}); refreshPlots();
    end
    function growShrink(sign)
        i=getSelRow(); if isempty(i), return; end
        step=max(1,round(st.edStep.Value)); N=st.data.frames; seg=double(st.segPl);
        if sign>0, seg(i,1)=max(1,seg(i,1)-step); seg(i,2)=min(N,seg(i,2)+step);
        else, seg(i,1)=min(seg(i,1)+step,seg(i,2)); seg(i,2)=max(seg(i,2)-step,seg(i,1)); end
        st.segPl=uint32(sortrows(seg,1)); st.tbl.Data=array2table(st.segPl,'VariableNames',{'start','end'}); refreshPlots();
    end
    function onAutoToggle(~,evt)
        if evt.Value && st.data.hasF
            autoDetect();      % re-detect once immediately when switched on
        end
    end

    function overlayDF(ax, dF, thr)
        % scale |dF| to the axis range, draw it as a dashed line, and
        % also show the threshold line when thr is given.
        if isempty(dF) || ~isvalid(ax), return; end
        yl = ylim(ax);
        lo = min(dF); hi = max(dF);
        if ~isfinite(lo) || ~isfinite(hi) || hi==lo, return; end

        y = (dF(:) - lo) ./ (hi - lo + eps);          % 0..1
        y = yl(1) + y * (yl(2) - yl(1));              % map to the axis range
        ph = plot(ax, 1:numel(dF), y, '--', 'LineWidth', 0.9, 'Color', [0.2 0.2 0.2]);
        noPick(ph);

        if nargin >= 3 && ~isempty(thr) && isfinite(thr)
            ty = (thr - lo) / (hi - lo + eps);        % 0..1
            ty = yl(1) + ty * (yl(2) - yl(1));        % map to the axis range
            ln = line(ax, [1 numel(dF)], [ty ty], 'LineStyle', ':', 'Color', [0.35 0.35 0.35]);
            noPick(ln);
        end
    end
    function [defPl, defTr, defMn, defTrc] = defaultSaveNames()
        sesDir = st.sessions.path{st.idx};   % folder holding Fluor.mat
        base   = st.data.id;                 % strip *_Output from the folder name
        defPl  = fullfile(sesDir, sprintf('%s_plateau.csv', base));
        defTr  = fullfile(sesDir, sprintf('%s_transit.csv', base));
        defMn  = fullfile(sesDir, sprintf('%s_means.csv',   base));
        defTrc = fullfile(sesDir, sprintf('%s_trace.csv',   base));   % <- added
    end
    function noPick(h)
        % block datatip/pick on graphics objects
        if isempty(h), return; end
        try
            set(h,'HitTest','off','PickableParts','none');
        catch
            for k = 1:numel(h)
                try, h(k).HitTest = 'off'; end
                try, h(k).PickableParts = 'none'; end
            end
        end
    end

end
