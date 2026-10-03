function FluorSegmenterLite_v2
% FluorSegmenterLite (Integrated)
% - 기존 FluorSegmenterLite에 MeansCollectorLite의
%   "선택(use)/프리뷰/요약 내보내기" 핵심을 통합 (한 화면에서 완료)
% - 루트/세션 로드 → 세그먼트 검출/편집 → 즉시 평균표 생성
%   → ROI 가시/선택 토글 → Save selected / Export summary / Export wide
% - Signal/Stats 툴박스 미보유 시 sgolayfilt / findchangepts 폴백 포함

%% ----------------------- STATE -----------------------------------------
st = struct();
st.root   = pwd;
st.data   = struct('frames',0,'rois',0,'hasF',false,'F',[], ...
    'Sgnl',[], 'Bgnd',[], 'Raw',[], 'id','');
st.sessions = table(); st.idx = 1;
st.segPl  = uint32(zeros(0,2));
st.segTr  = uint32(zeros(0,2));
st.excl   = {};                 % ROI별 exclude 사각형 목록
st.diag   = struct();           % 보조정보(|dF| 등)
st.selRow = 0;                  % 표에서 선택된 행
st.customRefRows = [];          % 사용자가 지정한 레퍼런스 plateau 행 번호들
st.selRowsLast   = [];          % 표에서 마지막으로 선택된 행(복수 가능)
st.hl = struct('F',[], 'S',[]);
st.lastSegPl = uint32(zeros(0,2));

% 통합: 현 세션의 평균표(Collector 기능)
st.meansT = table();            % columns: use,id,roi,seg,len,mean,std
st.visRois = [];               % 프리뷰에 표시할 ROI 목록
st.useMap   = containers.Map('KeyType','char','ValueType','logical'); % 선택 on/off 누적
st.meanCache = containers.Map('KeyType','char','ValueType','any');    % 선택키 → {id,roi,seg,len,mean,std}
st.segCache  = containers.Map('KeyType','char','ValueType','any');
st.isLoading = false;

%% ----------------------- UI SHELL --------------------------------------
st.fig = uifigure('Name','Fluor Segmenter (Integrated)', ...
    'Position',[100 100 1280 820], 'AutoResizeChildren','on');
try st.fig.WindowState = 'maximized'; catch; end   % 화면에 맞게 자동 최대화

GL = uigridlayout(st.fig,[2 2]);
GL.RowHeight   = {40,'1x'};
GL.ColumnWidth = {'1x', 520};       % 우측 사이드바 폭 증가

% ── Toolbar ─────────────────────────────────────────────────────────────
TB = uigridlayout(GL,[1 6]);
TB.Layout.Row = 1; TB.Layout.Column = [1 2];
TB.ColumnWidth = {'1x','fit','fit','fit','fit','fit'};
TB.Padding = [6 4 6 4];

st.btnPick = uibutton(TB,'Text','루트 선택 ...','ButtonPushedFcn',@pickFolder);
st.btnPick.Layout.Column = 1;

st.ddSes = uidropdown(TB,'Items',{'(루트 선택 필요)'},'Value','(루트 선택 필요)');
st.ddSes.Layout.Column = 2; st.ddSes.ValueChangedFcn = @sessionChanged;

st.btnLoad = uibutton(TB,'Text','세션 로드','ButtonPushedFcn',@(~,~)loadSession());
st.btnLoad.Layout.Column = 3;

st.btnAuto = uibutton(TB,'Text','Auto Detect','ButtonPushedFcn',@(~,~)autoDetect());
st.btnAuto.Layout.Column = 4;

st.btnLoadF = uibutton(TB,'Text','Load Force...','ButtonPushedFcn',@(~,~)loadForceManual());
st.btnLoadF.Layout.Column = 5;

spacer = uipanel(TB,'BorderType','none');  % spacer
spacer.Layout.Row = 1;
spacer.Layout.Column = 6;

% ── 좌측: 그래프 영역 ──────────────────────────────────────────────────
L = uigridlayout(GL,[4 1]); L.Layout.Row=2; L.Layout.Column=1;
L.RowHeight = {260, 240, 180, 52}; L.Padding=[8 8 8 8];

st.axF = uiaxes(L); title(st.axF,'Force');  xlabel(st.axF,'Frame'); ylabel(st.axF,'Force');
st.axS = uiaxes(L); title(st.axS,'Signal'); xlabel(st.axS,'Frame');  ylabel(st.axS,'Intensity');
for ax=[st.axF st.axS]
    disableDefaultInteractivity(ax);
    ax.Interactions = [panInteraction zoomInteraction];
    axtoolbar(ax,{'pan','zoomin','zoomout','restoreview'});
end
% 새 상대밝기 축
st.axR = uiaxes(L);  title(st.axR,'Relative intensity');
xlabel(st.axR,'Plateau #'); ylabel(st.axR,'Rel. mean (norm=1)');

BC = uigridlayout(L,[1 5]); BC.ColumnWidth={'fit','1x','fit','fit','fit'}; BC.Layout.Row = 4;

st.btnPrev = uibutton(BC,'Text','Prev','ButtonPushedFcn',@(~,~)stepROI(-1));
st.sldROI  = uislider(BC,'Limits',[1 2],'Value',1,'Enable','off'); st.sldROI.ValueChangedFcn=@onRoiSlide;st.sldROI.ValueChangingFcn = @onRoiChanging;
st.btnNext = uibutton(BC,'Text','Next','ButtonPushedFcn',@(~,~)stepROI(+1));
st.cbExcl  = uicheckbox(BC,'Text','Exclude','ValueChangedFcn',@toggleExclude);
uipanel(BC,'BorderType','none'); % spacer

% ── 우측: 사이드바 ─────────────────────────────────────────────────────
R = uigridlayout(GL,[3 1]); R.Layout.Row=2; R.Layout.Column=2;
R.RowHeight = {'fit','1.4x','1.2x'};  % 마지막에 통합 패널 배치

% Params 패널 (스크롤 가능, 고정폭 그리드)
pp = uipanel(R,'Title','Params & Modes','Scrollable','on'); pp.Layout.Row=1;
gp = uigridlayout(pp,[7 4]);
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
lblRel.Layout.Row    = 6; lblRel.Layout.Column = 1;
st.ddNorm = uidropdown(gp, ...
    'Items',     {'first&last','first','last','custom'}, ...
    'ItemsData', {'fl','first','last','custom'}, ...
    'Value','fl', ...
    'ValueChangedFcn', @(~,~)updateRelPlot());
st.ddNorm.Layout.Row    = 6; st.ddNorm.Layout.Column = 2;

st.btnUseSel = uibutton(gp,'Text','Use selection', ...
    'Tooltip','Segments 표에서 선택한 행(복수 가능)을 정규화 기준으로 사용', ...
    'ButtonPushedFcn', @(~,~)setCustomRefFromTable());
st.btnUseSel.Layout.Row    = 6; st.btnUseSel.Layout.Column = [3 4];

% Segments 패널 (표 + 미세조정 + Export)
sp = uipanel(R,'Title','Segments','Scrollable','on'); sp.Layout.Row=2;
sg = uigridlayout(sp,[4 1]); sg.RowHeight = {'1x','fit','fit','fit'}; sg.Padding=[9 6 9 6]; sg.RowSpacing = 6;
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

btnRow = uigridlayout(sg,[1 2]);
btnRow.Layout.Row    = 3;
btnRow.ColumnWidth   = {'fit','fit'};
btnRow.ColumnSpacing = 8;
btnRow.Padding       = [0 0 0 0];

uibutton(btnRow,'Text','Export Seg (S/B/R)', ...
    'Tooltip','Choose a folder → save both: _segmeans_all.csv and _segframes_all.csv', ...
    'ButtonPushedFcn', @(~,~)exportSegmentBoth());

uibutton(btnRow,'Text','Export Tr (S/B/R)', ...
    'Tooltip','Choose a folder → save both: _trmeans_all.csv and _trframes_all.csv', ...
    'ButtonPushedFcn', @(~,~)exportTrBoth());

set(findall(btnRow,'Type','uibutton'),'FontSize',10);
% 1) exclude 커밋 콜백 부착 부분
try
    iptaddcallback(st.axS,'ButtonDownFcn',@(~,~)maybeCommit());
catch
    % Image Processing Toolbox 없거나 iptaddcallback 미존재 시 무시
end

