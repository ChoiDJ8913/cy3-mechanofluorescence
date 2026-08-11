function out = run_torsion_dx_pipeline(xlsxPath, outDir, opts)
%RUN_TORSION_DX_PIPELINE
% fully silent (no console output): only figures and files are produced.
%
% fixed connectivity (ground truth): CAZ-NAU-CAG-CAH-CAI-CAJ-CAK-NAV-CBA
% rotation axes (fixed): phi1 CAG-CAH, phi2 CAH-CAI, phi3 CAI-CAJ, phi4 CAJ-CAK
% moving side (fixed): the downstream atom set (towards CBA) rotates together
% 2D scan: rotations are applied sequentially, phi1 first and then phiK
%
% dAbs = |r(CAZ)-r(CBA)|
% dx = dAbs - d0   (d0 is defined by opts.D0Definition)
%
% produces:
% - 3 heat maps (phi1 vs phi2/3/4)
% - check (A): dx vs phiK at fixed phi1 slices
% - check (B): 3D overlay (path lines + CAZ/CBA markers)
% - MAT output (default) + optional TXT export (snapshots only)
%
% when there is no model column (ModelColumn=""), treat every row as a single model.

arguments
    xlsxPath (1,1) string
    outDir (1,1) string = pwd

    opts.ModelID (1,1) string = "5NS4"
    opts.Sheet = 1
    opts.Range (1,1) string = ""

    opts.ModelColumn (1,1) string = "modelID"
    opts.AtomColumn (1,1) string = "atom"
    opts.XColumn (1,1) string = "x"
    opts.YColumn (1,1) string = "y"
    opts.ZColumn (1,1) string = "z"

    opts.Unit (1,1) string = "A"
    opts.PhiGrid (1,:) double = -180:180

    opts.D0Definition (1,1) string {mustBeMember(opts.D0Definition, ["original","zerozero","phi1Slice","globalMean"])} = "original"

    opts.ValidationPhi1 (1,1) double = 0
    opts.OverlayPhi1 (1,1) double = 90
    opts.OverlayK (1,1) double {mustBeMember(opts.OverlayK, [2 3 4])} = 2
    opts.OverlayPhiK (1,:) double = [-180 0 180]

    opts.MakePlots (1,1) logical = true
    opts.SaveFigures (1,1) logical = true
    opts.FigureFormat (1,1) string {mustBeMember(opts.FigureFormat, ["png","fig"])} = "png"
    opts.FigureVisible (1,1) logical = false

    opts.SaveMode (1,1) string {mustBeMember(opts.SaveMode, ["resultsOnly","snapshots"])} = "snapshots"
    opts.ExportTXT (1,1) logical = false
    opts.TXTPath (1,1) string = ""
end

if ~isfolder(outDir)
    mkdir(outDir);
end

phi = opts.PhiGrid(:).';
nPhi = numel(phi);

idx0 = find(phi == 0, 1, "first");
if isempty(idx0)
    error("PhiGrid must include 0 deg.");
end

[~, iPhi1Val] = min(abs(phi - opts.ValidationPhi1));
[~, iPhi1Ov] = min(abs(phi - opts.OverlayPhi1));

pathNames = ["CAZ","NAU","CAG","CAH","CAI","CAJ","CAK","NAV","CBA"];
topo = buildTopology_(pathNames);

T = readTableWithOptionalRange_(xlsxPath, opts.Sheet, opts.Range);

colAtom = resolveVarName_(T, opts.AtomColumn);
colX = resolveVarName_(T, opts.XColumn);
colY = resolveVarName_(T, opts.YColumn);
colZ = resolveVarName_(T, opts.ZColumn);

useModelFilter = strlength(opts.ModelColumn) > 0;
maskModel = true(height(T), 1);

