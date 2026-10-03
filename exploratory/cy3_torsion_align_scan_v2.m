function out = cy3_torsion_align_scan_v2(xlsxFile, opts)
% cy3_torsion_align_scan_v2
%   (A) save/plot the raw coordinates
%   (B) save/plot coordinates whose phi_k dihedrals match 5NS4, set by internal rotation (torsion-aligned)
%   (C) build/plot coordinates rigidly overlaid on the phi_k segment (CAG-CAH etc.)
%   + (as before) compute dCCAbs(phi) and dx(phi)

    arguments
        xlsxFile (1,1) string

        opts.PhiDeg (1,:) double = -180:1:180
        opts.BondMax (1,1) double = 1.8
        opts.BondMin (1,1) double = 0.1
        opts.UnitScale (1,1) double = 1.0

        opts.CidColumn (1,1) double = 9
        opts.AtomColumn (1,1) double = 2
        opts.XYZColumns (1,3) double = [5 6 7]

        opts.AxisAtoms (1,5) string = ["CAG","CAH","CAI","CAJ","CAK"]
        opts.CCAtoms (1,2) string = ["CAZ","CBA"]
        opts.AnchorAtom (1,1) string = "NAU"
        opts.TailAtom (1,1) string = "NAV"

        opts.SkipIncomplete (1,1) logical = true

        opts.PlotMode (1,1) string {mustBeMember(opts.PlotMode, ["overlay","mean_sd","both","none"])} = "overlay"
        opts.FontName (1,1) string = "Arial"
        opts.YLimDx (1,2) double = [NaN NaN]
        opts.YLimAbs (1,2) double = [NaN NaN]

        % ---- aligned coord storage ----
        opts.StoreAlignedAxes (1,:) double = 1:4
        opts.SaveAlignedMat (1,1) string = ""

        % ---- 3D plot controls ----
        opts.Plot3DRigidOverlay (1,1) logical = false
        opts.Plot3DShowLegend (1,1) logical = true
        opts.Plot3DLabelAtoms (1,1) logical = false

        % ---- NEW: stage plots ----
        opts.PlotStages (1,1) string {mustBeMember(opts.PlotStages, ["none","raw","torsion","rigid","all"])} = "none"
        opts.StageAxis (1,1) double {mustBeMember(opts.StageAxis, [1 2 3 4])} = 1
        opts.StageView (1,2) double = [-35 20]
    end

    C = readcell(xlsxFile);

    cidRaw = C(:, opts.CidColumn);
    isStart = is_block_start_(cidRaw);
    startIdx = find(isStart);

    if isempty(startIdx)
        error("Could not find the start row of the CID block. Check CidColumn=%d.", opts.CidColumn);
    end

    nBlocks = numel(startIdx);
    refBlock = nBlocks;

    axisPairs = [opts.AxisAtoms(1:4).', opts.AxisAtoms(2:5).'];
    defs = dihedral_defs_(opts);

    ref = read_block_(C, startIdx, refBlock, opts);
    idxRef = resolve_indices_(ref.atom, axisPairs, opts.CCAtoms, opts.AnchorAtom, opts.TailAtom);

    Aref = adjacency_from_cutoff_(ref.xyz, opts.BondMax, opts.BondMin);
    Gref = graph(Aref);

    backboneRef = backbone_indices_(ref.atom, opts);
    assignRef = assign_to_backbone_(Gref, ref.xyz, backboneRef);

    phiRefDeg = compute_dihedrals_deg_(ref.atom, ref.xyz, defs);

    phiScanDeg = opts.PhiDeg(:);

    modelIDAll = strings(nBlocks, 1);
    statusAll = strings(nBlocks, 1);

    kept = false(nBlocks, 1);

    dxCell = cell(nBlocks, 1);
    dAbsCell = cell(nBlocks, 1);
    dBaseAll = nan(nBlocks, 4);

    phi0All = nan(nBlocks, 4);
    deltaAll = nan(nBlocks, 4);
    phiAlignedAll = nan(nBlocks, 4);

    axKeep = unique(opts.StoreAlignedAxes(:).');
    axKeep = axKeep(axKeep >= 1 & axKeep <= 4);
    nAxKeep = numel(axKeep);

    rawAtomCell = cell(nBlocks, 1);
    rawXYZCell = cell(nBlocks, 1);

    atomCell = cell(nBlocks, 1);
    xyzAlignedCell = cell(nBlocks, nAxKeep);

    dbg = struct;
    dbg.cazInMove = false(nBlocks, 4);
    dbg.cbaInMove = false(nBlocks, 4);
    dbg.cazDisp = nan(nBlocks, 4);
    dbg.cbaDisp = nan(nBlocks, 4);
    dbg.countCAZ = nan(nBlocks, 1);
    dbg.countCBA = nan(nBlocks, 1);
    dbg.assignPos = cell(nBlocks, 1);

    for m = 1:nBlocks
        data = read_block_(C, startIdx, m, opts);
        modelIDAll(m) = data.modelID;

        rawAtomCell{m} = data.atom;
        rawXYZCell{m} = data.xyz;

        dbg.countCAZ(m) = sum(data.atom == opts.CCAtoms(1));
        dbg.countCBA(m) = sum(data.atom == opts.CCAtoms(2));

        ok = has_required_atoms_(data.atom, axisPairs, opts.CCAtoms, opts.AnchorAtom, opts.TailAtom);
        if ~ok
            if opts.SkipIncomplete
                statusAll(m) = "skipped_missing_atoms";
                continue;
            end
            error("Required atom name missing: %s", data.modelID);
        end

        idx = resolve_indices_(data.atom, axisPairs, opts.CCAtoms, opts.AnchorAtom, opts.TailAtom);

        A = adjacency_from_cutoff_(data.xyz, opts.BondMax, opts.BondMin);
        G = graph(A);

        backboneIdx = backbone_indices_(data.atom, opts);
        assignPos = assign_to_backbone_(G, data.xyz, backboneIdx);
        dbg.assignPos{m} = assignPos;

        phi0Deg = compute_dihedrals_deg_(data.atom, data.xyz, defs);
        phi0All(m, :) = phi0Deg;

        deltaDeg = wrapTo180_(phiRefDeg - phi0Deg);
        deltaDeg = refine_delta_by_check_(data, G, idx, defs, phiRefDeg, deltaDeg, assignPos, backboneIdx);

        deltaAll(m, :) = deltaDeg;

        phiAlignedDeg = compute_aligned_dihedrals_(data, G, idx, defs, deltaDeg, assignPos, backboneIdx);
        phiAlignedAll(m, :) = phiAlignedDeg;

        [dx, dAbs, dBase] = scan_cc_aligned_(data, G, idx, phiScanDeg, deltaDeg, assignPos, backboneIdx);

        dxCell{m} = dx;
        dAbsCell{m} = dAbs;
        dBaseAll(m, :) = dBase;

        kept(m) = true;
        statusAll(m) = "ok";

        atomCell{m} = data.atom;

        for a = 1:nAxKeep
            k = axKeep(a);

            [xyzAligned, moveIdx] = rotate_axis_with_backbone_rule_( ...
                data.xyz, idx.axis(k, :), deltaDeg(k), assignPos, k);

            xyzAlignedCell{m, a} = xyzAligned;

            dbg.cazInMove(m, k) = ismember(idx.cc(1), moveIdx);
            dbg.cbaInMove(m, k) = ismember(idx.cc(2), moveIdx);

            dbg.cazDisp(m, k) = norm(xyzAligned(idx.cc(1), :) - data.xyz(idx.cc(1), :));
            dbg.cbaDisp(m, k) = norm(xyzAligned(idx.cc(2), :) - data.xyz(idx.cc(2), :));
        end
    end

    out = struct;

    out.file = xlsxFile;
    out.phiScanDeg = phiScanDeg;

    out.refModelID = ref.modelID;
    out.phiRefDeg = phiRefDeg;

    out.modelID = modelIDAll(kept);
    out.phi0Deg = phi0All(kept, :);
    out.deltaDeg = deltaAll(kept, :);
    out.phiAlignedDeg = phiAlignedAll(kept, :);

    out.dxCC = cat(3, dxCell{kept});
    out.dCCAbs = cat(3, dAbsCell{kept});
    out.dCCBase = dBaseAll(kept, :);

    out.statusTable = table(modelIDAll, statusAll);

    out.raw = struct;
    out.raw.atom = rawAtomCell(kept);
    out.raw.xyz = rawXYZCell(kept);

    out.aligned = struct;
    out.aligned.axes = axKeep;
    out.aligned.atom = atomCell(kept);
    out.aligned.xyz = xyzAlignedCell(kept, :);

    out.debug = struct;
    out.debug.cazInMove = dbg.cazInMove(kept, :);
    out.debug.cbaInMove = dbg.cbaInMove(kept, :);
    out.debug.cazDisp = dbg.cazDisp(kept, :);
    out.debug.cbaDisp = dbg.cbaDisp(kept, :);
    out.debug.countCAZ = dbg.countCAZ(kept);
    out.debug.countCBA = dbg.countCBA(kept);
    out.debug.assignPos = dbg.assignPos(kept);

    if opts.SaveAlignedMat ~= ""
        S = out; %#ok<NASGU>
        save(opts.SaveAlignedMat, "S");
    end

    if opts.PlotMode ~= "none"
        plot_cc_scans_(out, opts);
    end

    if opts.PlotStages ~= "none"
        plot_alignment_stages_(out, ref, idxRef, assignRef, opts);
    end
end

% =========================
% Stage plots: raw -> torsion -> rigid
% =========================
function plot_alignment_stages_(out, ref, idxRef, assignRef, opts)
    axK = opts.StageAxis;

    doRaw = (opts.PlotStages == "raw") || (opts.PlotStages == "all");
    doTor = (opts.PlotStages == "torsion") || (opts.PlotStages == "all");
    doRig = (opts.PlotStages == "rigid") || (opts.PlotStages == "all");

    if doRaw
        plot_stage_core_(out.raw.atom, out.raw.xyz, ref, idxRef, axK, opts, "Raw coords (no torsion, no rigid)");
    end

    if doTor
        aIdx = find(out.aligned.axes == axK, 1);
        if isempty(aIdx)
            error("StoreAlignedAxes must include StageAxis=%d to plot the torsion stage.", axK);
        end
        plot_stage_core_(out.aligned.atom, out.aligned.xyz(:, aIdx), ref, idxRef, axK, opts, "After torsion alignment to ref \phi_k (no rigid)");
    end

    if doRig
        aIdx = find(out.aligned.axes == axK, 1);
        if isempty(aIdx)
            error("StoreAlignedAxes must include StageAxis=%d to plot the rigid stage.", axK);
        end

        xyzRig = cell(size(out.aligned.xyz, 1), 1);
        for m = 1:numel(xyzRig)
            xyzIn = out.aligned.xyz{m, aIdx};
            atomIn = out.aligned.atom{m};

            xyzRig{m} = rigid_overlay_to_ref_( ...
                xyzIn, atomIn, ...
                ref.xyz, ref.atom, ...
                idx_for_atomlist_(atomIn, opts.AxisAtoms(axK)), ...
                idx_for_atomlist_(atomIn, opts.AxisAtoms(axK+1)), ...
                idxRef.axis(axK, 1), idxRef.axis(axK, 2), ...
                idx_for_atom_(atomIn, opts.AnchorAtom), idxRef.anchor);
        end

        plot_stage_core_(out.aligned.atom, xyzRig, ref, idxRef, axK, opts, "After torsion + rigid overlay to ref axis segment");
    end
end

function plot_stage_core_(atomCell, xyzCell, ref, idxRef, axK, opts, subtitleText)
    modelID = string(ref.modelID);
    modelID = [modelID; string(out_ids_(atomCell))]; %#ok<NASGU> % not used; kept for structure

    nModels = numel(atomCell);
    colors = lines(nModels);

    fig = figure('Color','w', 'Position',[120 120 980 760]);
    ax = axes('Parent', fig);
    hold(ax, 'on');
    grid(ax, 'on');
    box(ax, 'on');
    axis(ax, 'equal');
    view(ax, opts.StageView(1), opts.StageView(2));

    title(ax, sprintf("Stage: %s | axis %d", subtitleText, axK), 'FontName', opts.FontName, 'Interpreter','none');

    h = gobjects(nModels, 1);

    for m = 1:nModels
        atom = string(atomCell{m});
        xyz = xyzCell{m};

        bb = backbone_polyline_indices_(atom, opts);
        cc = cc_indices_(atom, opts);

        c = colors(m, :);

        P = xyz(bb, :);
        h(m) = plot3(ax, P(:,1), P(:,2), P(:,3), 'Color', c, 'LineWidth', 1.6);

        scatter3(ax, P(:,1), P(:,2), P(:,3), 46, 'MarkerFaceColor', c, 'MarkerEdgeColor', 'k', 'HandleVisibility','off');

        pZ = xyz(cc(1), :);
        pB = xyz(cc(2), :);

        plot3(ax, [pZ(1) pB(1)], [pZ(2) pB(2)], [pZ(3) pB(3)], ...
            'Color', c, 'LineStyle', '--', 'LineWidth', 2.2, 'HandleVisibility','off');

        scatter3(ax, pZ(1), pZ(2), pZ(3), 90, 's', 'MarkerFaceColor', 'w', 'MarkerEdgeColor', c, 'LineWidth', 1.4, 'HandleVisibility','off');
        scatter3(ax, pB(1), pB(2), pB(3), 90, 's', 'MarkerFaceColor', c, 'MarkerEdgeColor', 'k', 'LineWidth', 1.4, 'HandleVisibility','off');

        if opts.Plot3DLabelAtoms
            label_atoms_(ax, atom, xyz, [bb, cc], opts.FontName, c);
        end
    end

    xlabel(ax, "X (\AA)", 'FontName', opts.FontName, 'Interpreter','tex');
    ylabel(ax, "Y (\AA)", 'FontName', opts.FontName, 'Interpreter','tex');
    zlabel(ax, "Z (\AA)", 'FontName', opts.FontName, 'Interpreter','tex');

    if opts.Plot3DShowLegend
        lgd = legend(ax, h, 'Location','eastoutside', 'Interpreter','none', 'FontName', opts.FontName);
        lgd.Box = 'off';
    end
end

function ids = out_ids_(atomCell)
    ids = strings(numel(atomCell), 1);
    for i = 1:numel(atomCell)
        ids(i) = "model_" + string(i);
    end
end

function bb = backbone_polyline_indices_(atom, opts)
    names = [opts.AnchorAtom, opts.AxisAtoms(:).', opts.TailAtom];
    bb = nan(1, numel(names));
    for i = 1:numel(names)
        bb(i) = find(atom == names(i), 1);
    end
end

function cc = cc_indices_(atom, opts)
    cc = nan(1,2);
    cc(1) = find(atom == opts.CCAtoms(1), 1);
    cc(2) = find(atom == opts.CCAtoms(2), 1);
end

function idx = idx_for_atom_(atom, name)
    idx = find(atom == string(name), 1);
end

function idx = idx_for_atomlist_(atom, name)
    idx = find(atom == string(name), 1);
end

% =========================
% core analysis (same logic as v1)
% =========================
function tf = is_block_start_(cidRaw)
    isText = cellfun(@(x) ischar(x) || isstring(x), cidRaw);
    cidStr = strings(size(cidRaw));
    cidStr(isText) = string(cidRaw(isText));
    tf = isText;
    tf = tf & (cidStr ~= "");
    tf = tf & (cidStr ~= "NaN");
end

function data = read_block_(C, startIdx, m, opts)
    i0 = startIdx(m);
    if m < numel(startIdx)
        i1 = startIdx(m + 1) - 1;
    else
        i1 = size(C, 1);
    end

    blk = C(i0:i1, :);

    modelID = "";
    if size(blk, 2) >= opts.CidColumn
        x = blk{1, opts.CidColumn};
        if ischar(x) || isstring(x)
            modelID = string(x);
        end
    end

    if modelID == "" || modelID == "NaN"
        modelID = "MODEL_" + string(m);
    end

    atom = string(blk(:, opts.AtomColumn));

    x = to_double_col_(blk(:, opts.XYZColumns(1)));
    y = to_double_col_(blk(:, opts.XYZColumns(2)));
    z = to_double_col_(blk(:, opts.XYZColumns(3)));

    xyz = [x, y, z];
    xyz = xyz .* opts.UnitScale;

    valid = ~any(isnan(xyz), 2);
    atom = atom(valid);
    xyz = xyz(valid, :);

    data = struct;
    data.modelID = modelID;
    data.atom = atom;
    data.xyz = xyz;
end

function defs = dihedral_defs_(opts)
    defs = strings(4, 4);
    defs(1, :) = [opts.AnchorAtom, opts.AxisAtoms(1), opts.AxisAtoms(2), opts.AxisAtoms(3)];
    defs(2, :) = [opts.AxisAtoms(1), opts.AxisAtoms(2), opts.AxisAtoms(3), opts.AxisAtoms(4)];
    defs(3, :) = [opts.AxisAtoms(2), opts.AxisAtoms(3), opts.AxisAtoms(4), opts.AxisAtoms(5)];
    defs(4, :) = [opts.AxisAtoms(3), opts.AxisAtoms(4), opts.AxisAtoms(5), opts.TailAtom];
end

function ok = has_required_atoms_(atom, axisPairs, ccAtoms, anchorAtom, tailAtom)
    req = [axisPairs(:); ccAtoms(:); anchorAtom; tailAtom];
    ok = all(ismember(req, atom));
end

function idx = resolve_indices_(atom, axisPairs, ccAtoms, anchorAtom, tailAtom)
    idxAxis = nan(4, 2);
    for k = 1:4
        idxAxis(k, 1) = find(atom == axisPairs(k, 1), 1);
        idxAxis(k, 2) = find(atom == axisPairs(k, 2), 1);
    end

    idxCC = nan(1, 2);
    idxCC(1) = find(atom == ccAtoms(1), 1);
    idxCC(2) = find(atom == ccAtoms(2), 1);

    idxAnchor = find(atom == anchorAtom, 1);
    idxTail = find(atom == tailAtom, 1);

    idx = struct;
    idx.axis = idxAxis;
    idx.cc = idxCC;
    idx.anchor = idxAnchor;
    idx.tail = idxTail;
end

function A = adjacency_from_cutoff_(coords, bondMax, bondMin)
    D = sqrt(sum((reshape(coords, [], 1, 3) - reshape(coords, 1, [], 3)).^2, 3));
    A = D < bondMax;
    A = A & (D > bondMin);
end

function bbIdx = backbone_indices_(atom, opts)
    bbNames = [opts.AnchorAtom, opts.AxisAtoms(:).', opts.TailAtom];
    bbIdx = nan(1, numel(bbNames));
    for i = 1:numel(bbNames)
        bbIdx(i) = find(atom == bbNames(i), 1);
    end
end

function pos = assign_to_backbone_(G, xyz, bbIdx)
    n = size(xyz, 1);
    k = numel(bbIdx);

    D = inf(n, k);
    for j = 1:k
        s = bbIdx(j);
        d = distances(G, s);
        D(:, j) = d(:);
    end

    pos = nan(n, 1);

    for i = 1:n
        di = D(i, :);
        if any(isfinite(di))
            [~, j] = min(di);
            pos(i) = j;
        else
            p = xyz(i, :);
            P = xyz(bbIdx, :);
            dd = sum((P - p).^2, 2);
            [~, j] = min(dd);
            pos(i) = j;
        end
    end
end

function phiDeg = compute_dihedrals_deg_(atom, xyz, defs)
    phiDeg = nan(1, 4);
    for k = 1:4
        ia = find(atom == defs(k, 1), 1);
        ib = find(atom == defs(k, 2), 1);
        ic = find(atom == defs(k, 3), 1);
        id = find(atom == defs(k, 4), 1);
        phiDeg(k) = dihedral_deg_(xyz(ia, :), xyz(ib, :), xyz(ic, :), xyz(id, :));
    end
end

function deltaDeg = refine_delta_by_check_(data, G, idx, defs, phiRefDeg, deltaDeg, assignPos, backboneIdx)
    %#ok<INUSD>
    for k = 1:4
        [xyz1, ~] = rotate_axis_with_backbone_rule_(data.xyz, idx.axis(k, :), deltaDeg(k), assignPos, k);
        p1 = compute_dihedrals_deg_(data.atom, xyz1, defs);
        e1 = abs(wrapTo180_(p1(k) - phiRefDeg(k)));

        [xyz2, ~] = rotate_axis_with_backbone_rule_(data.xyz, idx.axis(k, :), -deltaDeg(k), assignPos, k);
        p2 = compute_dihedrals_deg_(data.atom, xyz2, defs);
        e2 = abs(wrapTo180_(p2(k) - phiRefDeg(k)));

        if e2 < e1
            deltaDeg(k) = -deltaDeg(k);
        end
    end
end

function phiAlignedDeg = compute_aligned_dihedrals_(data, G, idx, defs, deltaDeg, assignPos, backboneIdx)
    %#ok<INUSD>
    phiAlignedDeg = nan(1, 4);
    for k = 1:4
        [xyz, ~] = rotate_axis_with_backbone_rule_(data.xyz, idx.axis(k, :), deltaDeg(k), assignPos, k);
        phiAfter = compute_dihedrals_deg_(data.atom, xyz, defs);
        phiAlignedDeg(k) = phiAfter(k);
    end
end

function [xyzOut, moveIdx] = rotate_axis_with_backbone_rule_(xyz0, axisIdx, thetaDeg, assignPos, axisK)
    pA = xyz0(axisIdx(1), :);
    pB = xyz0(axisIdx(2), :);

    u = pB - pA;
    u = u ./ norm(u);

    cutPos = axisK + 2;
    moveIdx = find(assignPos >= cutPos);

    xyzOut = xyz0;
    xyzOut(moveIdx, :) = rotate_points_core_(xyz0(moveIdx, :), pA, u, deg2rad(thetaDeg));
end

function [dx, dAbs, dBase] = scan_cc_aligned_(data, G, idx, phiScanDeg, deltaDeg, assignPos, backboneIdx)
    %#ok<INUSD>
    nPhi = numel(phiScanDeg);

    dx = zeros(nPhi, 4);
    dAbs = zeros(nPhi, 4);
    dBase = zeros(1, 4);

    for k = 1:4
        [xyzBase, ~] = rotate_axis_with_backbone_rule_(data.xyz, idx.axis(k, :), deltaDeg(k), assignPos, k);
        d0 = norm(xyzBase(idx.cc(1), :) - xyzBase(idx.cc(2), :));
        dBase(k) = d0;

        for i = 1:nPhi
            theta = deltaDeg(k) + phiScanDeg(i);
            [xyz, ~] = rotate_axis_with_backbone_rule_(data.xyz, idx.axis(k, :), theta, assignPos, k);
            d = norm(xyz(idx.cc(1), :) - xyz(idx.cc(2), :));

            dAbs(i, k) = d;
            dx(i, k) = d - d0;
        end
    end
end

function ang = dihedral_deg_(p1, p2, p3, p4)
    b0 = p2 - p1;
    b1 = p3 - p2;
    b2 = p4 - p3;

    b1n = b1 ./ norm(b1);

    v = b0 - dot(b0, b1n) .* b1n;
    w = b2 - dot(b2, b1n) .* b1n;

    x = dot(v, w);
    y = dot(cross(b1n, v), w);

    ang = rad2deg(atan2(y, x));
    ang = wrapTo180_(ang);
end

function a = wrapTo180_(a)
    a = mod(a + 180, 360) - 180;
end

function v = to_double_col_(col)
    v = nan(size(col));
    for i = 1:numel(col)
        x = col{i};
        if isnumeric(x) && isscalar(x)
            v(i) = double(x);
        elseif ischar(x) || isstring(x)
            y = str2double(string(x));
            if ~isnan(y)
                v(i) = y;
            end
        end
    end
end

function Pout = rotate_points_core_(P, p0, u, theta)
    P0 = P - p0;

    u = u(:).';
    c = cos(theta);
    s = sin(theta);

    dotProd = P0 * u.';
    term1 = P0 .* c;
    term2 = cross(repmat(u, size(P0, 1), 1), P0, 2) .* s;
    term3 = (dotProd * u) .* (1 - c);

    Pout = term1 + term2 + term3 + p0;
end

% =========================
% rigid overlay: match axis segment + azimuth by anchor
% =========================
function xyzOut = rigid_overlay_to_ref_(xyzIn, atomIn, xyzRef, atomRef, idxAin, idxBin, idxAref, idxBref, idxAnchorIn, idxAnchorRef)
    pA = xyzIn(idxAin, :);
    pB = xyzIn(idxBin, :);

    pAref = xyzRef(idxAref, :);
    pBref = xyzRef(idxBref, :);

    if ~isempty(idxAnchorIn) && ~isnan(idxAnchorIn)
        q = xyzIn(idxAnchorIn, :);
    else
        q = xyzIn(1, :);
    end

    if ~isempty(idxAnchorRef) && ~isnan(idxAnchorRef)
        qref = xyzRef(idxAnchorRef, :);
    else
        qref = xyzRef(1, :);
    end

    xyz1 = xyzIn - pA + pAref;
    pB1 = pB - pA + pAref;
    q1 = q - pA + pAref;

    v1 = pB1 - pAref;
    v2 = pBref - pAref;

    R1 = rotmat_align_vectors_(v1, v2);

    xyz2 = (R1 * (xyz1 - pAref).').' + pAref;
    q2 = (R1 * (q1 - pAref).').' + pAref;

    u = v2 ./ norm(v2);

    a = proj_perp_(q2 - pAref, u);
    aref = proj_perp_(qref - pAref, u);

    if norm(a) < 1e-12 || norm(aref) < 1e-12
        xyzOut = xyz2;
        return;
    end

    a = a ./ norm(a);
    aref = aref ./ norm(aref);

    ang = atan2(dot(u, cross(a, aref)), dot(a, aref));
    R2 = rot_about_axis_(u, ang);

    xyzOut = (R2 * (xyz2 - pAref).').' + pAref;
end

function v = proj_perp_(v, u)
    v = v - dot(v, u) .* u;
end

function R = rotmat_align_vectors_(a, b)
    a = a(:);
    b = b(:);

    na = norm(a);
    nb = norm(b);

    if na < 1e-12 || nb < 1e-12
        R = eye(3);
        return;
    end

    a = a ./ na;
    b = b ./ nb;

    v = cross(a, b);
    s = norm(v);
    c = dot(a, b);

    if s < 1e-12
        if c > 0
            R = eye(3);
            return;
        end

        tmp = [1;0;0];
        if abs(dot(tmp, a)) > 0.9
            tmp = [0;1;0];
        end

        v = cross(a, tmp);
        v = v ./ norm(v);
        R = rot_about_axis_(v, pi);
        return;
    end

    v = v ./ s;

    K = [  0    -v(3)  v(2);
          v(3)   0    -v(1);
         -v(2)  v(1)   0  ];

    R = eye(3) + K * s + (K * K) * (1 - c);
end

function R = rot_about_axis_(u, theta)
    u = u(:);
    u = u ./ norm(u);

    c = cos(theta);
    s = sin(theta);

    ux = u(1);
    uy = u(2);
    uz = u(3);

    R = [c+ux^2*(1-c),     ux*uy*(1-c)-uz*s, ux*uz*(1-c)+uy*s;
         uy*ux*(1-c)+uz*s, c+uy^2*(1-c),     uy*uz*(1-c)-ux*s;
         uz*ux*(1-c)-uy*s, uz*uy*(1-c)+ux*s, c+uz^2*(1-c)];
end

function label_atoms_(ax, atom, xyz, idxList, fontName, color)
    idxList = idxList(~isnan(idxList));
    idxList = unique(idxList);

    for i = 1:numel(idxList)
        k = idxList(i);
        text(ax, xyz(k,1), xyz(k,2), xyz(k,3), " " + atom(k), ...
            'FontName', fontName, 'FontSize', 9, 'Color', color, 'Interpreter','none', 'HandleVisibility','off');
    end
end

% =========================
% dx / dAbs plots (optional)
% =========================
function plot_cc_scans_(out, opts)
    if opts.PlotMode == "overlay" || opts.PlotMode == "both"
        plot_scan_family_(out.phiScanDeg, out.dxCC, out.modelID, out.refModelID, ...
            "\phi_%d: \Delta d_{C-C} aligned (N=%d)", "Torsion angle (°)", "\Delta d (\AA)", ...
            opts.FontName, opts.YLimDx);
    end

    if opts.PlotMode == "mean_sd"
        plot_scan_mean_sd_(out.phiScanDeg, out.dxCC, ...
            "\phi_%d: mean\pmSD \Delta d_{C-C} (N=%d)", "Torsion angle (°)", "\Delta d (\AA)", ...
            opts.FontName, opts.YLimDx);
    end

    if opts.PlotMode == "both"
        plot_scan_family_(out.phiScanDeg, out.dCCAbs, out.modelID, out.refModelID, ...
            "\phi_%d: d_{C-C}(\phi) aligned (N=%d)", "Torsion angle (°)", "d_{C-C} (\AA)", ...
            opts.FontName, opts.YLimAbs);
    end
end

function plot_scan_family_(phi, Y, modelID, refModelID, titleFmt, xlab, ylab, fontName, yLim)
    modelID = string(modelID);
    nModels = size(Y, 3);
    nPhi = numel(phi);

    colors = lines(nModels);
    lineStyles = {'-', '--', '-.', ':'};
    markers = {'o', 's', '^', 'd', 'v', '>', '<', 'p', 'h', 'x', '+'};

    interval = floor(nPhi / 14);
    if interval < 12
        interval = 12;
    end

    figure('Color', 'w', 'Position', [120 120 980 720]);

    for k = 1:4
        subplot(2, 2, k);
        hold on;
        box on;
        grid on;

        h = gobjects(nModels, 1);

        for m = 1:nModels
            ls = lineStyles{mod(m - 1, numel(lineStyles)) + 1};
            mk = markers{mod(m - 1, numel(markers)) + 1};

            offset = mod(2 * (m - 1), interval);
            mkIdx = (1 + offset):interval:nPhi;

            if mkIdx(end) ~= nPhi
                mkIdx(end + 1) = nPhi;
            end

            lw = 1.4;
            mfc = 'w';

            if modelID(m) == string(refModelID)
                lw = 2.6;
                mfc = colors(m, :);
            end

            h(m) = plot(phi, Y(:, k, m), ...
                'Color', colors(m, :), ...
                'LineStyle', ls, ...
                'LineWidth', lw, ...
                'Marker', mk, ...
                'MarkerIndices', mkIdx, ...
                'MarkerSize', 6, ...
                'MarkerFaceColor', mfc, ...
                'MarkerEdgeColor', colors(m, :), ...
                'DisplayName', modelID(m));
        end

        title(sprintf(titleFmt, k, nModels), 'FontName', fontName, 'Interpreter', 'tex');
        xlabel(xlab, 'FontName', fontName);
        ylabel(ylab, 'FontName', fontName, 'Interpreter', 'tex');

        xlim([min(phi) max(phi)]);
        axis square;

        if ~any(isnan(yLim))
            ylim(yLim);
        end

        lgd = legend(h, 'Location', 'eastoutside', 'Interpreter', 'none', 'FontName', fontName);
        lgd.Box = 'off';
    end
end

function plot_scan_mean_sd_(phi, Y, titleFmt, xlab, ylab, fontName, yLim)
    nModels = size(Y, 3);

    figure('Color', 'w', 'Position', [120 120 980 720]);

    for k = 1:4
        subplot(2, 2, k);
        hold on;
        box on;
        grid on;

        mu = mean(Y(:, k, :), 3);
        sd = std(Y(:, k, :), 0, 3);

        mu = mu(:);
        sd = sd(:);

        y1 = mu - sd;
        y2 = mu + sd;

        fill([phi; flipud(phi)], [y1; flipud(y2)], [0.9 0.9 0.9], 'EdgeColor', 'none', 'HandleVisibility', 'off');
        plot(phi, mu, 'LineWidth', 2);

        title(sprintf(titleFmt, k, nModels), 'FontName', fontName, 'Interpreter', 'tex');
        xlabel(xlab, 'FontName', fontName);
        ylabel(ylab, 'FontName', fontName, 'Interpreter', 'tex');

        xlim([min(phi) max(phi)]);
        axis square;

        if ~any(isnan(yLim))
            ylim(yLim);
        end
    end
end