% ── 통합 패널: Per-ROI Means (선택/프리뷰/내보내기) ───────────────────
cp = uipanel(R,'Title','Per-ROI Means (select & export)','Scrollable','on'); cp.Layout.Row=3;
CG = uigridlayout(cp,[4 1]); CG.RowHeight = {'fit',200,'1x','fit'}; CG.Padding=[8 6 8 6]; CG.RowSpacing=8;

% 상단 툴바(ROI 선택/일괄 토글)
CT = uigridlayout(CG,[1 9]); CT.Layout.Row=1; CT.ColumnWidth={'fit',90,8,'fit','fit','fit','1x','fit','fit'}; CT.RowHeight={26}; CT.Padding=[0 0 0 0];
uilabel(CT,'Text','ROI:','HorizontalAlignment','right');
st.ddRoiM = uidropdown(CT,'Items',{'-'},'Value','-', ...
    'ValueChangedFcn',@onMeansRoiChanged,'FontSize',10);
uipanel(CT,'BorderType','none');
uibutton(CT,'Text','Use',   'Tooltip','선택 ROI의 모든 행을 use=on', 'ButtonPushedFcn',@(~,~)setUseForROI(true,false),'FontSize',10);
uibutton(CT,'Text','Clear', 'Tooltip','선택 ROI의 모든 행을 use=off','ButtonPushedFcn',@(~,~)setUseForROI(false,false),'FontSize',10);
uibutton(CT,'Text','Only',  'Tooltip','선택 ROI만 on, 나머지 off', 'ButtonPushedFcn',@(~,~)setUseForROI(true,true),'FontSize',10);
uipanel(CT,'BorderType','none');
uibutton(CT,'Text','◀','Tooltip','Prev ROI','FontSize',10,'ButtonPushedFcn',@(~,~)stepRoiMean(-1));
uibutton(CT,'Text','▶','Tooltip','Next ROI','FontSize',10,'ButtonPushedFcn',@(~,~)stepRoiMean(+1));

% 프리뷰 플롯
st.axM = uiaxes(CG); st.axM.Layout.Row=2; disableDefaultInteractivity(st.axM);
st.axM.Interactions=[panInteraction zoomInteraction]; axtoolbar(st.axM,{'pan','zoomin','zoomout','restoreview'});
title(st.axM,'Means per SEG (모든 ROI 표시, 선택 ROI 강조)'); xlabel(st.axM,'SEG'); ylabel(st.axM,'mean');

% 평균표 테이블 (스크롤)
TP = uipanel(CG,'Scrollable','on'); TP.Layout.Row=3; TGL = uigridlayout(TP,[1 1]);
TGL.RowHeight={'1x'}; TGL.ColumnWidth={'1x'}; TGL.Padding=[0 0 0 0];
st.tblMeans = uitable(TGL,'Data',table(),'RowStriping','on');
st.tblMeans.CellEditCallback = @(~,~) syncUseMap();