if useModelFilter
    hasModelCol = any(strcmpi(string(T.Properties.VariableNames), opts.ModelColumn));
    if hasModelCol
        colModel = resolveVarName_(T, opts.ModelColumn);
        modelVals = string(T.(colModel));
        maskModel = strcmpi(modelVals, opts.ModelID);
        if ~any(maskModel)
            error("ModelID '%s' not found in column '%s'.", opts.ModelID, colModel);
        end
    else
        maskModel = true(height(T), 1);
    end
end

Tm = T(maskModel, :);
atomValsM = string(Tm.(colAtom));

coordsAll = [Tm.(colX) Tm.(colY) Tm.(colZ)];
coordsAll = double(coordsAll);

idxPath = zeros(numel(pathNames), 1);
for i = 1:numel(pathNames)
    hit = find(strcmpi(atomValsM, pathNames(i)));
    if isempty(hit)
        error("Required atom '%s' not found (after filtering).", pathNames(i));
    end
    if numel(hit) > 1
        error("Atom '%s' appears multiple times. Disambiguate input.", pathNames(i));
    end
    idxPath(i) = hit;
end

coords0 = coordsAll(idxPath, :);
coords0 = double(coords0);

CAZ0 = coords0(topo.idx.CAZ, :).';
axis1_p0 = coords0(topo.idx.CAG, :).';
axis1_q0 = coords0(topo.idx.CAH, :).';

movePhi1 = topo.movingIdx.phi1;
movePhi1Rotate = movePhi1(movePhi1 ~= topo.idx.CAH);

dAbs = struct();
dAbs.phi2 = nan(nPhi, nPhi);
dAbs.phi3 = nan(nPhi, nPhi);
dAbs.phi4 = nan(nPhi, nPhi);

needSnapshots = strcmpi(opts.SaveMode, "snapshots") || opts.MakePlots;
snapshots = struct();
snapshots.original = coords0;

coordsPhi1_Val = [];
coordsPhi1_Ov = [];

axis2_p_Ov = [];
axis2_q_Ov = [];
axis3_p_Ov = [];
axis3_q_Ov = [];
axis4_p_Ov = [];
axis4_q_Ov = [];

for i1 = 1:nPhi
    th1 = phi(i1);

    coords1 = coords0;
    pts0 = coords0(movePhi1Rotate, :).';
    pts1 = rotatePointsRodrigues_(pts0, axis1_p0, axis1_q0, th1);
    coords1(movePhi1Rotate, :) = pts1.';

    if needSnapshots && i1 == iPhi1Val
        coordsPhi1_Val = coords1;
        snapshots.phi1_only = coords1;
    end

    if needSnapshots && i1 == iPhi1Ov
        coordsPhi1_Ov = coords1;
        axis2_p_Ov = coords1(topo.idx.CAH, :).';
        axis2_q_Ov = coords1(topo.idx.CAI, :).';
        axis3_p_Ov = coords1(topo.idx.CAI, :).';
        axis3_q_Ov = coords1(topo.idx.CAJ, :).';
        axis4_p_Ov = coords1(topo.idx.CAJ, :).';
        axis4_q_Ov = coords1(topo.idx.CAK, :).';
    end

    axis2_p = coords1(topo.idx.CAH, :).';
    axis2_q = coords1(topo.idx.CAI, :).';
    axis3_p = coords1(topo.idx.CAI, :).';
    axis3_q = coords1(topo.idx.CAJ, :).';
    axis4_p = coords1(topo.idx.CAJ, :).';
    axis4_q = coords1(topo.idx.CAK, :).';

    CBA1 = coords1(topo.idx.CBA, :).';

    CBA2 = rotatePointManyAngles_(CBA1, axis2_p, axis2_q, phi);
    dAbs.phi2(i1, :) = vecnorm(CBA2 - CAZ0, 2, 1);

    CBA3 = rotatePointManyAngles_(CBA1, axis3_p, axis3_q, phi);
    dAbs.phi3(i1, :) = vecnorm(CBA3 - CAZ0, 2, 1);

    CBA4 = rotatePointManyAngles_(CBA1, axis4_p, axis4_q, phi);
    dAbs.phi4(i1, :) = vecnorm(CBA4 - CAZ0, 2, 1);
