function out = icy3_anchor_check(dnaPDB, dyePDB, dnaAnchorA, dnaAnchorB, ...
    dyeAnchorA, dyeAnchorB, torsionPair, rotateIdx, opts_or_dxTarget, dihedralRefs_legacy)
% icy3_anchor_check - after aligning the iCy3 anchors, sweep the torsion and
%   evaluate and plot dx(theta), N-N, anchor distance + (optional) clash, linker strain, small relaxation
%
% basic usage and the existing options are unchanged from the previous version.
% === new options ===
% opts.clash.enable=true;   % score and mark steric clashes from vdW overlap
% opts.clash.shell=12;      % [A] shell near the DNA (radius around anchors A/B)
% opts.clash.severeOverlap=0.4; % [A] severe-overlap criterion (sumR - dist > this)
% opts.linkerIdx=[];        % when linker atom indices are given, compute the RMSD against theta0
% opts.relax.enable=false;  % grid search over a small translation (in the plane perpendicular to the axis)
% opts.relax.maxTrans=0.3;  % [A] maximum displacement
% opts.relax.grid=3;        % grid points per axis (e.g. 3 -> -t, 0, +t)
% opts.weights.clash=1.0;   % weight in the relaxation objective
% opts.weights.linker=0.2;

% -------------------- parse the options --------------------
if nargin < 9 || isempty(opts_or_dxTarget)
    opts = struct();
elseif isstruct(opts_or_dxTarget)
    opts = opts_or_dxTarget;
else
    opts = struct('dxTarget_A', opts_or_dxTarget);
end
if nargin >= 10 && ~isempty(dihedralRefs_legacy)
    opts.dihedralRefs = dihedralRefs_legacy;
end

% default options
if ~isfield(opts,'fitMode'),      opts.fitMode      = 'twoPoint'; end
if ~isfield(opts,'dxTarget_A'),   opts.dxTarget_A   = [];         end
if ~isfield(opts,'dihedralRefs'), opts.dihedralRefs = [];         end
if ~isfield(opts,'thetaStep'),    opts.thetaStep    = 10;         end
if ~isfield(opts,'thetaRange'),   opts.thetaRange   = [-180 180]; end
if ~isfield(opts,'clash'),        opts.clash = struct();          end
if ~isfield(opts.clash,'enable'), opts.clash.enable = true;       end
if ~isfield(opts.clash,'shell'),  opts.clash.shell  = 8;         end
if ~isfield(opts.clash,'severeOverlap'), opts.clash.severeOverlap = 0.6; end
if ~isfield(opts,'linkerIdx'),    opts.linkerIdx    = [];         end
if ~isfield(opts,'relax'),        opts.relax = struct();          end
if ~isfield(opts.relax,'enable'), opts.relax.enable = false;      end
if ~isfield(opts.relax,'maxTrans'),opts.relax.maxTrans = 0.3;     end
if ~isfield(opts.relax,'grid'),   opts.relax.grid   = 3;          end
if ~isfield(opts,'weights'),      opts.weights = struct();        end
if ~isfield(opts.weights,'clash'), opts.weights.clash = 1.0;      end
if ~isfield(opts.weights,'linker'),opts.weights.linker=0.2;       end
if ~isfield(opts,'clashCutoff'),   opts.clashCutoff = 2.2; end  % A, warning threshold between heavy atoms
if ~isfield(opts,'wSteric'),       opts.wSteric     = 1.0; end
if ~isfield(opts,'wLink'),         opts.wLink       = 0.2; end
if ~isfield(opts,'relaxEpsDeg'),   opts.relaxEpsDeg = 2.0; end  % small internal relaxation (deg)

theta = opts.thetaRange(1):opts.thetaStep:opts.thetaRange(2);
phi   = nan(numel(theta),1);  phi0 = nan;


% -------------------- load the PDB --------------------
D_dna = pdbread(dnaPDB);
D_dye = pdbread(dyePDB);
Adna  = getAtomsStruct(D_dna);   % pick ATOM/HETATM automatically
Adye  = getAtomsStruct(D_dye);

