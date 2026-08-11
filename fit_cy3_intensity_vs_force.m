function out = fit_cy3_intensity_vs_force(F, I, opts)
% FIT_CY3_INTENSITY_VS_FORCE
% Two-factor fit of Cy3 intensity vs force:
%   I(F) = I0 * exp(-DeltaZ(F)/d) ./ (1 + S(F))
% where DeltaZ(F) from geometry (WLC/FJC; label at nt from surface),
% and S(F) = S0 * (1 + A * (1 - exp(-F/Fc))).^x  (phenomenological gating).
%
% Inputs:
%   F    : [n×1] force (pN)
%   I    : [n×1] intensity (arb. units)
%   opts : struct with fields (all optional)
%     .labelType      : 'ds' or 'ss' (default 'ds')
%     .ntLabel        : label position from surface in nt (default 20)
%     .temperatureC   : default 25 (kBT ~ 4.114 pN·nm at 25°C)
%     .persistence_nm : dsDNA persistence length (default 50 nm)
%     .fjc_b_nm       : ssDNA Kuhn length (default 1.5 nm)
%     .tirf_d_init_nm : initial TIRF depth guess (default 100 nm)
%     .fix_d_nm       : if provided (scalar), fixes d to this value
%     .fix_x          : if provided, fixes x to this value (shape)
%     .plotTitle      : string for figure title
%
% Output:
%   out: struct with fields:
%     .param   : fitted parameters (I0,d,S0,A,Fc,x)
%     .geom    : geometry + DeltaZ(F)
%     .modelI  : fitted curve at F
%     .parts   : decomposition (z-only, gating-only)
%     .resnorm : SSE
%     .options : opts with defaults filled
%
% Dongju-friendly: no toolboxes required (uses fminsearch).

% ---------- defaults ----------
if nargin < 3, opts = struct; end
g.labelType    = getdef(opts,'labelType','ds');        % 'ds' or 'ss'
g.ntLabel      = getdef(opts,'ntLabel',20);            % nt (or bp for ds)
g.temperatureC = getdef(opts,'temperatureC',25);       % degC
g.p_nm         = getdef(opts,'persistence_nm',50);     % dsDNA persistence (nm)
g.b_nm         = getdef(opts,'fjc_b_nm',1.5);          % ssDNA Kuhn length (nm)
g.d_init_nm    = getdef(opts,'tirf_d_init_nm',100);    % TIRF depth init (nm)
fix_d_nm       = getdef(opts,'fix_d_nm',[]);
fix_x          = getdef(opts,'fix_x',[]);
plotTitle      = getdef(opts,'plotTitle','Cy3 I–F fit (z vs gating)');

% constants
kBT = 4.114 * (273.15+g.temperatureC)/298.15;  % pN·nm

% ---------- sanitize data ----------
F = F(:); I = I(:);
mask = isfinite(F) & isfinite(I);
F = F(mask); I = I(mask);
[ F, idx ] = sort(F);
I = I(idx);

% ---------- geometry: DeltaZ(F) ----------
% label contour length to the dye from the surface (nm):
if strcmpi(g.labelType,'ds')
    Lc_nm = g.ntLabel * 0.34;  % 0.34 nm/bp
    xi = xi_wlc_marko_siggia(F, kBT, g.p_nm);  % extension fraction x/L
    z_nm = Lc_nm .* xi;
elseif strcmpi(g.labelType,'ss')
    Lc_nm = g.ntLabel * 0.59;  % 0.59 nm/nt (empirical)
    xi = xi_fjc(F, kBT, g.b_nm);  % extension fraction
    z_nm = Lc_nm .* xi;
else
    error('labelType must be ''ds'' or ''ss''.');
end
DeltaZ = z_nm - z_nm(1); % relative to the first force point

% ---------- model & parameterization ----------
% I(F) = I0 * exp(-DeltaZ/d) / (1 + S0 * (1 + A*(1-exp(-F/Fc)))^x)
% For positivity, fit in log-space: p = log([I0,d,S0,A,Fc,x])
% Optional: fix d and/or x.

% initial guesses
I0_init = I(1);
d_init  = g.d_init_nm;
% crude estimate for gating amplitude from high/low ratio (ignore z-term)
ratioHL = max(min(I)/max(I), 1e-3);
S0_init = max( (1/ratioHL - 1), 0.2 );
A_init  = 1.0;
Fc_init = max(median(F), 5);
x_init  = 1.0;

% pack/unpack helpers
function p = pack(I0,d,S0,A,Fc,x)
    p = log([I0,d,S0,A,Fc, max(x,1e-3)]);
end
function [I0,d,S0,A,Fc,x] = unpack(p)
    v = exp(p);
    I0 = v(1); d=v(2); S0=v(3); A=v(4); Fc=v(5); x=v(6);
end