end

[d0Value, d0Label, dx] = computeDx_(dAbs, opts.D0Definition, idx0, coords0, topo, opts.ModelID, opts.Unit);

out = struct();
out.meta = struct();
out.meta.xlsxPath = xlsxPath;
out.meta.outDir = outDir;
out.meta.modelID = opts.ModelID;
out.meta.unit = opts.Unit;
out.meta.phiGrid = phi;
out.meta.axisConvention = "Axis direction upstream->downstream; +angle follows right-hand rule.";
out.meta.d0Definition = opts.D0Definition;
out.meta.d0Label = d0Label;
out.meta.d0Value = d0Value;
out.meta.pathAtomNames = pathNames;
out.meta.topology = topo;

out.results = struct();
out.results.dAbs = dAbs;
out.results.dx = dx;

out.snapshots = struct();
out.snapshots.original = snapshots.original;

if needSnapshots && ~isempty(coordsPhi1_Val)
    out.snapshots.phi1_only = coordsPhi1_Val;
end

if needSnapshots && ~isempty(coordsPhi1_Ov)
    overlayCoords = buildOverlaySet_(coords0, coordsPhi1_Ov, opts.OverlayK, opts.OverlayPhiK, axis2_p_Ov, axis2_q_Ov, axis3_p_Ov, axis3_q_Ov, axis4_p_Ov, axis4_q_Ov, topo);

    out.snapshots.overlay = struct();
    out.snapshots.overlay.phi1 = phi(iPhi1Ov);
    out.snapshots.overlay.k = opts.OverlayK;
    out.snapshots.overlay.phiK = opts.OverlayPhiK;
    out.snapshots.overlay.coords = overlayCoords;

    out.validation = struct();
    out.validation.dihedral = computeOverlayDihedrals_(overlayCoords, topo);
end

figs = gobjects(0, 1);
if opts.MakePlots
    figs(end+1, 1) = plotHeatmap_(phi, dx.phi2, 2, d0Label, opts.ModelID, opts.Unit, opts.FigureVisible);
    figs(end+1, 1) = plotHeatmap_(phi, dx.phi3, 3, d0Label, opts.ModelID, opts.Unit, opts.FigureVisible);
    figs(end+1, 1) = plotHeatmap_(phi, dx.phi4, 4, d0Label, opts.ModelID, opts.Unit, opts.FigureVisible);

    figs(end+1, 1) = plotValidationCurves_(phi, dx, iPhi1Val, opts.ModelID, d0Label, opts.Unit, opts.FigureVisible);

    if isfield(out.snapshots, "overlay")
        figs(end+1, 1) = plotOverlay3D_(out.snapshots.overlay.coords, topo, opts.ModelID, opts.FigureVisible);
    end

    out.figures = figs;

    if opts.SaveFigures
        saveFigures_(figs, outDir, opts.FigureFormat);
    end
end

matPath = fullfile(outDir, sprintf("%s_torsion_dx_results.mat", opts.ModelID));
save(matPath, "out", "-v7.3");

if opts.ExportTXT
    txtPath = opts.TXTPath;
    if strlength(txtPath) == 0
        txtPath = fullfile(outDir, sprintf("%s_snapshots.txt", opts.ModelID));
    end
    exportSnapshotsTXT_(txtPath, out);
end

end

function T = readTableWithOptionalRange_(xlsxPath, sheet, rangeStr)
if strlength(rangeStr) == 0
    T = readtable(xlsxPath, "Sheet", sheet);
    return;
end
T = readtable(xlsxPath, "Sheet", sheet, "Range", rangeStr);
end

function vName = resolveVarName_(T, requested)
vars = string(T.Properties.VariableNames);
m = strcmpi(vars, requested);
if any(m)
    vName = T.Properties.VariableNames{find(m, 1, "first")};
    return;
end
error("Column '%s' not found. Available columns: %s", requested, strjoin(vars, ", "));
end

function topo = buildTopology_(pathNames)
idx = struct();
for i = 1:numel(pathNames)
    idx.(pathNames(i)) = i;
