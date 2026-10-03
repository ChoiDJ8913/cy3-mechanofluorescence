function out = pixel_lambda_calib_gui(pixels, yExp, refLambda, refInten, gLSF, peakPix0, slope0, peakLam0, opts)
% pixel_lambda_calib_gui
% Interactive calibration GUI for lambda = slope*(pixel-peakPix) + peakLam
%
% Inputs
% - pixels    : 1xN pixel grid (aligned window)
% - yExp      : 1xN experimental spectrum for calibration (recommend: mean baseline-subtracted Low)
% - refLambda : reference wavelengths (nm)
% - refInten  : reference intensities
% - gLSF      : convolution kernel (LSF) in pixel domain (1D, normalized)
% - peakPix0  : initial peak pixel (recommend: nLeft+1)
% - slope0    : initial slope (nm/px)
% - peakLam0  : initial peak wavelength (nm), typically ref peak wavelength
% - opts      : struct or name-value style (see defaults)
%
% Output out struct
% - out.ok
% - out.slope
% - out.peakPix
% - out.peakLam
% - out.lambdaCal
% - out.lambdaRange (1x2)
% - out.rmse
%
% Notes
% - Solid: convolved ref, Dashed: raw ref (same color).
% - ROI is applied in wavelength domain.
% - "Scale ref" uses least-squares amplitude scaling within ROI.

arguments
    pixels (1,:) double
    yExp (1,:) double
    refLambda (:,1) double
    refInten (:,1) double
    gLSF (:,1) double
    peakPix0 (1,1) double
    slope0 (1,1) double
    peakLam0 (1,1) double
    opts.SlopeMin (1,1) double = max(0.2, 0.5*slope0)
    opts.SlopeMax (1,1) double = min(10,  1.5*slope0)
    opts.SlopeStep (1,1) double = max(0.001, slope0/1000)
    opts.PeakLamMin (1,1) double = 520
    opts.PeakLamMax (1,1) double = 620
    opts.PeakPixMin (1,1) double = 1
    opts.PeakPixMax (1,1) double = numel(pixels)
    opts.LamRangeInit (1,2) double = [555 610]
    opts.UseConvolution (1,1) logical = true
    opts.ScaleRef (1,1) logical = true
    opts.BaselineCorrect (1,1) logical = false
    opts.BaselineEndPts (1,1) double = 6
    opts.DisplayMode (1,1) string {mustBeMember(opts.DisplayMode, ["none","max","area"])} = "none"
    opts.TitleText (1,1) string = "Pixel-\lambda calibration GUI"
end

% ---- sanitize ref for interp1 (unique lambda) ----
[refLambdaU, ord] = sort(refLambda(:));
refIntenU = refInten(:);
refIntenU = refIntenU(ord);

[refLambdaU, ~, ic] = unique(refLambdaU, "stable");
if numel(refLambdaU) < numel(refLambda)
    refIntenU = accumarray(ic, refIntenU, [], @mean);
end

% ---- state ----
st.slope = slope0;
st.peakPix = peakPix0;
st.peakLam = peakLam0;
st.lamMin = opts.LamRangeInit(1);
st.lamMax = opts.LamRangeInit(2);
st.useConv = opts.UseConvolution;
st.scaleRef = opts.ScaleRef;
st.baseCorr = opts.BaselineCorrect;
st.baseEnd = opts.BaselineEndPts;
st.mode = opts.DisplayMode;

% ---- figure ----
fig = figure("Color","w", "Name", char(opts.TitleText), "NumberTitle","off", ...
    "Position", [200 120 980 640]);

ax = axes("Parent", fig, "Position", [0.08 0.18 0.62 0.76]);
hold(ax, "on");
grid(ax, "on");
box(ax, "on");

% UI panel area
x0 = 0.73;
y0 = 0.86;
dy = 0.055;
wLbl = 0.10;
wBox = 0.16;