% apply fixes by tying parameters
p0 = pack(I0_init, d_init, S0_init, A_init, Fc_init, x_init);
fix = struct('d',~isempty(fix_d_nm),'x',~isempty(fix_x));
pIdxFree = true(1,6);
if fix.d, p0(2) = log(fix_d_nm); pIdxFree(2)=false; end
if fix.x, p0(6) = log(fix_x);    pIdxFree(6)=false; end
pFree0 = p0(pIdxFree);

% objective
function sse = obj(pFree)
    pAll        = p0;
    pAll(pIdxFree) = pFree;
    [I0,d,S0,A,Fc,x] = unpack(pAll);
    S  = S0 .* (1 + A .* (1 - exp(-F./Fc))).^x;
    Iz = I0 .* exp(-DeltaZ./d);
    Im = Iz ./ (1 + S);
    % robust weighting: down-weight extremes a bit
    w  = 1./max(1e-6, (0.1 + (I.^2)/median(I.^2)));
    r  = (Im - I);
    sse= sum(w(:).*r(:).^2);
end

% optimize (Nelder–Mead)
optsFM = optimset('Display','off','MaxFunEvals',2e4,'MaxIter',2e4,'TolX',1e-8,'TolFun',1e-8);
[pFreeBest, fBest] = fminsearch(@obj, pFree0, optsFM);
pBest = p0; pBest(pIdxFree)=pFreeBest;
[I0,d,S0,A,Fc,x] = unpack(pBest);

% curves
S       = S0 .* (1 + A .* (1 - exp(-F./Fc))).^x;
Iz_only = I0 .* exp(-DeltaZ./d);
Ig_only = I0 ./ (1 + S);
Imodel  = Iz_only ./ (1 + S);

% ---------- figure ----------
figure('Color','w'); hold on;
plot(F, I, 'o','MarkerSize',6,'LineWidth',1.2,'DisplayName','data');
plot(F, Imodel, '-','LineWidth',2.2,'DisplayName','fit: full');
plot(F, Iz_only * (I(1)/Iz_only(1)), '--','LineWidth',1.5,'DisplayName','z-term only (scaled)');
plot(F, Ig_only * (I(1)/Ig_only(1)), ':','LineWidth',1.8,'DisplayName','gating only (scaled)');
xlabel('Force F (pN)'); ylabel('Intensity (a.u.)');
title(plotTitle,'Interpreter','none');
legend('Location','best'); grid on; box on;
set(gca,'LineWidth',1.0,'FontSize',11);

% annotate contributions at max force
[~,kmax]=max(F);
drop_full = 100*(1 - Imodel(kmax)/Imodel(1));
drop_z    = 100*(1 - (Iz_only(kmax)/Iz_only(1)));
drop_g    = 100*(1 - (Ig_only(kmax)/Ig_only(1)));
text(mean(F), min(I)+(max(I)-min(I))*0.1, ...
    sprintf('drop at max F: full=%.1f%% | z=%.1f%% | gating=%.1f%%', ...
    drop_full, drop_z, drop_g), 'FontSize',10);

% ---------- outputs ----------
out.param = struct('I0',I0,'d_nm',d,'S0',S0,'A',A,'Fc_pN',Fc,'x',x);
out.geom  = struct('labelType',g.labelType,'ntLabel',g.ntLabel, ...
                   'Lc_nm',Lc_nm,'DeltaZ_nm',DeltaZ,'p_nm',g.p_nm,'b_nm',g.b_nm);
out.modelI = Imodel;
out.parts  = struct('Iz_only',Iz_only,'Ig_only',Ig_only);
out.resnorm = fBest;
g.tirf_d_init_nm = g.d_init_nm;
out.options = g;

% --------- local helpers ----------
function val = getdef(s, field, defaultVal)
    if isfield(s,field) && ~isempty(s.(field)), val = s.(field); else, val = defaultVal; end
end

end % main

% ================= helper functions =================

function xi = xi_wlc_marko_siggia(F, kBT, p_nm)
% extension fraction x/L for dsDNA (WLC; Marko-Siggia)
% F = (kBT/p) * [ 1/(4(1-xi)^2) - 1/4 + xi ]
xi = zeros(size(F));
for i=1:numel(F)
    Fi = max(F(i), 1e-6);
    % bracket on xi in (0,0.999999)
    f = @(x) (kBT/p_nm) * ( 1./(4*(1-x).^2) - 0.25 + x ) - Fi;
    % initial guess: high-force asymptotic
    xi0 = max(0, min(0.999, 1 - 0.5*sqrt(kBT/(Fi*p_nm))));
    % ensure bracketing
    a = 0; b = 0.999999;
    if f(a)*f(b)>0
        xi(i) = xi0; % fallback
    else
        xi(i) = fzero(f, [a b]);
    end
end
end

function xi = xi_fjc(F, kBT, b_nm)
% extension fraction x/L for ssDNA (FJC)
% xi = coth(alpha) - 1/alpha, alpha = F*b/kBT
alpha = (F .* b_nm) ./ kBT;
xi = coth_safe(alpha) - 1./max(alpha,1e-9);
end

function y = coth_safe(x)
y = cosh(x) ./ max(sinh(x), 1e-12);
end