end

topo = struct();
topo.idx = idx;

topo.axis.phi1 = [idx.CAG idx.CAH];
topo.axis.phi2 = [idx.CAH idx.CAI];
topo.axis.phi3 = [idx.CAI idx.CAJ];
topo.axis.phi4 = [idx.CAJ idx.CAK];

topo.movingIdx = struct();
topo.movingIdx.phi1 = (idx.CAH:idx.CBA).';
topo.movingIdx.phi2 = (idx.CAI:idx.CBA).';
topo.movingIdx.phi3 = (idx.CAJ:idx.CBA).';
topo.movingIdx.phi4 = (idx.CAK:idx.CBA).';
end

function ptsRot = rotatePointsRodrigues_(pts, axisP, axisQ, angleDeg)
u = axisQ - axisP;
u = u ./ norm(u);
u = u(:);

th = deg2rad(angleDeg);
c = cos(th);
s = sin(th);

v = pts - axisP;
v = double(v);

uxv = [u(2) .* v(3,:) - u(3) .* v(2,:);
       u(3) .* v(1,:) - u(1) .* v(3,:);
       u(1) .* v(2,:) - u(2) .* v(1,:)];

udv = u.' * v;

vRot = v .* c;
vRot = vRot + uxv .* s;
vRot = vRot + u .* (udv .* (1 - c));

ptsRot = axisP + vRot;
end


function ptsRot = rotatePointManyAngles_(pt, axisP, axisQ, angleDegVec)
u = axisQ - axisP;
u = u ./ norm(u);