uicontrol(fig, "Style","text", "Units","normalized", "Position",[x0 0.92 0.25 0.05], ...
    "String","Calibration controls", "FontWeight","bold", "BackgroundColor","w", "HorizontalAlignment","left");

% slope
uicontrol(fig, "Style","text", "Units","normalized", "Position",[x0 y0 wLbl 0.04], ...
    "String","slope", "BackgroundColor","w", "HorizontalAlignment","left");
hSlope = uicontrol(fig, "Style","edit", "Units","normalized", "Position",[x0+wLbl y0 wBox 0.045], ...
    "String", sprintf("%.6g", st.slope), "Callback", @(~,~)onEditSlope());
y0 = y0 - dy;

% peakLam
uicontrol(fig, "Style","text", "Units","normalized", "Position",[x0 y0 wLbl 0.04], ...
    "String","peak λ", "BackgroundColor","w", "HorizontalAlignment","left");
hPeakLam = uicontrol(fig, "Style","edit", "Units","normalized", "Position",[x0+wLbl y0 wBox 0.045], ...
    "String", sprintf("%.6g", st.peakLam), "Callback", @(~,~)onEditPeakLam());
y0 = y0 - dy;

% peakPix
uicontrol(fig, "Style","text", "Units","normalized", "Position",[x0 y0 wLbl 0.04], ...
    "String","peak px", "BackgroundColor","w", "HorizontalAlignment","left");
hPeakPix = uicontrol(fig, "Style","edit", "Units","normalized", "Position",[x0+wLbl y0 wBox 0.045], ...
    "String", sprintf("%d", round(st.peakPix)), "Callback", @(~,~)onEditPeakPix());
y0 = y0 - dy;

% lambda range
uicontrol(fig, "Style","text", "Units","normalized", "Position",[x0 y0 wLbl 0.04], ...
    "String","λ min", "BackgroundColor","w", "HorizontalAlignment","left");
hLamMin = uicontrol(fig, "Style","edit", "Units","normalized", "Position",[x0+wLbl y0 wBox 0.045], ...
    "String", sprintf("%.2f", st.lamMin), "Callback", @(~,~)onEditLamRange());
y0 = y0 - dy;

uicontrol(fig, "Style","text", "Units","normalized", "Position",[x0 y0 wLbl 0.04], ...
    "String","λ max", "BackgroundColor","w", "HorizontalAlignment","left");
hLamMax = uicontrol(fig, "Style","edit", "Units","normalized", "Position",[x0+wLbl y0 wBox 0.045], ...
    "String", sprintf("%.2f", st.lamMax), "Callback", @(~,~)onEditLamRange());
y0 = y0 - dy;

% checkboxes
hUseConv = uicontrol(fig, "Style","checkbox", "Units","normalized", "Position",[x0 y0 0.25 0.045], ...
    "String","Use convolution (conv ref)", "Value", double(st.useConv), "BackgroundColor","w", ...
    "Callback", @(~,~)onToggles());
y0 = y0 - dy;

hScaleRef = uicontrol(fig, "Style","checkbox", "Units","normalized", "Position",[x0 y0 0.25 0.045], ...
    "String","Scale ref amplitude (LS)", "Value", double(st.scaleRef), "BackgroundColor","w", ...
    "Callback", @(~,~)onToggles());
y0 = y0 - dy;

hBaseCorr = uicontrol(fig, "Style","checkbox", "Units","normalized", "Position",[x0 y0 0.25 0.045], ...
    "String","Baseline-correct (ends)", "Value", double(st.baseCorr), "BackgroundColor","w", ...
    "Callback", @(~,~)onToggles());
y0 = y0 - dy;

% display mode
uicontrol(fig, "Style","text", "Units","normalized", "Position",[x0 y0 wLbl 0.04], ...
    "String","mode", "BackgroundColor","w", "HorizontalAlignment","left");