Rdna  = [[Adna.X].' [Adna.Y].' [Adna.Z].'];
Rdye  = [[Adye.X].' [Adye.Y].' [Adye.Z].'];

nDye  = size(Rdye,1);
assert(all(ismember([dyeAnchorA,dyeAnchorB,torsionPair,rotateIdx],1:nDye)), ...
    'dye atom index out of range.');

% DNA anchor coordinates
idxA = pickAtom(D_dna, dnaAnchorA{:});
idxB = pickAtom(D_dna, dnaAnchorB{:});
A = Rdna(idxA,:);  B = Rdna(idxB,:);

% dye anchor coordinates
a = Rdye(dyeAnchorA,:);  b = Rdye(dyeAnchorB,:);

% -------------------- isotropic scaling + rigid fit (two points) --------------------
[R, s, t] = align_two_points_exact(a, b, A, B);
R0 = (s*(R*Rdye.') + t).';   a0 = (s*(R*a.') + t).';  b0 = (s*(R*b.') + t).';

% force axis (DNA A->B)
u = (B - A);  u = u / norm(u);

% build the rotation set for each mode
if strcmpi(opts.fitMode,'onepoint')
    rotateIdx_eff = setdiff(rotateIdx, unique([dyeAnchorA, torsionPair]));   % B is included
else % 'twoPoint'
    rotateIdx_eff = setdiff(rotateIdx, unique([dyeAnchorA, dyeAnchorB, torsionPair]));
end

% the two nitrogens (reference value)
iN = find(strcmpi({Adye.element},'N'));  if numel(iN)>=2, iN1=iN(1); iN2=iN(2); else, iN1=1; iN2=2; end

% axis coordinates (in the aligned frame)
p  = (s*(R*Rdye(torsionPair(1),:).') + t).';
q  = (s*(R*Rdye(torsionPair(2),:).') + t).';
ax = (q - p);  ax = ax / norm(ax);

% baseline(θ0)
d0      = (b0 - a0);   % for twoPoint
P_base  = R0;          % onePoint baseline (pinned at A)
dT0     = A - P_base(dyeAnchorA,:);
P_base  = P_base + dT0;
b0_free = P_base(dyeAnchorB,:);

% phi0 of the reference PDB
if ~isempty(opts.dihedralRefs)
    A4=opts.dihedralRefs(1); B4=opts.dihedralRefs(2); C4=opts.dihedralRefs(3); D4=opts.dihedralRefs(4);
    phi0 = dihedral_deg(R0(A4,:), R0(B4,:), R0(C4,:), R0(D4,:));
end

% prepare the clash calculation: subset near the DNA and vdW radii
if opts.clash.enable
    nearMask = (vecnorm(Rdna - A,2,2) < opts.clash.shell) | (vecnorm(Rdna - B,2,2) < opts.clash.shell);
    dnaNearIdx = find(nearMask);
    R_dnaNear  = Rdna(dnaNearIdx,:);
    el_dnaNear = lower(string({Adna(dnaNearIdx).element}));
    el_dye     = lower(string({Adye.element}));
    rvdw_dna   = arrayfun(@vdw_radius, el_dnaNear);
    rvdw_dye   = arrayfun(@vdw_radius, el_dye);
    
else
    dnaNearIdx=[]; R_dnaNear=[]; el_dnaNear=[]; rvdw_dna=[]; el_dye=[]; rvdw_dye=[];
end

% -------------------- scan loop --------------------
NN  = zeros(numel(theta),1);
AD  = zeros(numel(theta),1);
DX  = zeros(numel(theta),1);
minDist   = nan(numel(theta),1);
maxOverlap= nan(numel(theta),1);
nSevere    = zeros(numel(theta),1);
sevMask    = false(numel(theta),1);
linkerRMSD = nan(numel(theta),1);

% orthonormal basis perpendicular to the axis (for the relaxation)
if opts.relax.enable
    Uperp = null(ax.');          % 3x2
    if size(Uperp,2)<2, Uperp=[Uperp, orth(randn(3,1))]; end
    U1 = Uperp(:,1).'; U2 = Uperp(:,2).';
    ts = linspace(-opts.relax.maxTrans, opts.relax.maxTrans, opts.relax.grid);
end

for k = 1:numel(theta)
    th  = deg2rad(theta(k));
    Rax = rodrigues_rot(ax, th);
    P   = R0;

    % rotate the internal atoms only
    X = P(rotateIdx_eff,:) - p;
    P(rotateIdx_eff,:) = (Rax*X.').' + p;

    % --- onePoint/twoPoint: pin at A / hold fixed ---
    switch lower(opts.fitMode)
        case 'twopoint'
            a1 = P(dyeAnchorA,:);  b1 = P(dyeAnchorB,:);
            AD(k) = norm(a1 - b1);
            DX(k) = dot( (b1 - a1) - d0, u );
        case 'onepoint'
            dT = A - P(dyeAnchorA,:);  P = P + dT;
            a1 = P(dyeAnchorA,:);     b1 = P(dyeAnchorB,:);
            AD(k) = norm(a1 - b1);
            % --- (optional) small relaxation: shift the rotateIdx block within the plane perpendicular to the axis ---
            if opts.relax.enable
                bestP = P; bestCost = inf;
                for i = 1:numel(ts)
                    for j = 1:numel(ts)
                        dShift = ts(i)*U1 + ts(j)*U2;   % 1x3
                        Pc = P; Pc(rotateIdx_eff,:) = Pc(rotateIdx_eff,:) + dShift;
                        [cCost, ~, ~] = local_clash_cost(Pc, R_dnaNear, rvdw_dye, rvdw_dna, ...
                                                         el_dye, el_dnaNear, opts, b0_free, u, dyeAnchorB, ...
                                                         P_base, opts.linkerIdx);
                        if cCost < bestCost
                            bestCost = cCost; bestP = Pc;
                        end
                    end
                end
                P = bestP;  % apply the relaxation
                b1 = P(dyeAnchorB,:);
            end
            DX(k) = dot( (b1 - b0_free), u );
        otherwise
            error('opts.fitMode must be ''twoPoint'' or ''onePoint''.');
    end

    % reference metrics
    N1 = P(iN1,:); N2 = P(iN2,:);  NN(k) = norm(N1 - N2);

    if ~isempty(opts.dihedralRefs)
        phi(k) = dihedral_deg(P(A4,:), P(B4,:), P(C4,:), P(D4,:));
    end

    % --- clash and linker strain ---
    if opts.clash.enable
        [mD, mO, nS] = clash_metrics(P, R_dnaNear, rvdw_dye, rvdw_dna, el_dye, el_dnaNear, opts.clash.severeOverlap);
        minDist(k)    = mD;
        maxOverlap(k) = mO;
        nSevere(k)    = nS;
        sevMask(k)    = nS>0;
    end
    if ~isempty(opts.linkerIdx)
        if strcmpi(opts.fitMode,'onepoint'), Pref = P_base; else, Pref = R0; end
        L0 = Pref(opts.linkerIdx,:); L1 = P(opts.linkerIdx,:);
        linkerRMSD(k) = rmsd_points(L0, L1);
    end
end

% -------------------- plots --------------------
figure('Color','w');
tiledlayout(1,3,'Padding','compact','TileSpacing','compact');

% 1) N–N
nexttile; 
plot(theta, NN,'o-','LineWidth',1.2); grid on;
xlabel('\theta (deg)'); ylabel('N–N (Å)');
title(sprintf('N–N vs. torsion  [%s]', opts.fitMode));

% 2) anchor to anchor
nexttile; 
plot(theta, AD,'o-','LineWidth',1.2); grid on;
xlabel('\theta (deg)'); ylabel('anchor–anchor (Å)');
title('Dye anchor distance');

% 3) dx(theta) with clash marks
nexttile; 
hold on; grid on;
hDX = plot(theta, DX,'o-','LineWidth',1.2,'DisplayName','\Delta x(\theta)');
yline(0,'k:','Baseline = \theta_0','LabelVerticalAlignment','bottom');
if ~isempty(opts.dxTarget_A)
    yline(opts.dxTarget_A,'r--',sprintf('\\Delta x_{exp} = %.2f \\AA',opts.dxTarget_A));
    try
        try
            f = DX - opts.dxTarget_A;
            sgn = sign(f);
            j = find(sgn(1:end-1).*sgn(2:end) <= 0, 1, 'first');  % first crossing
            if ~isempty(j) && f(j)~=f(j+1)
                th_hit = interp1(f(j:j+1), theta(j:j+1), 0, 'linear');
                xline(th_hit,'r:','\theta_{hit}','LabelOrientation','horizontal');
            end
        end
        xline(th_hit,'r:','\theta_{hit}','LabelOrientation','horizontal');
    catch, end
end
% mark the clashing steps
if opts.clash.enable
    plot(theta(sevMask), DX(sevMask), 'ro', 'MarkerFaceColor','r', 'MarkerSize',4, ...
        'DisplayName','clash(severe)');
end
% mark theta0 + phi_ref
[~,i0] = min(abs(theta - 0));
plot(theta(i0), DX(i0), 'ko', 'MarkerFaceColor','k', 'MarkerSize',5, 'DisplayName','\theta_0');
if ~isnan(phi0)
    tag='twisted'; if abs(abs(phi0)-180)<30, tag='trans-like'; elseif abs(phi0)<30, tag='cis-like'; end
    text(theta(i0)+3, DX(i0)+0.08, sprintf('\\phi_{ref}=%.1f^\\circ (%s)',phi0,tag), ...
        'FontSize',9,'Color',[0 0 0]);
end
xlabel('\theta (deg)  —  rotation around selected bond');
ylabel('\Delta x along force (\xC5)');
title(sprintf('\\Delta x(\\theta) on force axis  [%s]', opts.fitMode));
lg = legend({'\Delta x(\theta)','clash(severe)','\theta_0'}, 'Location','best'); set(lg,'AutoUpdate','on'); hold off;

% -------------------- results --------------------
clash = struct('minDist',minDist,'maxOverlap',maxOverlap,'nSevere',nSevere,'severeMask',sevMask);
out = struct('theta',theta,'deltaX_A',DX,'anchorDist',AD,'NN',NN, ...
             'phi',phi,'phi0',phi0, ...
             'A',A,'B',B,'a0',a0,'b0',b0,'scale',s,'R',R,'t',t, ...
             'fitMode',opts.fitMode,'dxTarget_A',opts.dxTarget_A, ...
             'clash',clash,'linkerRMSD',linkerRMSD);
end

% ================= utility functions =================
function idx = pickAtom(S, chain, resi, name)
A = getAtomsStruct(S);
chainID = string({A.chainID});
resSeq  = [A.resSeq];
names   = lower(strtrim(string({A.AtomName})));
want    = lower(strtrim(string(name)));
alts    = unique([want, strrep(want,"*","'"), strrep(want,"'","*")]); % O3'/O3*
mask = (chainID==string(chain)) & (resSeq==resi) & ismember(names, alts);
idx  = find(mask,1);
if isempty(idx)
    error('Atom not found: chain=%s  resi=%d  name~=%s  (tried %s)', ...
          chain, resi, name, strjoin(alts,", "));
end
end

function [R,s,t] = align_two_points_exact(a,b,A,B)
va = (b - a);    vA = (B - A);
na = va / norm(va);  nA = vA / norm(vA);
k  = cross(na,nA); sk = norm(k);
if sk < 1e-14
    if dot(na,nA) > 0
        R = eye(3);
    else
        axis = null(na.').'; if isempty(axis), axis = [1 0 0]; else, axis = axis(1,:); end
        axis = axis/norm(axis);
        K = [0 -axis(3) axis(2); axis(3) 0 -axis(1); -axis(2) axis(1) 0];
        R = eye(3) + 2*(K*K);
    end
else
    k = k/sk; ang = atan2(sk, dot(na,nA));
    K = [0 -k(3) k(2); k(3) 0 -k(1); -k(2) k(1) 0];
    R = eye(3) + sin(ang)*K + (1-cos(ang))*(K*K);
end
s = norm(vA)/norm(va);
t = A.' - s*R*a.';
a_fit = (s*(R*a.')+t).';  b_fit = (s*(R*b.')+t).';
if max(norm(a_fit-A), norm(b_fit-B)) > 1e-6
    warning('Anchor misfit after alignment exceeds tolerance.');
end
end

function R = rodrigues_rot(axis, ang)
ax = axis(:)/norm(axis);
K = [0 -ax(3) ax(2); ax(3) 0 -ax(1); -ax(2) ax(1) 0];
R = eye(3) + sin(ang)*K + (1-cos(ang))*(K*K);
end

function A = getAtomsStruct(S)
M = S.Model; if numel(M)>1, M = M(1); end
if isfield(M,'Atom') && ~isempty(M.Atom)
    A = M.Atom;
elseif isfield(M,'HeterogenAtom') && ~isempty(M.HeterogenAtom)
    A = M.HeterogenAtom;
else
    error('No Atom/HeterogenAtom found in this PDB.');
end
end

function ang = dihedral_deg(rA,rB,rC,rD)
b1 = rB - rA;  b2 = rC - rB;  b3 = rD - rC;
n1 = cross(b1,b2);  n2 = cross(b2,b3);
ang = atan2d( norm(b2)*dot(b1,n2), dot(n1,n2) );
end

function r = vdw_radius(el)
% simple vdW radii (A). Elements not listed fall back to C (1.70).
switch char(el)
    case 'c', r = 1.70;
    case 'n', r = 1.55;
    case 'o', r = 1.52;
    case 'p', r = 1.80;
    case 's', r = 1.80;
    case 'h', r = 1.20;
    case 'f', r = 1.47;
    case 'cl', r = 1.75;
    case 'br', r = 1.85;
    case 'i', r = 1.98;
    otherwise, r = 1.70;
end
end

function [minD, maxO, nSev] = clash_metrics(P_dye, R_dna, rvdw_dye, rvdw_dna, el_dye, el_dna, sevThr)
% dye vs DNA neighbourhood: minimum distance, maximum overlap (sumR - dist), count of severe overlaps

% === strip hydrogens: handles el_* whether it is a string or a cell ===
toCell = @(x) (isstring(x) * 0 + 1); %#ok<NASGU>  % dummy to avoid lint
if ~isempty(el_dye)
    if isstring(el_dye), el_dye = cellstr(el_dye); end
    keepDye = ~strcmpi(el_dye,'H');
    P_dye   = P_dye(keepDye,:);
    rvdw_dye= rvdw_dye(keepDye);
end
if ~isempty(el_dna)
    if isstring(el_dna), el_dna = cellstr(el_dna); end
    keepDNA = ~strcmpi(el_dna,'H');
    R_dna   = R_dna(keepDNA,:);
    rvdw_dna= rvdw_dna(keepDNA);
end

if isempty(R_dna)
    minD = NaN; maxO = 0; nSev = 0; return;
end
Nd = size(P_dye,1); Nn = size(R_dna,1);
% distance matrix (Nd x Nn)
DX = P_dye(:,1) - R_dna(:,1).';  DY = P_dye(:,2) - R_dna(:,2).';  DZ = P_dye(:,3) - R_dna(:,3).';
D  = sqrt(DX.^2 + DY.^2 + DZ.^2);
% sum of vdW radii
Rsum = rvdw_dye(:) + rvdw_dna(:).';
over = max(0, Rsum - D);
minD = min(D(:));
maxO = max(over(:));
nSev = nnz(over(:) > sevThr);
end

function val = rmsd_points(X0, X1)
% RMSD of two point sets (same count, matched order)
diffs = X0 - X1;
val = sqrt(mean(sum(diffs.^2,2)));
end

function [cost, maxO, rmsdL] = local_clash_cost(P, R_dnaNear, rvdw_dye, rvdw_dna, el_dye, el_dna, opts, b0_free, u, dyeAnchorB, P_base, linkerIdx)
% relaxation objective: clash (mean of overlap^2) + linker RMSD
if isempty(R_dnaNear)
    maxO = 0; over2mean = 0;
else
    DX = P(:,1) - R_dnaNear(:,1).'; DY = P(:,2) - R_dnaNear(:,2).'; DZ = P(:,3) - R_dnaNear(:,3).';
    D  = sqrt(DX.^2 + DY.^2 + DZ.^2);
    Rsum  = rvdw_dye(:) + rvdw_dna(:).';
    over  = max(0, Rsum - D);
    maxO  = max(over(:));
    over2mean = mean(over(:).^2);
end
if isempty(linkerIdx)
    rmsdL = 0;
else
    L0 = P_base(linkerIdx,:); L1 = P(linkerIdx,:);
    rmsdL = rmsd_points(L0, L1);
end
cost = opts.weights.clash*over2mean + opts.weights.linker*rmsdL^2;
end