th = deg2rad(angleDegVec(:).');
c = cos(th);
s = sin(th);

v = pt - axisP;
v = v(:);

uxv = cross(u, v);
udv = dot(u, v);

term1 = v .* c;
term2 = uxv .* s;
term3 = u .* (udv .* (1 - c));

ptsRot = axisP + term1 + term2 + term3;
end

function [d0, d0Label, dx] = computeDx_(dAbs, d0Def, idx0, coords0, topo, modelID, unitStr)
dx = struct();

switch d0Def
    case "original"
        d0 = norm(coords0(topo.idx.CAZ, :) - coords0(topo.idx.CBA, :));
        d0Label = sprintf("d0=|CAZ-CBA| in original %s (%.6g %s)", modelID, d0, unitStr);
        dx.phi2 = dAbs.phi2 - d0;
        dx.phi3 = dAbs.phi3 - d0;
        dx.phi4 = dAbs.phi4 - d0;

    case "zerozero"
        d0 = dAbs.phi2(idx0, idx0);
        d0Label = sprintf("d0=dAbs(phi1=0,phiK=0) from (phi2 grid) (%.6g %s)", d0, unitStr);
        dx.phi2 = dAbs.phi2 - d0;
        dx.phi3 = dAbs.phi3 - d0;
        dx.phi4 = dAbs.phi4 - d0;

    case "phi1Slice"
        d0v2 = dAbs.phi2(:, idx0);
        d0v3 = dAbs.phi3(:, idx0);
        d0v4 = dAbs.phi4(:, idx0);

        d0 = NaN;
        d0Label = "d0(phi1)=dAbs(phi1,phiK=0) slice baseline";
        dx.phi2 = dAbs.phi2 - d0v2;
        dx.phi3 = dAbs.phi3 - d0v3;
        dx.phi4 = dAbs.phi4 - d0v4;

    case "globalMean"
        d0 = mean([dAbs.phi2(:); dAbs.phi3(:); dAbs.phi4(:)], "omitnan");
        d0Label = sprintf("d0=global mean dAbs across all grids (%.6g %s)", d0, unitStr);
        dx.phi2 = dAbs.phi2 - d0;
        dx.phi3 = dAbs.phi3 - d0;
        dx.phi4 = dAbs.phi4 - d0;

    otherwise
        error("Unsupported D0Definition: %s", d0Def);
end
end

function overlaySet = buildOverlaySet_(coords0, coordsPhi1, k, phiKList, axis2_p, axis2_q, axis3_p, axis3_q, axis4_p, axis4_q, topo)
overlaySet = struct();
overlaySet.original = coords0;
overlaySet.phi1_only = coordsPhi1;

coordsBase = coordsPhi1;

switch k
    case 2
        axisP = axis2_p;
        axisQ = axis2_q;
        movingIdx = topo.movingIdx.phi2;
    case 3
        axisP = axis3_p;
        axisQ = axis3_q;
        movingIdx = topo.movingIdx.phi3;
    case 4
        axisP = axis4_p;
        axisQ = axis4_q;
        movingIdx = topo.movingIdx.phi4;
    otherwise
        error("k must be 2, 3, or 4.");
end

for j = 1:numel(phiKList)
    th = phiKList(j);

    coordsK = coordsBase;
    pts0 = coordsBase(movingIdx, :).';
    pts1 = rotatePointsRodrigues_(pts0, axisP, axisQ, th);
    coordsK(movingIdx, :) = pts1.';

    fieldName = matlab.lang.makeValidName(sprintf("phi1_plus_phi%d_%ddeg", k, round(th)));
    overlaySet.(fieldName) = coordsK;
end
end

function dih = computeOverlayDihedrals_(overlaySet, topo)
names = fieldnames(overlaySet);
dih = struct();

for i = 1:numel(names)
    X = overlaySet.(names{i});

    dih.(names{i}) = struct();
    dih.(names{i}).phi1 = dihedralDeg_(X(topo.idx.NAU, :), X(topo.idx.CAG, :), X(topo.idx.CAH, :), X(topo.idx.CAI, :));
    dih.(names{i}).phi2 = dihedralDeg_(X(topo.idx.CAG, :), X(topo.idx.CAH, :), X(topo.idx.CAI, :), X(topo.idx.CAJ, :));
    dih.(names{i}).phi3 = dihedralDeg_(X(topo.idx.CAH, :), X(topo.idx.CAI, :), X(topo.idx.CAJ, :), X(topo.idx.CAK, :));
    dih.(names{i}).phi4 = dihedralDeg_(X(topo.idx.CAI, :), X(topo.idx.CAJ, :), X(topo.idx.CAK, :), X(topo.idx.NAV, :));
end
end

function ang = dihedralDeg_(r1, r2, r3, r4)
b1 = (r2 - r1);
b2 = (r3 - r2);
b3 = (r4 - r3);

n1 = cross(b1, b2);
n2 = cross(b2, b3);

n1 = n1 ./ norm(n1);
n2 = n2 ./ norm(n2);

m1 = cross(n1, b2 ./ norm(b2));

x = dot(n1, n2);
y = dot(m1, n2);

ang = rad2deg(atan2(y, x));
end

function fig = plotHeatmap_(phi, dxGrid, k, d0Label, modelID, unitStr, isVisible)
if isVisible
    vis = "on";
else
    vis = "off";
end

fig = figure("Name", sprintf("%s_heatmap_phi1_phi%d", modelID, k), "Visible", vis);
ax = axes(fig);

imagesc(ax, phi, phi, dxGrid.');
axis(ax, "xy");
xlabel(ax, "\phi_1 (deg)");
ylabel(ax, sprintf("\\phi_%d (deg)", k));

mn = min(dxGrid(:), [], "omitnan");
mx = max(dxGrid(:), [], "omitnan");

if ~isfinite(mn) || ~isfinite(mx)
    mn = 0;
    mx = 0;
end

if mn == mx
    mn = mn - 1;
    mx = mx + 1;
end

caxis(ax, [mn mx]);

cb = colorbar(ax);
cb.Label.String = sprintf("dx (%s)\nmin %.4g   max %.4g", unitStr, mn, mx);

if mn < 0 && mx > 0
    ticks = [mn 0 mx];
else
    ticks = [mn (mn + mx) / 2 mx];
end

ticks = unique(ticks, "stable");
cb.Ticks = ticks;

tickLabels = strings(size(ticks));
for i = 1:numel(ticks)
    tickLabels(i) = sprintf("%.4g", ticks(i));
end
cb.TickLabels = tickLabels;

title(ax, sprintf("%s dx heatmap (\\phi_1 vs \\phi_%d)\n%s", modelID, k, d0Label), "Interpreter", "none");
end


function fig = plotValidationCurves_(phi, dx, iPhi1, modelID, d0Label, unitStr, isVisible)
if isVisible
    vis = "on";
else
    vis = "off";
end

fig = figure("Name", sprintf("%s_validation_slice", modelID), "Visible", vis);
plot(phi, dx.phi2(iPhi1, :));
hold on;
plot(phi, dx.phi3(iPhi1, :));
plot(phi, dx.phi4(iPhi1, :));
hold off;

xlabel("\phi_k (deg)");
ylabel(sprintf("dx (%s)", unitStr));
legend("\phi_2", "\phi_3", "\phi_4", "Location", "best");
title(sprintf("%s validation: fixed \\phi_1 index=%d\n%s", modelID, iPhi1, d0Label), "Interpreter", "none");
end

function fig = plotOverlay3D_(overlaySet, topo, modelID, isVisible)
if isVisible
    vis = "on";
else
    vis = "off";
end

fig = figure("Name", sprintf("%s_overlay3D", modelID), "Visible", vis);
ax = axes(fig);
hold(ax, "on");

names = fieldnames(overlaySet);
for i = 1:numel(names)
    X = overlaySet.(names{i});
    plot3(ax, X(:,1), X(:,2), X(:,3), "-");
    plot3(ax, X(topo.idx.CAZ,1), X(topo.idx.CAZ,2), X(topo.idx.CAZ,3), "o");
    plot3(ax, X(topo.idx.CBA,1), X(topo.idx.CBA,2), X(topo.idx.CBA,3), "s");
end

hold(ax, "off");
grid(ax, "on");
axis(ax, "equal");
xlabel(ax, "x");
ylabel(ax, "y");
zlabel(ax, "z");
title(ax, sprintf("%s overlay: CAZ-...-CBA path", modelID), "Interpreter", "none");
end

function saveFigures_(figs, outDir, fmt)
for i = 1:numel(figs)
    f = figs(i);
    if ~isvalid(f)
        continue;
    end

    nm = string(f.Name);
    if strlength(nm) == 0
        nm = "figure_" + i;
    end
    safe = regexprep(nm, "[^\w\-]+", "_");

    switch fmt
        case "png"
            p = fullfile(outDir, safe + ".png");
            exportgraphics(f, p);
        case "fig"
            p = fullfile(outDir, safe + ".fig");
            savefig(f, p);
        otherwise
            error("Unsupported FigureFormat: %s", fmt);
    end
end
end

function exportSnapshotsTXT_(txtPath, out)
fid = fopen(txtPath, "w");
if fid < 0
    error("Failed to open TXTPath for writing: %s", txtPath);
end

cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, "modelID\tstage\tatomName\tx\ty\tz\n");

modelID = out.meta.modelID;
atomNames = out.meta.pathAtomNames;

writeStage_(fid, modelID, "original", atomNames, out.snapshots.original);

if isfield(out.snapshots, "phi1_only")
    writeStage_(fid, modelID, "phi1_only", atomNames, out.snapshots.phi1_only);
end

if isfield(out.snapshots, "overlay")
    ov = out.snapshots.overlay.coords;
    fn = fieldnames(ov);
    for i = 1:numel(fn)
        writeStage_(fid, modelID, "phi1_plus_phiK", atomNames, ov.(fn{i}));
    end
end
end

function writeStage_(fid, modelID, stage, atomNames, coords)
for i = 1:numel(atomNames)
    fprintf(fid, "%s\t%s\t%s\t%.10g\t%.10g\t%.10g\n", modelID, stage, atomNames(i), coords(i,1), coords(i,2), coords(i,3));
end
end