hMode = uicontrol(fig, "Style","popupmenu", "Units","normalized", "Position",[x0+wLbl y0 wBox 0.045], ...
    "String", {"none","max","area"}, "Value", mode_to_idx(st.mode), "Callback", @(~,~)onMode());
y0 = y0 - dy;

% RMSE text
hRMSE = uicontrol(fig, "Style","text", "Units","normalized", "Position",[x0 y0 0.25 0.06], ...
    "String","RMSE: (n/a)", "BackgroundColor","w", "HorizontalAlignment","left");
y0 = y0 - dy;

% buttons
hApply = uicontrol(fig, "Style","pushbutton", "Units","normalized", "Position",[x0 0.08 0.12 0.06], ...
    "String","Use", "FontWeight","bold", "Callback", @(~,~)onUse());
hCancel = uicontrol(fig, "Style","pushbutton", "Units","normalized", "Position",[x0+0.13 0.08 0.12 0.06], ...
    "String","Cancel", "Callback", @(~,~)onCancel());

% ---- initial plot handles ----
hExp = plot(ax, nan, nan, "LineWidth", 2, "DisplayName", "Exp (cal)");
hConv = plot(ax, nan, nan, "LineWidth", 1.6, "DisplayName", "Ref conv");
hRaw = plot(ax, nan, nan, "--", "LineWidth", 1.0, "DisplayName", "Ref raw");

hRoiL = xline(ax, st.lamMin, "k:", "HandleVisibility","off");
hRoiR = xline(ax, st.lamMax, "k:", "HandleVisibility","off");

xlabel(ax, "Wavelength (\lambda, nm)");
ylabel(ax, "Intensity (displayed)");
legend(ax, "Location","best", "Interpreter","none");

% render first time
updatePlot();

% modal wait
uiwait(fig);

% return
if isvalid(fig)
    ud = getappdata(fig, "out");
    delete(fig);
else
    ud = struct();
end

out = ud;

% =================== nested callbacks ===================

function onEditSlope()
    v = str2double(get(hSlope, "String"));
    if isfinite(v)
        st.slope = min(max(v, opts.SlopeMin), opts.SlopeMax);
        set(hSlope, "String", sprintf("%.6g", st.slope));
        updatePlot();
    end
end

function onEditPeakLam()
    v = str2double(get(hPeakLam, "String"));
    if isfinite(v)
        st.peakLam = min(max(v, opts.PeakLamMin), opts.PeakLamMax);
        set(hPeakLam, "String", sprintf("%.6g", st.peakLam));
        updatePlot();
    end
end

function onEditPeakPix()
    v = str2double(get(hPeakPix, "String"));
    if isfinite(v)
        st.peakPix = min(max(round(v), opts.PeakPixMin), opts.PeakPixMax);
        set(hPeakPix, "String", sprintf("%d", st.peakPix));
        updatePlot();
    end
end

function onEditLamRange()
    v1 = str2double(get(hLamMin, "String"));
    v2 = str2double(get(hLamMax, "String"));
    if isfinite(v1) && isfinite(v2)
        if v2 < v1
            tmp = v1;
            v1 = v2;
            v2 = tmp;
        end
        st.lamMin = v1;
        st.lamMax = v2;
        set(hLamMin, "String", sprintf("%.2f", st.lamMin));
        set(hLamMax, "String", sprintf("%.2f", st.lamMax));
        updatePlot();
    end
end

function onToggles()
    st.useConv = logical(get(hUseConv, "Value"));
    st.scaleRef = logical(get(hScaleRef, "Value"));
    st.baseCorr = logical(get(hBaseCorr, "Value"));
    updatePlot();
end

function onMode()
    val = get(hMode, "Value");
    st.mode = idx_to_mode(val);
    updatePlot();
end

function onUse()
    o = buildOut(true);
    setappdata(fig, "out", o);
    uiresume(fig);
end

function onCancel()
    o = buildOut(false);
    setappdata(fig, "out", o);
    uiresume(fig);
end

% =================== core update ===================