% 하단 버튼줄
BR = uigridlayout(CG,[1 5]);
BR.Layout.Row = 4;
BR.ColumnWidth = {'fit','fit','fit','fit','fit'};   % 버튼 폭을 텍스트에 맞춤
BR.ColumnSpacing = 8;
BR.Padding = [0 0 0 0];
uibutton(BR,'Text','All on','ButtonPushedFcn',@(~,~)bulkUse(true));
uibutton(BR,'Text','All off','ButtonPushedFcn',@(~,~)bulkUse(false));
uibutton(BR,'Text','Save sel.','ButtonPushedFcn',@(~,~)saveSelected());
uibutton(BR,'Text','Summary','ButtonPushedFcn',@(~,~)exportSummary());
uibutton(BR,'Text','Wide','ButtonPushedFcn',@(~,~)exportMergedWideAccum());
set(findall(BR,'Type','uibutton'),'FontSize',10);

    function syncUseMap()
        T = st.tblMeans.Data;
        if isempty(T), return; end
        T = ensureUseCol(T);
        T = enforceSingleRoiForCurrentSession(T);

        st.tblMeans.Data = T;
        st.meansT       = T;

        % 현재 ROI만 map에 반영(참/거짓 모두)
        curRoi = uint16(max(1, min(st.data.rois, round(st.sldROI.Value))));
        m = (uint16(T.roi) == curRoi) & (string(T.id) == string(st.data.id));
        idx = find(m).';
        % 먼저 현재 세션·현재 ROI 키들을 깔끔히 삭제
        purgeOtherRoiKeysForCurrentSession(curRoi);   % 다른 ROI 청소
        % 그리고 현재 ROI의 모든 seg 키를 재설정
        sid = lower(strrep(currentSessionKey(),'\','/'));
        for ii = idx
            k = sprintf('%s|%u|%u', sid, uint16(T.roi(ii)), uint16(T.seg(ii)));
            st.useMap(k) = logical(T.use(ii));
            if ~T.use(ii)
                % false인 경우 map에 굳이 남겨두고 싶지 않다면 삭제해도 무방
                % remove(st.useMap, k);
            end
        end
    end


%% ----------------------- CALLBACKS ------------------------------------
    function pickFolder(~,~)
        d = uigetdir(st.root,'세션 루트 선택'); if isequal(d,0), return; end
        st.root = d; [tbl,msg] = scanSessions(d);
        if isempty(tbl), uialert(st.fig,sprintf('Fluor.mat을 찾지 못했습니다\n%s',msg),'Not Found'); return; end
        st.sessions = tbl; st.idx = 1;
        st.ddSes.Items = tbl.label; st.ddSes.Value = tbl.label{1};
    end

    function sessionChanged(~,~)
        if isempty(st.sessions), return; end
        ii = find(strcmp(st.ddSes.Value, st.sessions.label),1);
        if ~isempty(ii), st.idx = ii; end
        st.cbAuto.Value = false;
    end

    function loadSession()
        if isempty(st.sessions), return; end
        st.isLoading = true;                          % ★ 시작: 콜백 무시
        % UI/상태 초기화 (파일간 오염 방지)
        st.selRow = 0; st.selRowsLast = [];
        if isfield(st,'ddRoiM') && isvalid(st.ddRoiM)
            st.ddRoiM.Items = {'-'}; st.ddRoiM.Value = '-';  % ★ 임시 초기화
        end

        pth = st.sessions.path{st.idx};
        [ok, D, idStr, err] = loadFluorMat(pth);
        if ~ok
            st.isLoading = false; uialert(st.fig,err,'Load Error'); return;
        end
        st.data = D; st.data.id = idStr; st.excl = cell(1,D.rois); st.loadedPath = pth;

        % 좌측 슬라이더를 '항상 1'로 고정 시작 (파일 간 선택 ROI 전파 방지)
        if D.rois>=2
            st.sldROI.Limits=[1 D.rois]; st.sldROI.Value=1; st.sldROI.Enable='on';
        else
            st.sldROI.Limits=[1 2]; st.sldROI.Value=1; st.sldROI.Enable='off';
        end
        setRoiSliderTicks();

        [hasF,F] = loadForceAuto(pth, D.frames);
        st.data.hasF=hasF; st.data.F=F(:)';
        st.segPl = uint32(zeros(0,2)); st.segTr=uint32(zeros(0,2));

        refreshPlots(); if hasF, autoDetect(); end

        % 평균표/우측 ROI 드롭다운 구성 (이 시점에서 좌측 ROI=1 기준으로 세팅됨)
        rebuildMeansTable(); refreshMeansPlot();

        st.isLoading = false;                          % ★ 끝: 콜백 허용
    end

    function refreshPlots()
        flushUseEdits();
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
            if isfield(st.diag,'thrH')
                thrVal = st.diag.thrH;
            end

            % 현재 hold 상태를 보존한 채 오버레이
            wasHold = ishold(st.axF);
            hold(st.axF, 'on');
            overlayDF(st.axF, st.diag.dF, thrVal);
            if ~wasHold, hold(st.axF, 'off'); end
        end
        hold(st.axF,'off');
        hold(st.axS,'off');
        % 우측 표 갱신
        st.tbl.Data = array2table(st.segPl, 'VariableNames',{'start','end'});
        % 기존 하이라이트 제거(세그먼트 재계산/표 수정 시 깔끔하게)
        try if all(isvalid(st.hl.F)), delete(st.hl.F); end, catch, end
        try if all(isvalid(st.hl.S)), delete(st.hl.S); end, catch, end

        % 새 상대밝기 그래프 갱신
        updateRelPlot();

        % ── 평균표/프리뷰 갱신을 '한 번만' 하도록 정리
        didRebuild = ~isequal(st.segPl, st.lastSegPl);
        if didRebuild
            rebuildMeansTable();            % 내부에서 updateMeansTableUI() 호출됨
            st.lastSegPl = st.segPl;
            % (여기서 refreshMeansPlot()을 직접 호출하지 않음: rebuild 내에서 이미 실행)
        else
            refreshMeansPlot();             % 세그먼트 안 바뀐 경우에만 1회
        end
    end

    function updateRelPlot()
        cla(st.axR);
        if st.data.rois<1 || isempty(st.segPl), return; end

        rid = max(1, min(st.data.rois, round(st.sldROI.Value)));
        seg = double(st.segPl);

        % ROI별 exclude 반영
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

        % ---- 정규화 기준 선택 ----
        mode = st.ddNorm.Value;   % 'fl' | 'first' | 'last' | 'custom'
        switch mode
            case 'fl'
                idx = unique([1, Pn]);                % 첫+끝 평균
            case 'first'
                idx = 1;
            case 'last'
                idx = Pn;
            case 'custom'
                idx = st.customRefRows;
                idx = idx(idx>=1 & idx<=Pn);          % 유효성
                if isempty(idx)                       % 비어있으면 안전한 기본
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
        r = [min(muN-sdN) max(muN+sdN)];
        if all(isfinite(r))
            pad = 0.1*max(eps, r(2)-r(1));
            ylim(st.axR, [r(1)-pad, r(2)+pad]);
        end
        title(st.axR, sprintf('Relative intensity (ROI %d), ref=%s', rid, mode));
        xlabel(st.axR,'Plateau #'); ylabel(st.axR,'Rel. mean (norm=1)');
        noPick(he);
    end

    function autoDetect()
        if ~st.data.hasF, uialert(st.fig,'Force가 필요합니다.','No Force'); return; end
        % ---- UI 값 그대로, 합리적 하한만 ----
        P.smoothWin = max(3,  round(st.edSmooth.Value));   % 3 이상
        P.pad       = max(1,  round(st.edPad.Value));      % 1 이상
        P.minDwell  = max(1,  round(st.edMinDw.Value));    % 1 이상
        P.trim      = max(0,  round(st.edTrim.Value));     % 0 이상
        P.pctFloor  = max(10, min(99, round(st.edPct.Value)));   % 10~99
        P.thrScale  = max(0.2, min(3,  st.edThr.Value));         % 0.2~3

        % 전이가 pad/trim에 먹히지 않도록 최소 체류 보정
        need = 2*P.pad + 2*P.trim + 3;
        if P.minDwell < need
            P.minDwell = need;
            st.edMinDw.Value = P.minDwell;          % UI도 동기화
        end

        [pl,tr,diag] = detectByChangePoint(st.data.F, P);
        st.segPl = pl; st.segTr = tr; st.diag = diag;

        st.lblStats.Text = sprintf('thr:%.6g  T=%d, P=%d', ...
            diag.thrH, size(st.segTr,1), size(st.segPl,1));
        applyLag();
    end

    function [pl, tr, diag] = detectByChangePoint(F, P)
        % 적응 임계 + 히스테리시스 + prominence + 면적 기준
        F = F(:); N = numel(F);
        W = max(3, round(P.smoothWin));
        L = 2*floor(W/2)+1;

        % 스무딩 및 기울기 (폴백 포함)
        Ff  = fillmissing(F,'linear','EndValues','nearest');
        if exist('sgolayfilt','file')
            Fs  = sgolayfilt(Ff, 3, L);
        else
            Fs  = movmedian(Ff, L);
        end
        dF0 = abs(gradient(Fs));
        % |dF|도 살짝 평활해서 봉우리 안정화
        dF  = movmean(dF0, max(3, round(L/5)));

        % 전역 퍼센타일 + 로컬 잡음(MAD) 기반 적응 임계
        sigma = 1.4826 * mad(dF, 1);                  % robust sigma
        thr0  = prctile(dF, max(10, min(99, P.pctFloor)));
        thrH  = max(P.thrScale * thr0, 2.5*sigma);    % 채택 상한 임계
        thrL  = 0.55 * thrH;                           % 연결 하한 임계

        % 최소 간격/최대 개수
        minDist = max(P.minDwell, ceil(0.6*W));
        maxChg  = min(50, max(3, floor(N / max(1, P.minDwell))));

        % ── 씨앗 ① changepts (폴백 고려)
        cidx = [];
        if exist('findchangepts','file')
            try
                cidx = findchangepts(Fs,'Statistic','mean', ...
                    'MinDistance',minDist,'MaxNumChanges',maxChg);
            catch, cidx = [];
            end
        end

        % ── 씨앗 ② |dF| 봉우리 (prominence 사용)
        prom = max(1.5*sigma, 0.2*thrH);
        sep  = max(1, round(minDist/2));
        pk   = islocalmax(dF,'MinSeparation',sep,'MinProminence',prom);
        pidx = find(pk);

        % 씨앗 취합 (없으면 임계 초과 구간 중심 사용)
        seeds = unique([cidx(:); pidx(:)]);
        if isempty(seeds)
            msk = dF >= thrH;
            d   = diff([false; msk; false]);
            s   = find(d== 1); e = find(d==-1)-1;
            seeds = round((s+e)/2);
        end

        % 히스테리시스: thrL로 좌우 확장 + pad, 채택 조건(피크 or 면적)
        mskLo = dF >= thrL;
        cand  = zeros(0,2);
        for k = 1:numel(seeds)
            s = seeds(k);
            % 좌/우로 내려가는 지점 찾기
            l = s; while l>1   && mskLo(l-1), l=l-1; end
            r = s; while r<N   && mskLo(r+1), r=r+1; end
            if r<l, continue; end

            % pad 확장
            a = max(1, l - P.pad);
            b = min(N, r + P.pad);

            % 채택 기준: 피크 또는 면적(베이스라인 위 누적)
            pmax  = max(dF(l:r));
            area  = sum(max(0, dF(l:r) - thrL));
            areaT = max(thrH * max(1, P.pad*0.8), 2.0*sigma * (r-l+1));

            if (pmax >= thrH) || (area >= areaT)
                cand(end+1,:) = [a b]; %#ok<AGROW>
            end
        end

        % 후보 병합
        if isempty(cand)
            tr = uint32(zeros(0,2));
        else
            gap = max(1, round(min(W, P.pad)));     % 너무 가까우면 합치기
            tr  = uint32(mergeClose(double(cand), gap));
        end

        % 여집합 → plateau, trim / minDwell 적용
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

        % 진단(오버레이용)
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

    function onRoiSlide(~,~)
        if st.isLoading, return; end
        flushUseEdits();

        % 1) 좌측 슬라이더 값에 맞춰 우측 ROI 드롭다운을 먼저 동기화
        if isfield(st,'ddRoiM') && isvalid(st.ddRoiM)
            rid   = max(1, min(st.data.rois, round(st.sldROI.Value)));
            items = string(st.ddRoiM.Items);
            val   = string(rid);
            if any(items == val)
                st.ddRoiM.Value = char(val);
            else
                % 아이템이 아직 준비 안됐으면 갱신 후 값 설정
                updateMeansTableUI();                 % (내부에서 refreshMeansPlot 호출)
                items = string(st.ddRoiM.Items);
                if any(items == val)
                    st.ddRoiM.Value = char(val);
                end
            end
        end

        % 2) 마지막에 전체 플롯 갱신(좌측/상대/우측 프리뷰 포함)
        refreshPlots();
        rid = max(1, min(st.data.rois, round(st.sldROI.Value)));
        purgeOtherRoiKeysForCurrentSession(rid);
        refreshMeansPlot();
        % ROI 전환 시, 이 파일에서 현재 ROI만 남기고 모두 off
        try
            T = st.tblMeans.Data;
            if ~isempty(T)
                T = enforceSingleRoiForCurrentSession(T);
                st.tblMeans.Data = T; st.meansT = T; syncUseMap(); % 맵 재동기화
            end
        catch
        end
    end


    function stepROI(d)
        if st.data.rois<1, return; end
        v = round(st.sldROI.Value)+d;
        v = max(1,min(v,st.data.rois));
        st.sldROI.Value = v;
        onRoiSlide();              % <-- 슬라이더 콜백을 직접 호출해 동기화
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
        if isempty(T)
            st.segPl = uint32(zeros(0,2));
            st.segTr = uint32(zeros(0,2));
        else
            st.segPl = guardSeg(uint32(table2array(T)), st.data.frames);
            st.segTr = uint32(complementSeg(double(st.segPl), st.data.frames));
        end
        refreshPlots();
    end

    function exportSegmentBoth()
        % 사전 체크
        if st.data.rois<1 || isempty(st.segPl)
            uialert(st.fig,'ROI 또는 plateau 세그먼트가 없습니다. 먼저 세션 로드 및 Auto Detect를 실행하세요.','Export');
            return;
        end

        % 기본 시작 위치: perFileDir()가 있으면 그 폴더, 아니면 st.root
        defDir = st.root;
        try defDir = perFileDir(); catch, end

        destDir = uigetdir(defDir, 'Select export folder for BOTH CSVs');
        if isequal(destDir,0), return; end

        base = currentBaseId();
        % 두 파일을 같은 폴더에 저장
        exportSegmentMeansAll(destDir, true);
        exportSegmentFramesAll(destDir, true);

        msg = sprintf('Saved:\n%s\n%s', ...
            fullfile(destDir, sprintf('%s_segmeans_all.csv',  base)), ...
            fullfile(destDir, sprintf('%s_segframes_all.csv', base)));
        uialert(st.fig, msg, 'Export done', 'Icon','success');
    end

    function exportSegmentMeansAll(destDir, quiet)
        if nargin < 1 || isempty(destDir), destDir = ''; end
        if nargin < 2 || isempty(quiet),   quiet   = false; end

        if st.data.rois<1 || isempty(st.segPl)
            uialert(st.fig,'ROI 또는 plateau 세그먼트가 없습니다.','Export'); return;
        end

        base = currentBaseId();
        if ~isempty(destDir) && isfolder(destDir)
            fd = fullfile(destDir, sprintf('%s_segmeans_all.csv', base));
        else
            defOut = fullfile(perFileDir(), sprintf('%s_segmeans_all.csv', base));
            [f,p] = uiputfile({'*.csv','CSV'}, 'Save Segment Means (S/B/R)', defOut);
            if isequal(f,0), return; end
            fd = fullfile(p,f);
        end
        N = st.data.frames;
        hasBg = ~isempty(st.data.Bgnd) && all(size(st.data.Bgnd)==[N st.data.rois]);
        hasRw = ~isempty(st.data.Raw)  && all(size(st.data.Raw )==[N st.data.rois]);

        rows = cell(0,13); % id roi seg start end len f_mean mean_sgnl sd_sgnl mean_bgnd sd_bgnd mean_raw sd_raw

        for r = 1:st.data.rois
            seg0 = double(st.segPl); if isempty(seg0), continue; end
            segEff = seg0;
            if numel(st.excl)>=r && ~isempty(st.excl{r})
                segEff = minusSeg(seg0, double(st.excl{r}), N); % exclude 적용
            end

            S  = st.data.Sgnl(:,r);
            B  = tern(hasBg, st.data.Bgnd(:,r), []);
            Rw = tern(hasRw, st.data.Raw (:,r), []);

            for i=1:size(seg0,1)
                a0=seg0(i,1); b0=seg0(i,2);
                bins = subBins(segEff,a0,b0); % exclude 적용된 실제 집계 프레임 구간들
                [L, muS, sdS] = aggBins(S,bins);
                if hasBg, [~, muB, sdB] = aggBins(B,bins); else, muB=NaN; sdB=NaN; end
                if hasRw, [~, muR, sdR] = aggBins(Rw,bins); else, muR=NaN; sdR=NaN; end
                fmean = NaN;
                if st.data.hasF && ~isempty(bins)
                    idx = bins2idx(bins);
                    fmean = mean(st.data.F(idx),'omitnan');
                end
                rows(end+1,:) = { string(st.data.id), uint16(r), uint16(i), ...
                    uint32(a0), uint32(b0), uint32(L), double(fmean), ...
                    muS, sdS, muB, sdB, muR, sdR }; %#ok<AGROW>
            end
        end

        T = cell2table(rows,'VariableNames', ...
            {'id','roi','seg','start','end','len','f_mean', ...
            'mean_sgnl','sd_sgnl','mean_bgnd','sd_bgnd','mean_raw','sd_raw'});
        writetable(T,fd);
        if ~quiet
            uialert(st.fig, sprintf('Saved\n%s', fd), 'Saved');
        end

        % --- helpers ---
        function bins = subBins(segEff,a0,b0)
            if isempty(segEff), bins=zeros(0,2); return; end
            A=segEff(:,1); E=segEff(:,2);
            hit = ~(E<a0 | A>b0);
            bins = [max(A(hit),a0), min(E(hit),b0)];
            bins = bins(bins(:,2)>=bins(:,1),:);
        end
        function [L,mu,sd] = aggBins(v,bins)
            if isempty(bins), L=0; mu=NaN; sd=NaN; return; end
            idx = bins2idx(bins);
            x = v(idx);
            L  = numel(x);
            mu = mean(x,'omitnan');
            sd = std(x,0,'omitnan');
        end
        function idx = bins2idx(bins)
            idx = []; for kk=1:size(bins,1), idx = [idx, bins(kk,1):bins(kk,2)]; end
        end
        function y = tern(c,a,b), if c, y=a; else, y=b; end, end
    end

    function setCustomRefFromTable()
        if isempty(st.selRowsLast)
            uialert(st.fig,'Segments 표에서 기준으로 쓸 행을 하나 이상 선택하세요.','No selection');
            return;
        end
        st.customRefRows = st.selRowsLast(:)';     % 기억
        st.ddNorm.Value  = 'custom';               % 모드를 custom으로
        updateRelPlot();
    end

    function loadForceManual()
        if st.data.frames<1, uialert(st.fig,'먼저 세션을 로드하세요','Load Force'); return; end
        [f,p] = uigetfile({'*.dat;*.txt;*.csv','Force file'},'Select force file', st.root);
        if isequal(f,0), return; end
        F = readForce(fullfile(p,f), st.data.frames);
        if isempty(F), uialert(st.fig,'파일을 읽지 못했습니다','Force'); return; end
        st.data.hasF = true; st.data.F = F(:)'; refreshPlots();
    end

    function exportSegmentFramesAll(destDir, quiet)
        if nargin < 1 || isempty(destDir), destDir = ''; end
        if nargin < 2 || isempty(quiet),   quiet   = false; end

        if st.data.rois<1 || isempty(st.segPl)
            uialert(st.fig,'ROI 또는 plateau 세그먼트가 없습니다.','Export'); return;
        end

        base = currentBaseId();
        if ~isempty(destDir) && isfolder(destDir)
            fd = fullfile(destDir, sprintf('%s_segframes_all.csv', base));
        else
            defOut = fullfile(perFileDir(), sprintf('%s_segframes_all.csv', base));
            [f,p] = uiputfile({'*.csv','CSV'}, 'Save Segment Frames (S/B/R)', defOut);
            if isequal(f,0), return; end
            fd = fullfile(p,f);
        end

        N = st.data.frames;
        hasBg = ~isempty(st.data.Bgnd) && all(size(st.data.Bgnd)==[N st.data.rois]);
        hasRw = ~isempty(st.data.Raw)  && all(size(st.data.Raw )==[N st.data.rois]);

        rows = cell(0,8); % id roi seg frame force sgnl bgnd raw

        for r = 1:st.data.rois
            seg0 = double(st.segPl); if isempty(seg0), continue; end
            segEff = seg0;
            if numel(st.excl)>=r && ~isempty(st.excl{r})
                segEff = minusSeg(seg0, double(st.excl{r}), N); % exclude 적용
            end

            S  = st.data.Sgnl(:,r);
            B  = []; if hasBg, B  = st.data.Bgnd(:,r); end
            Rw = []; if hasRw, Rw = st.data.Raw (:,r); end
            F  = nan(N,1); if st.data.hasF, F = st.data.F(:); end

            for i=1:size(seg0,1)
                a0=seg0(i,1); b0=seg0(i,2);
                bins = subBins(segEff,a0,b0);
                if isempty(bins), continue; end

                for kk=1:size(bins,1)
                    a=bins(kk,1); e=bins(kk,2);
                    n = (a:e)';

                    % --- 각 열을 cell로 준비 ---
                    idc  = repmat({string(st.data.id)}, numel(n), 1);     % cell of string
                    roic = num2cell(repmat(uint16(r),  numel(n), 1));
                    segc = num2cell(repmat(uint16(i),  numel(n), 1));
                    frmc = num2cell(uint32(n));
                    frcc = num2cell(F(n));
                    sgnc = num2cell(S(n));
                    if hasBg, bgc = num2cell(B(n));  else, bgc = num2cell(nan(numel(n),1)); end
                    if hasRw, rwc = num2cell(Rw(n)); else, rwc = num2cell(nan(numel(n),1)); end

                    blk = [idc roic segc frmc frcc sgnc bgc rwc];         % cell 배열
                    rows = [rows; blk];                                    % vertcat
                end
            end
        end

        % ---- cell → table (타입 명시) ----
        if isempty(rows)
            uialert(st.fig,'내보낼 데이터가 없습니다.','Export'); return;
        end

        id  = vertcat(rows{:,1});                          % string array (Nx1)
        roi = uint16(cell2mat(rows(:,2)));
        seg = uint16(cell2mat(rows(:,3)));
        frm = uint32(cell2mat(rows(:,4)));
        frc = double(cell2mat(rows(:,5)));
        sgn = double(cell2mat(rows(:,6)));
        bg  = double(cell2mat(rows(:,7)));
        raw = double(cell2mat(rows(:,8)));

        T = table(id, roi, seg, frm, frc, sgn, bg, raw, ...
            'VariableNames', {'id','roi','seg','frame','force','sgnl','bgnd','raw'});

        writetable(T,fd);
        if ~quiet
            uialert(st.fig, sprintf('Saved (%d rows)\n%s', height(T), fd), 'Saved');
        end

        % --- helpers ---
        function bins = subBins(segEff,a0,b0)
            if isempty(segEff), bins=zeros(0,2); return; end
            A=segEff(:,1); E=segEff(:,2);
            hit = ~(E<a0 | A>b0);
            bins = [max(A(hit),a0), min(E(hit),b0)];
            bins = bins(bins(:,2)>=bins(:,1),:);
        end
    end

    function onMeansRoiChanged(~,~)
        if st.isLoading, return; end
        flushUseEdits();

        if st.data.rois>=1 && ~strcmp(st.ddRoiM.Value,'-')
            rid = str2double(string(st.ddRoiM.Value));
            if isfinite(rid)
                st.sldROI.Value = max(1,min(st.data.rois, round(rid)));
                refreshPlots();
                purgeOtherRoiKeysForCurrentSession(round(rid));
            end
        end
        try
            T = st.tblMeans.Data;
            if ~isempty(T)
                T = enforceSingleRoiForCurrentSession(T);
                st.tblMeans.Data = T; st.meansT = T; syncUseMap(); % 맵 재동기화
            end
        catch
        end
    end
    function highlightSeg(k)
        % k: 선택 plateau 인덱스(1-based)
        % 기존 하이라이트 제거
        try if all(isvalid(st.hl.F)), delete(st.hl.F); end, catch, end
        try if all(isvalid(st.hl.S)), delete(st.hl.S); end, catch, end

        if isempty(st.segPl) || k<1 || k>size(st.segPl,1), return; end
        a = double(st.segPl(k,1)); b = double(st.segPl(k,2));

        % Force/Signal 축에 경계선 추가
        st.hl.F(1) = xline(st.axF, a, '-', 'Color', [0.25 0.25 0.85], 'LineWidth', 1.4);
        st.hl.F(2) = xline(st.axF, b, '-', 'Color', [0.25 0.25 0.85], 'LineWidth', 1.4);
        st.hl.S(1) = xline(st.axS, a, '-', 'Color', [0.25 0.25 0.85], 'LineWidth', 1.4);
        st.hl.S(2) = xline(st.axS, b, '-', 'Color', [0.25 0.25 0.85], 'LineWidth', 1.4);
    end

    function onMeansPointClick(segIdx)
        % 우측 포인트 클릭 시 → 표 선택 + 좌측 하이라이트
        try
            st.tbl.Selection = [segIdx, 1];   % (Row, Col)
        catch
            % 구버전 대응: 내부 상태만 갱신
            st.selRow = segIdx;
            st.selRowsLast = segIdx;
        end
        highlightSeg(segIdx);
    end
