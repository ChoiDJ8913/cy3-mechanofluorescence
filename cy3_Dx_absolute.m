function cy3_Dx_absolute(refAngleDeg)
% |dx| distribution (A) at absolute angles {180, -90, 0, 90}
% reference angle refAngleDeg (default 0): |dx|(angle) = |N-N(angle) - N-N(ref)| (A)
%
% usage:
%   cy3_Dx_absolute            % reference 0 deg
%   cy3_Dx_absolute(180)       % reference 180 deg
%
% file format: .xlsx / .csv
% 7 rows per model: [N_L C1 C2 C3 C4 C5 N_R]
% - use columns x,y,z when present; otherwise take the three most-varying numeric columns as XYZ
% - generate model/atom labels automatically when absent

    if nargin<1, refAngleDeg = 0; end

    % ---------- select and read the file ----------
    [fname,fpath] = uigetfile({'*.xlsx;*.xls;*.csv','Table files (*.xlsx, *.xls, *.csv)'}, ...
                              'Select Cy3 XYZ table');
    if isequal(fname,0), disp('Cancelled'); return; end
    file = fullfile(fpath,fname);

    T = read_table_flex(file);
    T = normalize_headers(T);

    % select the XYZ columns
    xyz = pick_xyz_cols(T);
    for c = xyz, T.(c{1}) = toNum(T.(c{1})); end
    T = rmmissing(T,'DataVariables',xyz);

    % model/atom labels
    modelCol = pick_first(T, ["model","models","id"]);
    if modelCol==""
        nR = height(T); assert(mod(nR,7)==0, 'Rows must be multiple of 7 if no model column.');
        T.model = repelem((1:(nR/7))', 7);
        modelCol = "model";
    end
    atomCol  = pick_first(T, ["atom","atomname","name","label"]);
    if atomCol==""
        order   = ["N_L","C1","C2","C3","C4","C5","N_R"];
        nModels = height(T)/7;
        atoms   = repmat(order, nModels, 1);
        atoms   = reshape(atoms.', [], 1);
        T.atom  = string(atoms);
        atomCol = "atom";
    end
    T.atom = standardize_atom(T.(atomCol));

    models = unique(T.(modelCol),'stable');
    nang   = [180 -90 0 90];
    xt     = {'180°','-90°','0°','90°'};
    Axes   = {'phi1','phi2','phi3'};
    amap   = axis_map();

    % check the index of the reference angle
    [tf,idxRef] = ismember(refAngleDeg, nang);
    assert(tf, 'refAngleDeg (%g deg) must be one of {180,-90,0,90}.', refAngleDeg);

    % result container
    NN_abs = nan(numel(models), numel(Axes), numel(nang)); % Å
    dXabs  = nan(size(NN_abs));                            % |Δx| Å
    rowsAbs = {}; rowsDx = {};

    % ---------- loop over models ----------
    for m = 1:numel(models)
        Mi = T(T.(modelCol)==models(m), :);
        [X,Y,Z,ok] = coords7(Mi, xyz);
        if ~ok, warning('Model %s skipped (incomplete).', string(models(m))); continue; end

        for a = 1:numel(Axes)
            map = amap.(Axes{a});
            % signed dihedral of this model about the given axis (deg)
            phi_now = rad2deg(dihedral_signed(X,Y,Z, map.i(1),map.i(2),map.i(3),map.i(4)));

            % rotate for each angle -> N-N
            nn_here = nan(1,numel(nang));
            for j = 1:numel(nang)
                delta = wrapTo180(nang(j) - phi_now);
                [Xr,Yr,Zr] = rotate_about_bond(X,Y,Z, map.axis(1),map.axis(2), map.rotate, deg2rad(delta));
                nn_here(j) = norm([Xr(7)-Xr(1) , Yr(7)-Yr(1) , Zr(7)-Zr(1)]);  % Å
            end
            NN_abs(m,a,:) = nn_here;
            dXabs(m,a,:)  = abs(nn_here - nn_here(idxRef));  % |dx| relative to the reference angle refAngleDeg

            rowsAbs(end+1,:) = {sprintf('M%d',m), Axes{a}, nn_here(1), nn_here(2), nn_here(3), nn_here(4)}; %#ok<AGROW>
            rowsDx(end+1,:)  = {sprintf('M%d',m), Axes{a}, dXabs(m,a,1), dXabs(m,a,2), dXabs(m,a,3), dXabs(m,a,4)}; %#ok<AGROW>
        end
    end

    % -------- print the table --------
    TblAbs = cell2table(rowsAbs, 'VariableNames', {'model','axis','NN_180_A','NN_m90_A','NN_0_A','NN_90_A'});
    TblDx  = cell2table(rowsDx,  'VariableNames', {'model','axis','abs_dNN_180_A','abs_dNN_m90_A','abs_dNN_0_A','abs_dNN_90_A'});
    show_table(TblAbs, 'N–N (Å) @ absolute angles');
    show_table(TblDx,  sprintf('|Δx| (Å) relative to %g°', refAngleDeg));

    % -------- plots (uniform style + native marker overlay) --------
    C  = lines(numel(models));      % colour is the only difference
    mk = 'o';                       % line markers (for the curves)
    LW = 1.4; MS = 34;

    % (1) N–N vs absolute angle + native N–N (markers only)
    fig1 = figure('Color','w','Name','N–N vs absolute angle (Å)','NumberTitle','off');
    tl1  = tiledlayout(fig1,3,1,'Padding','compact','TileSpacing','compact');

    for a = 1:3
        nexttile(tl1,a); hold on;

        % native N-N: markers only (open diamonds), no line
        for m = 1:numel(models)
            Mi = T(T.(modelCol)==models(m), :);
            [X0,Y0,Z0,ok0] = coords7(Mi, xyz);
            if ~ok0, continue; end
            nn_native = norm([X0(7)-X0(1), Y0(7)-Y0(1), Z0(7)-Z0(1)]);
            scatter(1:4, nn_native*ones(1,4), 28, ...
                'Marker','d', 'MarkerEdgeColor', C(m,:), 'MarkerFaceColor','none', ...
                'LineWidth',1.0, 'HandleVisibility','off');   % keep out of the legend
        end

        % N-N curve vs absolute angle (solid line + circle markers, colour only differs)
        for m = 1:numel(models)
            vals = squeeze(NN_abs(m,a,:)).';
            plot(1:4, vals, '-', 'Color', C(m,:), 'LineWidth', LW);
            scatter(1:4, vals, MS, C(m,:), 'filled', 'Marker', mk, ...
                    'MarkerFaceAlpha',0.85, 'MarkerEdgeAlpha',0.85);
        end

        grid on; xlim([1 4]); xticks(1:4); xticklabels({'180°','-90°','0°','90°'});
        ylabel('N–N (Å)');
        title(sprintf('%s | N–N @ 180,-90,0,90° (diamond = native N–N)', upper(Axes{a})));
        if a==1
            legend(compose('M%d',1:numel(models)), 'Location','eastoutside');
        end
        hold off;
    end

    % (2) |dx| vs absolute angle (relative to refAngleDeg)
    fig2 = figure('Color','w','Name','|Δx| vs absolute angle (Å)','NumberTitle','off');
    tl2  = tiledlayout(fig2,3,1,'Padding','compact','TileSpacing','compact');

    for a = 1:3
        nexttile(tl2,a); hold on;
        plot(1:4, [0 0 0 0], 'k:'); % baseline

        for m = 1:numel(models)
            vals = squeeze(dXabs(m,a,:)).';
            plot(1:4, vals, '-', 'Color', C(m,:), 'LineWidth', LW);
            scatter(1:4, vals, MS, C(m,:), 'filled', 'Marker', mk, ...
                    'MarkerFaceAlpha',0.85, 'MarkerEdgeAlpha',0.85);
        end

        grid on; xlim([1 4]); xticks(1:4); xticklabels({'180°','-90°','0°','90°'});
        ylabel('|Δx| (Å)');
        title(sprintf('%s | |Δx| relative to %g°', upper(Axes{a}), refAngleDeg));
        if a==1
            legend(compose('M%d',1:numel(models)), 'Location','eastoutside');
        end
        hold off;
    end
end

% ================= helpers =================
function T = read_table_flex(file)
    [~,~,ext] = fileparts(file);
    switch lower(ext)
        case {'.xlsx','.xls'}, T = readtable(file,'VariableNamingRule','preserve');
        case '.csv'
            try, T = readtable(file,'VariableNamingRule','preserve','FileType','text');
            catch, T = readtable(file,'VariableNamingRule','preserve');
            end
        otherwise, error('Unsupported file: %s', ext);
    end
end
function T = normalize_headers(T)
    T.Properties.VariableNames = lower(regexprep(T.Properties.VariableNames, '\s+', ''));
end
function xyz = pick_xyz_cols(T)
    xyz = intersect({'x','y','z'}, T.Properties.VariableNames,'stable');
    if numel(xyz)==3, return; end
    numCols = T.Properties.VariableNames( varfun(@isnumeric, T, 'OutputFormat','uniform') );
    assert(numel(numCols)>=3, 'Need at least 3 numeric columns for XYZ.');
    v = var(T{:,numCols}, 0, 1, 'omitnan');
    [~,ord] = sort(v,'descend');
    xyz = numCols(ord(1:3)); xyz = sort(xyz);
end
function s = pick_first(T, names)
    s = "";
    for k=1:numel(names)
        if any(strcmpi(T.Properties.VariableNames, lower(names(k))))
            s = string(lower(names(k))); return;
        end
    end
end
function A = standardize_atom(a)
    s = string(a);
    s = lower(strrep(strrep(s,'_',''),'-',''));
    A = strings(size(s));
    for i=1:numel(s)
        t = s(i);
        if t=="nl" || t=="nleft", A(i)="NL";
        elseif t=="nr" || t=="nright", A(i)="NR";
        elseif startsWith(t,"c") && strlength(t)==2 && isstrprop(extractAfter(t,1),'digit')
            A(i) = upper(t);
        elseif t=="c1", A(i)="C1"; elseif t=="c2", A(i)="C2";
        elseif t=="c3", A(i)="C3"; elseif t=="c4", A(i)="C4"; elseif t=="c5", A(i)="C5";
        else, A(i)=upper(t);
        end
    end
end
function [X,Y,Z,ok] = coords7(Mi, xyz)
    names = string(Mi.atom);
    need  = ["NL","C1","C2","C3","C4","C5","NR"];
    idx = zeros(1,7);
    for k=1:7
        hit = find(names==need(k), 1, 'first');
        if isempty(hit), X=[];Y=[];Z=[]; ok=false; return; end
        idx(k)=hit;
    end
    Xi = Mi.(xyz{1}); Yi = Mi.(xyz{2}); Zi = Mi.(xyz{3});
    X = Xi(idx).'; Y = Yi(idx).'; Z = Zi(idx).';
    ok = true;
end
function a = dihedral_signed(X,Y,Z,i1,i2,i3,i4)
    A=[X(i1) Y(i1) Z(i1)]; B=[X(i2) Y(i2) Z(i2)];
    C=[X(i3) Y(i3) Z(i3)]; D=[X(i4) Y(i4) Z(i4)];
    b1=B-A; b2=C-B; b3=D-C;
    n1=cross(b1,b2); n2=cross(b2,b3);
    L2=norm(b2); L1=norm(n1); L3=norm(n2);
    if any([L1,L2,L3]<1e-12), a=NaN; return; end
    a = atan2( dot(b2/L2, cross(n1,n2)), dot(n1,n2) ); % rad
end
function [Xr,Yr,Zr] = rotate_about_bond(X,Y,Z,iL,iR,idxRot,theta)
    Xr=X; Yr=Y; Zr=Z;
    CL=[X(iL) Y(iL) Z(iL)]; CR=[X(iR) Y(iR) Z(iR)];
    axis = CR-CL; L=norm(axis); if L<1e-12, return; end
    k=(axis/L).'; K=[0 -k(3) k(2); k(3) 0 -k(1); -k(2) k(1) 0];
    R = eye(3)*cos(theta) + sin(theta)*K + (1-cos(theta))*(k*k.');
    for ii = idxRot
        v=[X(ii)-CL(1); Y(ii)-CL(2); Z(ii)-CL(3)];
        vr=R*v;
        Xr(ii)=vr(1)+CL(1); Yr(ii)=vr(2)+CL(2); Zr(ii)=vr(3)+CL(3);
    end
end
function a = wrapTo180(a), a = mod(a+180,360)-180; end
function x = toNum(x)
    if iscell(x), x = string(x); end
    if isstring(x) || ischar(x) || iscategorical(x)
        x = str2double(string(x));
    end
    x = double(x);
end
function show_table(Tbl, ttl)
    if usejava('jvm') && feature('ShowFigureWindows')
        f = uifigure('Name',ttl,'Color','w');
        uitable(f,'Data',Tbl, 'Units','normalized','Position',[0 0 1 1]);
    else
        fprintf('\n==== %s ====\n', ttl); disp(Tbl);
    end
end
function m = axis_map()
    m.phi1.i     = [1 2 3 4];  m.phi1.axis  = [2 3];  m.phi1.rotate = 3:7; % C1–C2, rotate C3..NR
    m.phi2.i     = [2 3 4 5];  m.phi2.axis  = [3 4];  m.phi2.rotate = 4:7; % C2–C3, rotate C4..NR
    m.phi3.i     = [3 4 5 6];  m.phi3.axis  = [4 5];  m.phi3.rotate = 5:7; % C3–C4, rotate C5..NR
end