function updatePlot()

    % --- 1) columnize inputs ---
    pix = pixels(:);  % enforce column
    lambdaCal = st.slope * (pix - st.peakPix) + st.peakLam;
    lambdaCal = lambdaCal(:);
    fprintf("slope=%.6g, peakPix=%.6g, peakLam=%.6g, anyNaN(lambdaCal)=%d\n", ...
    st.slope, st.peakPix, st.peakLam, any(isnan(lambdaCal)));
    y = yExp(:);

    rRaw = interp1(refLambdaU, refIntenU, lambdaCal, "linear", 0);
    rRaw = rRaw(:);

    rConv = rRaw;
    if st.useConv
        g = gLSF(:);
        rConv = conv(rConv, g, "same");
    end
    rConv = rConv(:);

    % --- 2) (critical) force same length ---
    n = min([numel(lambdaCal), numel(y), numel(rConv), numel(rRaw)]);
    if numel(lambdaCal) ~= n || numel(y) ~= n || numel(rConv) ~= n
        % This should not happen if inputs are consistent, but we force it for robustness.
        lambdaCal = lambdaCal(1:n);
        y        = y(1:n);
        rRaw     = rRaw(1:n);
        rConv    = rConv(1:n);
    end

    % --- 3) optional baseline correction (must preserve column) ---
    if st.baseCorr
        y     = subtract_baseline_ends(y, st.baseEnd);
        rRaw  = subtract_baseline_ends(rRaw, st.baseEnd);
        rConv = subtract_baseline_ends(rConv, st.baseEnd);

        % re-enforce column + same length (defensive)
        y = y(:); rRaw = rRaw(:); rConv = rConv(:);
        n = min([numel(lambdaCal), numel(y), numel(rConv), numel(rRaw)]);
        lambdaCal = lambdaCal(1:n);
        y        = y(1:n);
        rRaw     = rRaw(1:n);
        rConv    = rConv(1:n);
    end

    % --- 4) display mode ---
    switch st.mode
        case "none"
            % do nothing
        case "max"
            y    = norm_max(y);
            rRaw = norm_max(rRaw);
            rConv= norm_max(rConv);
        case "area"
            y    = norm_area(y);
            rRaw = norm_area(rRaw);
            rConv= norm_area(rConv);
    end

    % --- 5) ROI mask (build stepwise to avoid shape surprises) ---
    idxRoi = (lambdaCal >= st.lamMin) & (lambdaCal <= st.lamMax);
    idxRoi = idxRoi(:) & isfinite(y) & isfinite(rConv);

    if nnz(idxRoi) < 3
        idxRoi = isfinite(y) & isfinite(rConv);
    end

    % --- 6) least-squares amplitude scaling within ROI ---
    a = 1;
    if st.scaleRef
        yy = y(idxRoi);
        rr = rConv(idxRoi);
        den = dot(rr, rr);
        if den > 0
            a = dot(yy, rr) / den;
        end
    end

    rConvS = a * rConv;
    rRawS  = a * rRaw;

    d = y(idxRoi) - rConvS(idxRoi);
    rmse = sqrt(mean(d.^2, "omitnan"));

    % --- 7) update plot objects ---
    set(hExp,  "XData", lambdaCal, "YData", y,      "DisplayName", "Exp (cal)");
    set(hConv, "XData", lambdaCal, "YData", rConvS, "DisplayName", sprintf("Ref conv (a=%.3g)", a));

    col = hConv.Color;
    set(hRaw,  "XData", lambdaCal, "YData", rRawS,  "Color", col, "DisplayName", "Ref raw");

    set(hRoiL, "Value", st.lamMin);
    set(hRoiR, "Value", st.lamMax);
    set(hRMSE, "String", sprintf("RMSE (ROI): %.4g", rmse));

    lo = min(lambdaCal, [], "omitnan");
    hi = max(lambdaCal, [], "omitnan");

    % If invalid or degenerate, do not hard-set xlim (prevents crash).
    if isempty(lo) || isempty(hi) || ~isfinite(lo) || ~isfinite(hi) || lo >= hi
        % fall back to ROI window if it is valid; otherwise auto
        if isfinite(st.lamMin) && isfinite(st.lamMax) && st.lamMin < st.lamMax
            xlim(ax, [st.lamMin st.lamMax]);
        else
            xlim(ax, "auto");
        end
    else
        xlim(ax, [lo hi]);
    end