% ====== 통합: MeansCollectorLite 핵심 동작 (현 세션만) =================
    function rebuildMeansTable()
        if st.data.rois<1 || isempty(st.segPl)
            st.meansT = table(); updateMeansTableUI(); return;
        end

        rows = cell(0,7); % use,id,roi,seg,len,mean,std
        for r=1:st.data.rois
            seg = double(st.segPl); if isempty(seg), continue; end
            S = st.data.Sgnl(:,r);
            for i=1:size(seg,1)
                a=seg(i,1); b=seg(i,2); L = b-a+1;
                v = S(a:b); mu = mean(v,'omitnan'); sd = std(v,0,'omitnan');
                rows(end+1,:) = {false, string(st.data.id), uint16(r), uint16(i), L, mu, sd}; %#ok<AGROW>
            end
        end

        if isempty(rows)
            st.meansT = table();
        else
            T = cell2table(rows,'VariableNames',{'use','id','roi','seg','len','mean','std'});

            % ▶▶▶ (1) 이전 선택 복원
            U = false(height(T),1);
            for ii = 1:height(T)
                k = useKey(T.id(ii), T.roi(ii), T.seg(ii));
                if isKey(st.useMap, k), U(ii) = st.useMap(k); end
            end
            T.use = U;

            % ▶▶▶ (2) 값 캐시 채우기 (누적 Wide에서 사용)
            for ii = 1:height(T)
                k = useKey(T.id(ii), T.roi(ii), T.seg(ii));
                st.meanCache(k) = { string(T.id(ii)), uint16(T.roi(ii)), uint16(T.seg(ii)), ...
                    uint32(T.len(ii)), double(T.mean(ii)), double(T.std(ii)) };
            end

            st.meansT = T;
        end

        % ▶▶▶ (3) 세그먼트 최신본도 세션키로 캐시(선택 사항이지만 유용)
        try
            st.segCache(currentSessionKey()) = st.segPl;
        catch
        end

        updateMeansTableUI();
    end



    function updateMeansTableUI()
        T = st.meansT;
        st.tblMeans.Data = T;
        if isempty(T)
            st.ddRoiM.Items = {'-'}; st.ddRoiM.Value='-';
        else
            rois = unique(T.roi,'stable'); items = cellstr(string(rois));
            if isempty(items), items={'-'}; end
            st.ddRoiM.Items = items;
            % 현재 좌측 슬라이더 ROI에 맞춰 세팅
            rid = max(1, min(st.data.rois, round(st.sldROI.Value)));
            want = char(string(rid));
            if any(strcmp(items, want))
                st.ddRoiM.Value = want;
            else
                st.ddRoiM.Value = items{1};
            end
        end
        refreshMeansPlot();
    end

    function refreshMeansPlot()
        cla(st.axM);
        T = st.tblMeans.Data; if isempty(T) || height(T)==0, return; end
        if isempty(st.ddRoiM.Value) || strcmp(st.ddRoiM.Value,'-'), return; end
        roiSel = st.ddRoiM.Value;

        % 가시 ROI: 현 표 전체의 ROI (선택 없으면 전체)
        visList = unique(string(T.roi),'stable');
        hold(st.axM,'on');
        % 회색: 가시 ROI들
        for k = 1:numel(visList)
            r = visList{k};
            m = roiMask(T.roi, r);
            if ~any(m), continue; end
            R = sortrows(T(m, {'seg','mean','std'}), 'seg');
            errorbar(st.axM, double(R.seg), double(R.mean), double(R.std), ...
                'o-','Color',[0.80 0.80 0.80],'LineWidth',0.9,'MarkerSize',4,'CapSize',4);
        end

        mSel = roiMask(T.roi, roiSel);
        Rsel = sortrows(T(mSel, {'seg','mean','std','use'}), 'seg');
        if ~isempty(Rsel)
            % 두꺼운 에러바(강조)
            hb = errorbar(st.axM, double(Rsel.seg), double(Rsel.mean), double(Rsel.std), ...
                'o-','LineWidth',1.8,'MarkerSize',5,'CapSize',5);

            % 클릭 가능한 포인트를 개별로 얹음
            xs = double(Rsel.seg); ys = double(Rsel.mean);
            for ii = 1:numel(xs)
                hp = plot(st.axM, xs(ii), ys(ii), 'o', ...
                    'MarkerSize', 8, 'LineWidth', 1.2, ...
                    'Color', hb.Color, ...
                    'PickableParts','all','HitTest','on');
                hp.ButtonDownFcn = @(~,~) onMeansPointClick(xs(ii));
            end

            if any(Rsel.use)
                plot(st.axM, double(Rsel.seg(Rsel.use)), double(Rsel.mean(Rsel.use)), ...
                    'o','MarkerSize',6,'LineWidth',1.8,'Color',[0.1 0.1 0.1]);
            end
            title(st.axM, sprintf('Means per SEG (ROI %s)  —  used: %d/%d', ...
                string(roiSel), nnz(Rsel.use), height(Rsel)));
        else
            title(st.axM, 'Means per SEG (모든 ROI 표시, 선택 ROI 강조)');
        end


        grid(st.axM,'on'); xlabel(st.axM,'SEG'); ylabel(st.axM,'mean');
        hold(st.axM,'off');
    end

    function stepRoiMean(d)
        items = st.ddRoiM.Items; if isempty(items) || strcmp(items{1},'-'), return; end
        i = find(strcmp(items, st.ddRoiM.Value), 1);
        i = max(1, min(numel(items), i + d));
        st.ddRoiM.Value = items{i};
        onMeansRoiChanged();

    end

    function bulkUse(onoff)
        T = st.tblMeans.Data; if isempty(T), return; end
        T = ensureUseCol(T, onoff);
        T = enforceSingleRoiForCurrentSession(T);
        st.tblMeans.Data = T; st.meansT = T; refreshMeansPlot();
        onIdx = find(T.use==true);
        for ii = onIdx.'
            st.useMap(useKey(T.id(ii),T.roi(ii),T.seg(ii))) = true;
        end
    end

    function setUseForROI(turnOn, onlyThis)
        T = st.tblMeans.Data; if isempty(T), return; end
        T = ensureUseCol(T);
        if onlyThis, T.use(:) = false; end
        mask = roiMask(T.roi, st.ddRoiM.Value);
        T.use(mask) = logical(turnOn);

        % ★ 단일 ROI 강제 & 반영
        T = enforceSingleRoiForCurrentSession(T);
        st.tblMeans.Data = T; st.meansT = T; refreshMeansPlot();
        onIdx = find(T.use==true);
        for ii = onIdx.'
            st.useMap(useKey(T.id(ii),T.roi(ii),T.seg(ii))) = true;
        end
    end

    function saveSelected()
        flushUseEdits();
        T = getMeansLive(); if isempty(T), return; end
        T = ensureUseCol(T);
        rows = T( T.use==true & string(T.id)==string(st.data.id), : );   % ← roi 필터 제거
        if isempty(rows), uialert(st.fig,'No rows selected.','Save'); return; end
        openPreviewExport(rows, fullfile(perFileDir(),'merged_means_selected.csv'), ...
            'Selected rows', perFileDir(), st.fig);
    end


    function exportSummary()
        flushUseEdits();
        T = st.tblMeans.Data; if isempty(T), return; end
        T = ensureUseCol(T);
        rows = T( T.use==true & string(T.id)==string(st.data.id), : );   % ← roi 필터 제거
        if isempty(rows), uialert(st.fig,'No rows selected.','Export summary'); return; end

        if exist('groupsummary','file')
            G = groupsummary(rows, {'id','roi','seg'}, {'mean','std','numel'}, 'mean');
            S = table(G.id, G.roi, G.seg, G.mean_mean, G.std_mean, G.numel_mean, ...
                'VariableNames', {'id','roi','seg','mean','sd','N'});
        else
            % fallback 수동 집계
            key = string(rows.id) + "|" + string(rows.roi) + "|" + string(rows.seg);
            uk  = unique(key,'stable');
            S = table('Size',[0 6], ...
                'VariableTypes',{'string','uint16','uint16','double','double','double'}, ...
                'VariableNames',{'id','roi','seg','mean','sd','N'});
            for k = 1:numel(uk)
                m = key==uk(k);
                idk  = string(rows.id(find(m,1,'first')));
                roik = uint16(rows.roi(find(m,1,'first')));
                segk = uint16(rows.seg(find(m,1,'first')));
                mu   = mean(double(rows.mean(m)),'omitnan');
                sd   = mean(double(rows.std(m)),'omitnan');
                N    = sum(m);
                S = [S; {idk,roik,segk,mu,sd,double(N)}]; %#ok<AGROW>
            end
        end
        S.sem = S.sd ./ max(1, sqrt(S.N));
        openPreviewExport(S, fullfile(perFileDir(),'summary_by_segment.csv'), ...
            'Summary by SEG', perFileDir(), st.fig);
    end
    function exportMergedWideAccum()
        flushUseEdits();

        % 1) 선택(on) 키 수집
        if st.useMap.Count == 0
            uialert(st.fig,'No rows selected.','Export wide'); return;
        end
        K = keys(st.useMap); V = values(st.useMap);
        selKeys = K(cellfun(@(x)logical(x), V));
        if isempty(selKeys)
            uialert(st.fig,'No rows selected.','Export wide'); return;
        end

        % 2) 캐시에서 값 모으기 (방문했던 세션만 대상)
        rows = cell(0,6); % id, roi, seg, len, mean, std
        for i=1:numel(selKeys)
            k = selKeys{i};
            if ~isKey(st.meanCache, k)
                % (안전) 해당 키 값이 없으면 스킵
                continue;
            end
            rows(end+1,:) = st.meanCache(k); %#ok<AGROW>
        end
        if isempty(rows)
            uialert(st.fig,'No data cached for selected rows.','Export wide'); return;
        end

        % 3) 테이블로 변환
        R = cell2table(rows, 'VariableNames', {'id','roi','seg','len','mean','std'});

        % 4) 기존 Wide 포맷으로 피벗
        R = sortrows(R, {'id','roi','seg'});
        maxSeg = max(double(R.seg)); if ~isfinite(maxSeg) || maxSeg<1, maxSeg = 1; end
        mnNames = compose('s%d_mean', 1:maxSeg);
        sdNames = compose('s%d_sd',   1:maxSeg);
        varNames = ['fn','id','roi', mnNames, sdNames];
        out = table('Size',[0 numel(varNames)], ...
            'VariableTypes', repmat({'string'},1,numel(varNames)), ...
            'VariableNames', varNames);

        keysIR = unique(string(R.id)+"|"+string(R.roi), 'stable');
        for k = 1:numel(keysIR)
            pr = split(keysIR(k),"|");
            idk = pr(1); roik = pr(2);
            m = (string(R.id)==idk) & (string(R.roi)==roik);
            G = R(m,:);
            segIdx = double(G.seg);
            [grpSeg,~,grpIdx] = unique(segIdx);
            mm = accumarray(grpIdx, double(G.mean), [], @mean);
            ss = accumarray(grpIdx, double(G.std),  [], @mean);

            rowMean = strings(1,maxSeg); rowSd = strings(1,maxSeg);
            for t=1:numel(grpSeg)
                s = grpSeg(t);
                if s>=1 && s<=maxSeg
                    rowMean(s) = compose('%.6g', mm(t));
                    rowSd(s)   = compose('%.6g', ss(t));
                end
            end
            row = table( string(sprintf('%s_%s', idk, roik)), idk, roik, ...
                'VariableNames', {'fn','id','roi'});
            for s=1:maxSeg, row.(sprintf('s%d_mean',s)) = rowMean(s); end
            for s=1:maxSeg, row.(sprintf('s%d_sd',s))   = rowSd(s);   end
            out = [out; row]; %#ok<AGROW>
        end

        % 5) 저장/미리보기 (폴더 루트)
        openPreviewExport(out, fullfile(rootDir(),'merged_wide.csv'), ...
            'Merged means (wide; across files in folder)', rootDir(), st.fig);
    end
    function paramChanged(~,~)
        % 숫자 파라미터가 바뀔 때 동작
        % - Auto update가 켜져 있고 Force가 있으면 재검출
        % - 아니면 플롯만 갱신
        if st.cbAuto.Value && st.data.hasF
            autoDetect();
        else
            refreshPlots();
        end
    end

    function tblSelected(~,evt)
        % Segments 표에서 선택된 행을 기억 (custom 정규화 기준으로 사용)
        if isempty(evt.Indices)
            st.selRow = 0;
            st.selRowsLast = [];
        else
            st.selRow       = evt.Indices(1);            % 미세조정용 단일 행
            st.selRowsLast  = unique(evt.Indices(:,1));  % 정규화 기준 후보(복수)
        end
        if strcmp(st.ddNorm.Value,'custom')
            updateRelPlot();  % 즉시 반영
        end
        if ~isempty(st.selRow) && st.selRow>=1, highlightSeg(st.selRow); end
    end
%% ----------------------- HELPERS --------------------------------------
clamp = @(v,lo,hi) max(lo, min(hi, v));
    function setRoiSliderTicks()
        if ~isvalid(st.sldROI), return; end
        if st.data.rois>=2
            % 라벨/눈금 정수만 보이게
            n = st.data.rois;

            % 라벨이 너무 많으면 겹치니, 최대 25개만 균등 간격으로 표시(원하면 삭제 가능)
            maxTicks = 25;
            if n <= maxTicks
                ticks = 1:n;
            else
                ticks = unique(round(linspace(1,n,maxTicks)));
            end

            st.sldROI.MajorTicks       = ticks;
            st.sldROI.MajorTickLabels  = string(ticks);
        else
            st.sldROI.MajorTicks      = [1 2];
            st.sldROI.MajorTickLabels = ["1","2"];
        end
    end

    function purgeOtherRoiKeysForCurrentSession(curRoi)
        try
            sid = lower(strrep(currentSessionKey(),'\','/'));
            K = keys(st.useMap);
            for i = 1:numel(K)
                k = K{i};
                if startsWith(k, [sid '|'])
                    tok = regexp(k, '\|(\d+)\|\d+$', 'tokens', 'once'); % key: sid|roi|seg
                    if ~isempty(tok)
                        roi_k = uint16(str2double(tok{1}));
                        if roi_k ~= uint16(curRoi)
                            remove(st.useMap, k);        % 같은 세션의 다른 ROI 흔적 제거
                        end
                    end
                end
            end
        catch
        end
    end

    function base = currentBaseId()
        % 우선순위: (1) 세션 라벨 → (2) 로드된 데이터 id → (3) 폴더명
        if ~isempty(st.sessions) && st.idx>=1 && st.idx<=height(st.sessions) ...
                && isfield(st.sessions,'label') && ~isempty(st.sessions.label{st.idx})
            base = st.sessions.label{st.idx};     % 예: "sample_1.2"
            return;
        end
        if isfield(st.data,'id') && ~isempty(st.data.id)
            base = char(string(st.data.id));
            return;
        end
        if isfield(st,'loadedPath') && ~isempty(st.loadedPath) && isfolder(st.loadedPath)
            [~, base] = fileparts(st.loadedPath);
        else
            [~, base] = fileparts(st.root);
        end
        base = regexprep(base,'_Output$','');     % 후처리(있으면 제거)
    end

    function T = enforceSingleRoiForCurrentSession(T)
        % 현재 파일(세션)에서는 ddRoiM.Value에 해당하는 ROI만 use=true 허용
        if isempty(T) || strcmp(st.ddRoiM.Value,'-') || st.data.rois<1
            return;
        end
        curRoi = uint16(clamp(round(str2double(string(st.ddRoiM.Value))),1,st.data.rois));
        T = ensureUseCol(T);
        otherOn = (uint16(T.roi) ~= curRoi) & T.use;
        if any(otherOn)
            T.use(otherOn) = false;          % 표에서 다른 ROI가 켜져 있으면 자동으로 끔
        end
    end

    function [ok, D, idStr, err] = loadFluorMat(matPath)
        ok=false; D=struct(); err=''; idStr = makeId(matPath);
        try
            S = load(fullfile(matPath,'Fluor.mat'));

            % Sgnl 우선, 없으면 Raw-Bgnd로 폴백
            if isfield(S,'Sgnl'), Sgnl = S.Sgnl;
            elseif isfield(S,'Raw') && isfield(S,'Bgnd'), Sgnl = S.Raw - S.Bgnd;
            else, error('Fluor.mat에 Sgnl이 없고 Raw/Bgnd 조합도 없습니다.');
            end

            Bgnd = []; Raw = [];
            if isfield(S,'Bgnd'), Bgnd = S.Bgnd; end
            if isfield(S,'Raw'),  Raw  = S.Raw;  end

            % 행렬 방향 통일 (frames×rois)
            if size(Sgnl,1) < size(Sgnl,2), Sgnl = Sgnl'; end
            if ~isempty(Bgnd) && size(Bgnd,1) < size(Bgnd,2), Bgnd = Bgnd'; end
            if ~isempty(Raw)  && size(Raw,1)  < size(Raw,2),  Raw  = Raw';  end

            frames = size(Sgnl,1); rois = size(Sgnl,2);
            if ~isempty(Bgnd) && ~isequal(size(Bgnd),[frames rois]), Bgnd = []; end
            if ~isempty(Raw)  && ~isequal(size(Raw ),[frames rois]), Raw  = []; end
            if isempty(Raw) && ~isempty(Bgnd), Raw = Sgnl + Bgnd; end

            D.Sgnl=Sgnl; D.Bgnd=Bgnd; D.Raw=Raw; D.frames=frames; D.rois=rois; ok=true;
        catch ME, err=ME.message;
        end
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
    function flushUseEdits()
        % uitable 편집 커밋 + 최신 useMap 반영
        try
            drawnow;                           % pending UI flush
            st.tblMeans.Data = st.tblMeans.Data; % no-op 할당으로 commit 유도
            drawnow;
        catch
        end
        % 테이블의 use 컬럼을 논리형으로 보정
        try
            T = st.tblMeans.Data;
            if ~isempty(T)
                st.tblMeans.Data = ensureUseCol(T);
            end
        catch
        end
        % map 최신화
        try syncUseMap(); catch, end
    end

    function T = getMeansLive()
        % 테이블이 비어있으면 메모리 테이블 사용
        if ~isempty(st.tblMeans.Data)
            T = ensureUseCol(st.tblMeans.Data);
        else
            T = ensureUseCol(st.meansT);
        end
        % 혹시 모를 타입/지연 반영 방지: useMap을 최종 오버레이
        if ~isempty(T)
            for ii = 1:height(T)
                k = useKey(T.id(ii), T.roi(ii), T.seg(ii));
                if isKey(st.useMap, k)
                    T.use(ii) = st.useMap(k);
                end
            end
        end
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
        F=[];
        try T = readmatrix(fp); catch, T=[]; end
        if isempty(T) || ~isnumeric(T)
            try
                opts = detectImportOptions(fp,'Delimiter',{' ','\t',','});
                vt = opts.VariableTypes; keep = ismember(vt,{'double','single'});
                if any(keep), opts.SelectedVariableNames = opts.VariableNames(keep); end
                T = table2array(readtable(fp,opts));
            catch, T=[];
            end
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
        catch, F=[];
        end
    end


    function onRoiChanging(src,evt)
        src.Value = round(evt.Value);  % 드래그 중에도 정수만
    end


    function k = useKey(~, roi, seg)
        sid = lower(strrep(currentSessionKey(), '\','/'));  % 경로 정규화
        k = sprintf('%s|%u|%u', sid, uint16(roi), uint16(seg));
    end
    function sid = currentSessionKey()
        % 가능한 한 "canonical absolute path"를 써서 경로 표현을 고정
        if isfield(st,'loadedPath') && ~isempty(st.loadedPath) && isfolder(st.loadedPath)
            try
                jfile = java.io.File(st.loadedPath);
                sid = char(jfile.getCanonicalPath());
            catch
                sid = char(string(st.loadedPath));  % 자바 실패 시 fallback
            end
        elseif ~isempty(st.sessions) && st.idx>=1 && st.idx<=height(st.sessions)
            try
                jfile = java.io.File(st.sessions.path{st.idx});
                sid = char(jfile.getCanonicalPath());
            catch
                sid = char(string(st.sessions.path{st.idx}));
            end
        else
            sid = char(string(st.root));  % 마지막 안전망
        end
    end

    function dirp = perFileDir()
        % 현재 세션 폴더/라벨을 기반으로, 파일별 하위폴더를 반환
        if isfield(st,'loadedPath') && ~isempty(st.loadedPath) && isfolder(st.loadedPath)
            sesDir = st.loadedPath;
        elseif ~isempty(st.sessions) && st.idx>=1 && st.idx<=height(st.sessions)
            sesDir = st.sessions.path{st.idx};
        else
            sesDir = st.root;
        end
        base = currentBaseId();                   % 아래 2) 참조
        dirp = fullfile(sesDir, base);            % ← 개별 파일 하위폴더
        if ~isfolder(dirp), mkdir(dirp); end
    end

    function dirp = rootDir()
        dirp = st.root;
        if ~isfolder(dirp), mkdir(dirp); end
    end
% ---- segments utilities -------------------------------------------------

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

    function onAutoToggle(~,evt)
        if evt.Value && st.data.hasF
            autoDetect();      % 켜질 때 즉시 한 번 재검출
        end
    end

    function overlayDF(ax, dF, thr)
        % |dF|를 해당 축 범위로 정규화해서 점선으로 그려주고,
        % thr가 주어지면 임계선도 같이 표시한다.
        if isempty(dF) || ~isvalid(ax), return; end
        yl = ylim(ax);
        lo = min(dF); hi = max(dF);
        if ~isfinite(lo) || ~isfinite(hi) || hi==lo, return; end

        y = (dF(:) - lo) ./ (hi - lo + eps);          % 0..1
        y = yl(1) + y * (yl(2) - yl(1));              % 축 범위로 매핑
        ph = plot(ax, 1:numel(dF), y, '--', 'LineWidth', 0.9, 'Color', [0.2 0.2 0.2]);
        noPick(ph);

        if nargin >= 3 && ~isempty(thr) && isfinite(thr)
            ty = (thr - lo) / (hi - lo + eps);        % 0..1
            ty = yl(1) + ty * (yl(2) - yl(1));        % 축 범위로 매핑
            ln = line(ax, [1 numel(dF)], [ty ty], 'LineStyle', ':', 'Color', [0.35 0.35 0.35]);
            noPick(ln);
        end
    end


    function noPick(h)
        % 그래픽 객체에 대한 datatip/pick 차단 (안전한 try/catch 처리)
        if isempty(h), return; end
        try
            set(h,'HitTest','off','PickableParts','none');
        catch
            for k = 1:numel(h)
                try h(k).HitTest = 'off';
                catch
                end
                try h(k).PickableParts = 'none';
                catch
                end
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
        if ischar(r) || isstring(r)
            rv = uint16(str2double(string(r)));
        else
            rv = uint16(r);
        end
        mask = uint16(roiCol) == rv;
    end

    function openPreviewExport(T, defaultName, titleStr, defDir, parentFig)
        if isempty(T)
            uialert(parentFig,'No data to export.','Preview');
            return;
        end
        if nargin < 4 || isempty(defDir)
            defDir = pwd;                 % 안전 기본값
        end

        % defaultName 이 경로를 포함할 수도, 아닐 수도 있으므로 분리
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
        GL.ColumnWidth = {'1x', 540};
        GL.Padding     = [8 8 8 8];

        uilabel(GL,'Text',sprintf('%s — rows: %d, cols: %d (미리보기는 최대 %d행)', ...
            titleStr, height(T), width(T), PREVIEW_MAX),'FontWeight','bold');

        ut = uitable(GL,'Data',showT,'RowStriping','on');
        ut.Layout.Row = 2; ut.Layout.Column = 1;

        BR = uigridlayout(GL,[1 4]);
        BR.Layout.Row=3;
        BR.ColumnWidth = {'fit','1x','fit','fit'};
        BR.Padding=[0 0 0 0];

        uilabel(BR,'Text',sprintf('보이는 %d행만 미리보기, 저장은 전체 %d행.', ...
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
    function exportTrBoth()
        if st.data.rois < 1 || isempty(st.segTr)
            uialert(st.fig, 'Transition 세그먼트가 없습니다. 먼저 Auto Detect를 실행하세요.', 'Export');
            return
        end

        defDir = st.root;
        try defDir = perFileDir(); catch, end

        destDir = uigetdir(defDir, 'Select export folder for Transition CSVs');
        if isequal(destDir, 0), return, end

        base = currentBaseId();
        exportTrMeansAll(destDir, true);
        exportTrFramesAll(destDir, true);

        msg = sprintf('Saved:\n%s\n%s', ...
            fullfile(destDir, sprintf('%s_trmeans_all.csv',  base)), ...
            fullfile(destDir, sprintf('%s_trframes_all.csv', base)));
        uialert(st.fig, msg, 'Export done', 'Icon', 'success');
    end

    function exportTrMeansAll(destDir, quiet)
        N     = st.data.frames;
        base  = currentBaseId();
        fd    = fullfile(destDir, sprintf('%s_trmeans_all.csv', base));
        hasBg = ~isempty(st.data.Bgnd) && isequal(size(st.data.Bgnd), [N st.data.rois]);
        hasRw = ~isempty(st.data.Raw)  && isequal(size(st.data.Raw),  [N st.data.rois]);

        seg = double(st.segTr);
        nSeg = size(seg, 1);
        nRoi = st.data.rois;
        nRow = nRoi * nSeg;

        id      = repmat(string(st.data.id), nRow, 1);
        roi     = repelem(uint16(1:nRoi)',   nSeg);
        segIdx  = repmat(uint16(1:nSeg)',    nRoi, 1);
        starts  = repmat(uint32(seg(:,1)),   nRoi, 1);
        ends    = repmat(uint32(seg(:,2)),   nRoi, 1);
        lens    = ends - starts + 1;
        fmean   = nan(nRow, 1);
        muS     = nan(nRow, 1);
        sdS     = nan(nRow, 1);
        muB     = nan(nRow, 1);
        sdB     = nan(nRow, 1);
        muR     = nan(nRow, 1);
        sdR     = nan(nRow, 1);

        for r = 1:nRoi
            S  = st.data.Sgnl(:, r);
            B  = [];  if hasBg, B  = st.data.Bgnd(:, r); end
            Rw = [];  if hasRw, Rw = st.data.Raw(:,  r); end

            for i = 1:nSeg
                row      = (r-1)*nSeg + i;
                a        = seg(i,1);
                b        = seg(i,2);
                v        = S(a:b);
                muS(row) = mean(v, 'omitnan');
                sdS(row) = std(v, 0, 'omitnan');

                if hasBg
                    vB       = B(a:b);
                    muB(row) = mean(vB, 'omitnan');
                    sdB(row) = std(vB, 0, 'omitnan');
                end
                if hasRw
                    vR       = Rw(a:b);
                    muR(row) = mean(vR, 'omitnan');
                    sdR(row) = std(vR, 0, 'omitnan');
                end
                if st.data.hasF
                    fmean(row) = mean(st.data.F(a:b), 'omitnan');
                end
            end
        end

        T = table(id, roi, segIdx, starts, ends, lens, fmean, ...
            muS, sdS, muB, sdB, muR, sdR, ...
            'VariableNames', {'id','roi','seg','start','end','len','f_mean', ...
            'mean_sgnl','sd_sgnl','mean_bgnd','sd_bgnd','mean_raw','sd_raw'});
        writetable(T, fd);
        if ~quiet
            uialert(st.fig, sprintf('Saved\n%s', fd), 'Saved');
        end
    end

    function exportTrFramesAll(destDir, quiet)
        N    = st.data.frames;
        base = currentBaseId();
        fd   = fullfile(destDir, sprintf('%s_trframes_all.csv', base));

        seg = double(st.segTr);
        rid = max(1, min(st.data.rois, round(st.sldROI.Value)));

        % baseline 계산 (updateRelPlot과 동일한 방식)
        segPl  = double(st.segPl);
        S      = st.data.Sgnl(:, rid);
        Pn     = size(segPl, 1);
        muPl   = arrayfun(@(i) mean(S(segPl(i,1):segPl(i,2)), 'omitnan'), (1:Pn)');

        mode = st.ddNorm.Value;
        switch mode
            case 'fl'
                refIdx = unique([1, Pn]);
            case 'first'
                refIdx = 1;
            case 'last'
                refIdx = Pn;
            case 'custom'
                refIdx = st.customRefRows;
                refIdx = refIdx(refIdx >= 1 & refIdx <= Pn);
                if isempty(refIdx)
                    refIdx = unique([1, Pn]);
                end
        end
        baseline = mean(muPl(refIdx), 'omitnan');
        if ~isfinite(baseline) || baseline == 0, baseline = 1; end

        % 사전 할당
        lens        = seg(:,2) - seg(:,1) + 1;
        totalFrames = sum(lens);

        segId    = zeros(totalFrames, 1, 'uint16');
        frm      = zeros(totalFrames, 1, 'uint32');
        frc      = nan(totalFrames, 1);
        sgn      = nan(totalFrames, 1);
        sgn_norm = nan(totalFrames, 1);

        F = nan(N, 1);
        if st.data.hasF, F = st.data.F(:); end

        ptr = 1;
        for i = 1:size(seg, 1)
            a        = seg(i, 1);
            b        = seg(i, 2);
            n        = b - a + 1;
            idx      = ptr : ptr + n - 1;
            frames_i = (a:b)';

            segId(idx)    = uint16(i);
            frm(idx)      = uint32(frames_i);
            frc(idx)      = F(frames_i);
            sgn(idx)      = S(frames_i);
            sgn_norm(idx) = S(frames_i) / baseline;

            ptr = ptr + n;
        end

        T = table(segId, frm, frc, sgn, sgn_norm, ...
            'VariableNames', {'seg','frame','force','sgnl','sgnl_norm'});
        writetable(T, fd);

        if ~quiet
            uialert(st.fig, sprintf('Saved (%d rows)\n%s', height(T), fd), 'Saved');
        end
    end
end