end


function o = buildOut(okFlag)
    % Force column everywhere
    pix = pixels(:);
    lambdaCal = st.slope * (pix - st.peakPix) + st.peakLam;
    lambdaCal = lambdaCal(:);

    y = yExp(:);

    rRaw = interp1(refLambdaU, refIntenU, lambdaCal, "linear", 0);
    rRaw = rRaw(:);

    rConv = rRaw;
    if st.useConv
        rConv = conv(rConv, gLSF(:), "same");
    end
    rConv = rConv(:);

    if st.baseCorr
        y     = subtract_baseline_ends(y, st.baseEnd);
        rConv = subtract_baseline_ends(rConv, st.baseEnd);
    end

    switch st.mode
        case "none"
        case "max"
            y = norm_max(y);
            rConv = norm_max(rConv);
        case "area"
            y = norm_area(y);
            rConv = norm_area(rConv);
    end

    idxRoi = (lambdaCal >= st.lamMin) & (lambdaCal <= st.lamMax);
    idxRoi = idxRoi(:) & isfinite(y) & isfinite(rConv);
    if nnz(idxRoi) < 3
        idxRoi = isfinite(y) & isfinite(rConv);
    end

    a = 1;
    if st.scaleRef
        yy = y(idxRoi);
        rr = rConv(idxRoi);
        den = dot(rr, rr);
        if den > 0
            a = dot(yy, rr) / den;
        end
    end

    rConvS = a * rConv;
    d = y(idxRoi) - rConvS(idxRoi);
    rmse = sqrt(mean(d.^2, "omitnan"));

    o.ok = okFlag;
    o.slope = st.slope;
    o.peakPix = st.peakPix;
    o.peakLam = st.peakLam;
    o.lambdaCal = lambdaCal;
    o.lambdaRange = [st.lamMin st.lamMax];
    o.rmse = rmse;
    o.displayMode = st.mode;
    o.scaleRef = st.scaleRef;
    o.useConv = st.useConv;
    o.baselineCorrect = st.baseCorr;
end


end

% ===== small utilities (local) =====

function idx = mode_to_idx(m)
if m == "none"
    idx = 1;
elseif m == "max"
    idx = 2;
else
    idx = 3;
end
end

function m = idx_to_mode(idx)
if idx == 1
    m = "none";
elseif idx == 2
    m = "max";
else
    m = "area";
end
end

function y = subtract_baseline_ends(y, nEnd)
    y = y(:);
    n = numel(y);

    if n == 0
        return
    end

    nEnd = max(1, min(nEnd, floor(n/4)));
    if nEnd == 0
        return
    end

    iL = 1:nEnd;
    iR = (n-nEnd+1):n;

    yL = median(y(iL), "omitnan");
    yR = median(y(iR), "omitnan");
    if ~isfinite(yL), yL = 0; end
    if ~isfinite(yR), yR = 0; end

    x = (1:n).';
    s = (yR - yL) / max(1, (n - 1));
    b = yL + s * (x - 1);

    y = y - b;
    y(~isfinite(y)) = NaN;
end


function y = norm_max(y)
y = y(:);
den = max(y, [], "omitnan");
if ~(isfinite(den) && den > 0)
    den = 1;
end
y = y ./ den;
end

function y = norm_area(y)
y = y(:);
den = sum(y, "omitnan");
if ~(isfinite(den) && den > 0)
    den = 1;
end
y = y ./ den;
end
