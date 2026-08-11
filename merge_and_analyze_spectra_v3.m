function merge_and_analyze_spectra_v3(options)
% MERGE_AND_ANALYZE_SPECTRA_V3 (patched, GUI-consistent)
%
% Primary fixes
% 1) lambda_cal is always defined immediately after GUI returns slope/peakPix/peakLam.
% 2) pixel_lambda_calib_gui checkbox states (baseline / conv / scale) are propagated
%    to downstream ref overlay and RMSE ranking.
% 3) Ref-sanity comparison is done in a dedicated intensity-mean workflow to avoid
%    mixing definitions between mean curve and SEM shading.
% 4) Fix: rConv -> rConv_u (typo) and allowScale missing-arg crash in compute_intensity_overlay call sites.
%
% Definitions (for manuscript defensibility)
% - "Shape summary" (mL_plot/mH_plot, SEM): per-molecule max-normalized spectra (allL_disp/allH_disp).
% - "Ref sanity" (expL_u/expH_u): mean of background-subtracted intensity spectra (meanSpecL_u/meanSpecH_u),
%   optionally ends-linear baseline corrected, and optionally amplitude-scaled vs ref within fitRange.
%
% Conventions:
% - solid = convolved ref (LSF)
% - dashed = raw ref (pre-conv), same color

arguments
    options.DataDir (1,1) string = ""
    options.RefFiles (1,:) string = string.empty(1, 0)
    options.AlignWindow (1,2) double {mustBeInteger, mustBePositive} = [15, 35]

    % Reference convolution
    options.ApplyRefConvolution (1,1) logical = true

    % PSF-based LSF (preferred)
    options.UsePSFLSF (1,1) logical = true
    options.PSFMatFile (1,1) string = ""
    options.PSFVarName (1,1) string = "PSF_extracted"
    options.PSFDispAxis (1,1) string {mustBeMember(options.PSFDispAxis, ["x","y"])} = "x"

    % Gaussian fallback if PSF is not available
    options.RefLSF_FWHM_px (1,1) double {mustBePositive} = 3.56

    % Calibration controls
    options.InitialSlope (1,1) double {mustBePositive} = 2.0
    options.CalibFitFrac (1,1) double {mustBePositive} = 0.05
    options.CalibBaselineCorrect (1,1) logical = true
    options.CalibBaseline_EndPts (1,1) double {mustBeInteger, mustBePositive} = 6
    options.CalibAllowScale (1,1) logical = false

    % Robust QC (2-pass)
    options.QC_Enable (1,1) logical = true
    options.QC_MADmult (1,1) double {mustBePositive} = 6
    options.QC_MinPeakADC (1,1) double = -Inf

    % Optional: auto-pick calibration ref by short filename
    options.CalibrationRefShortName (1,1) string = ""

    % Figures / debug toggles
    options.ShowDiagnostics (1,1) logical = true
    options.ShowPaperFigure (1,1) logical = true
    options.ShowPaperFigure_BaselineCorrected (1,1) logical = true
    options.PreNormDiag_Enable (1,1) logical = true
    options.PreNormDiag_ShowArea (1,1) logical = false

    % Ref comparison (RMSE ranking + overlay)
    options.RefCompare_Enable (1,1) logical = true
    options.RefCompare_TopK (1,1) double {mustBeInteger, mustBePositive} = 6
    options.RefCompare_ShowRawTop (1,1) logical = true
    options.SaveRefSummaryCSV (1,1) logical = true
    options.RMSEBaselineCorrect (1,1) logical = true
    % Ref comparison: per-ref figure windows (Exp vs single ref)
    options.RefCompare_PerRefFigures (1,1) logical = true
    options.RefCompare_PerRefShowRaw (1,1) logical = true

    % Ref sanity check figure (intensity-domain mean vs ref)
    options.RefSanity_Enable (1,1) logical = true
    options.RefSanity_ShowBothBaselineModes (1,1) logical = false
    options.RefSanity_XLim (1,2) double = [530, 680]

    % Main figures: optionally show the calibration ref raw curve
    options.ShowCalRefRawInMain (1,1) logical = false
end

%% 1) DataDir
if options.DataDir == ""
    dataDirCandidate = uigetdir("D:\MT\roi_selected_fig");
    if dataDirCandidate == 0
        return
    end
    options.DataDir = string(dataDirCandidate);
end
dataDir = options.DataDir;

%% 2) Reference CSVs (multi-select)
if isempty(options.RefFiles)
    [f, p] = uigetfile("D:\MT\custom_spectum\*.csv", "Select reference Cy3 CSV files", "MultiSelect", "on");
    if isequal(f, 0)
        return
    end
    if ischar(f)
        f = {f};
    end
    f = string(f);
    options.RefFiles = fullfile(string(p), f);
end

%% 3) select the PSF (single; cancel -> Gaussian fallback)
if options.UsePSFLSF
    if options.PSFMatFile == ""
        [fPsf, pPsf] = uigetfile("D:\MT\psf\*.mat", "Select PSF .mat file");
        if isequal(fPsf, 0)
            options.UsePSFLSF = false;
        else
            options.PSFMatFile = string(fullfile(pPsf, fPsf));
        end
    end
end

%% 4) Build LSF kernel
if options.UsePSFLSF && options.PSFMatFile ~= ""
    gLSF = lsf_from_psf_mat(options.PSFMatFile, options.PSFVarName, options.PSFDispAxis);
else
    gLSF = gaussian_kernel_fwhm_px(options.RefLSF_FWHM_px);
end

%% 5) list of experimental .mat files
fileList = dir(fullfile(dataDir, "*.mat"));
nFiles = length(fileList);
if nFiles == 0
    warning("No .mat files found in DataDir.");
    return
end

nLeft = options.AlignWindow(1);
nRight = options.AlignWindow(2);
targetLen = nLeft + 1 + nRight;
pixels = 1:targetLen;

%% 6) 2-pass QC: peak distribution scan (Low channel)
qcPeak = nan(nFiles, 1);
for i = 1:nFiles
    data = load(fullfile(dataDir, fileList(i).name));
    if ~isfield(data, "signalData")
        continue
    end
    if ~isfield(data.signalData, "profLow")
        continue
    end

    lp_org = data.signalData.profLow(:).';
    if isempty(lp_org)
        continue
    end

    lp_for_peak = smoothdata(lp_org, "movmean", 3, "omitnan");
    qcPeak(i) = max(lp_for_peak, [], "omitnan");
end

qcTh = Inf;
if options.QC_Enable
    qv = qcPeak(isfinite(qcPeak));
    if ~isempty(qv)
        medP = median(qv);
        madP = median(abs(qv - medP));
        if isfinite(medP) && isfinite(madP) && madP > 0
            qcTh = medP + options.QC_MADmult * madP;
        end
    end
end

%% 7) data processing (main pass)
if options.ShowDiagnostics
    allL_raw = nan(nFiles, targetLen);
    allH_raw = nan(nFiles, targetLen);
else
    allL_raw = [];
    allH_raw = [];
end

allL_disp = nan(nFiles, targetLen);
allH_disp = nan(nFiles, targetLen);

% Baseline-subtracted (valley-offset) intensity spectra for intensity-mean workflows
allL_bs = nan(nFiles, targetLen);
allH_bs = nan(nFiles, targetLen);

sumSpecL = zeros(1, targetLen);
sumSpecH = zeros(1, targetLen);
cntSpecL = zeros(1, targetLen);
cntSpecH = zeros(1, targetLen);

bgSearchLimit = max(1, nLeft - 3);
bgIndices = 1:bgSearchLimit;

validIdx = false(nFiles, 1);
droppedByQC = false(nFiles, 1);

for i = 1:nFiles
    data = load(fullfile(dataDir, fileList(i).name));
    if ~isfield(data, "signalData")
        continue
    end
    if ~isfield(data.signalData, "profLow")
        continue
    end
    if ~isfield(data.signalData, "profHigh")
        continue
    end

    lp_org = data.signalData.profLow(:).';
    hp_org = data.signalData.profHigh(:).';
    if isempty(lp_org) || isempty(hp_org)
        continue
    end

    if options.QC_Enable && isfinite(qcPeak(i))
        if qcPeak(i) > qcTh || qcPeak(i) < options.QC_MinPeakADC
            droppedByQC(i) = true;
            continue
        end
    end

    lp_for_peak = smoothdata(lp_org, "movmean", 3, "omitnan");
    [~, peakIdx] = max(lp_for_peak, [], "omitnan");

    idxStart = peakIdx - nLeft;
    idxEnd = peakIdx + nRight;

    lp_aligned = extract_window(lp_org, idxStart, idxEnd, targetLen);
    hp_aligned = extract_window(hp_org, idxStart, idxEnd, targetLen);

    if options.ShowDiagnostics
        allL_raw(i, :) = lp_aligned;
        allH_raw(i, :) = hp_aligned;
    end

    if all(isnan(lp_aligned(bgIndices)))
        bgL = 0;
    else
        tmpL = smoothdata(lp_aligned(bgIndices), "movmean", 3, "omitnan");
        bgL = min(tmpL, [], "all", "omitnan");
    end

    if all(isnan(hp_aligned(bgIndices)))
        bgH = 0;
    else
        tmpH = smoothdata(hp_aligned(bgIndices), "movmean", 3, "omitnan");
        bgH = min(tmpH, [], "all", "omitnan");
    end

    specL = lp_aligned - bgL;
    specH = hp_aligned - bgH;

    specL = max(specL, 0);
    specH = max(specH, 0);

    allL_bs(i, :) = specL;
    allH_bs(i, :) = specH;

    maskL = isfinite(specL);
    sumSpecL(maskL) = sumSpecL(maskL) + specL(maskL);
    cntSpecL(maskL) = cntSpecL(maskL) + 1;

    maskH = isfinite(specH);
    sumSpecH(maskH) = sumSpecH(maskH) + specH(maskH);
    cntSpecH(maskH) = cntSpecH(maskH) + 1;

    denomDispL = max(specL, [], "omitnan");
    denomDispH = max(specH, [], "omitnan");

    if denomDispL <= 0
        denomDispL = 1;
    end
    if denomDispH <= 0
        denomDispH = 1;
    end

    allL_disp(i, :) = specL ./ denomDispL;
    allH_disp(i, :) = specH ./ denomDispH;

    validIdx(i) = true;
end

if ~any(validIdx)
    warning("No valid spectra after loading/QC.");
    if options.QC_Enable
        fprintf("QC threshold was %.3g (MAD-mult=%.2f). All were dropped or invalid.\n", qcTh, options.QC_MADmult);
    end
    return
end

if options.QC_Enable
    nDropped = sum(droppedByQC);
    fprintf("QC: dropped %d/%d (peak threshold %.3g).\n", nDropped, nFiles, qcTh);
end

allL_disp = allL_disp(validIdx, :);
allH_disp = allH_disp(validIdx, :);
allL_bs = allL_bs(validIdx, :);
allH_bs = allH_bs(validIdx, :);

if options.ShowDiagnostics
    allL_raw = allL_raw(validIdx, :);
    allH_raw = allH_raw(validIdx, :);
end

N = size(allL_disp, 1);

%% 8) Shape summary statistics (per-molecule max-normalized)
mLow_disp = mean(allL_disp, 1, "omitnan");
mHigh_disp = mean(allH_disp, 1, "omitnan");

span = 5;
mL_plot = smoothdata(mLow_disp, "movmean", span, "omitnan");
mH_plot = smoothdata(mHigh_disp, "movmean", span, "omitnan");

mL_plot = mL_plot ./ max(mL_plot, [], "omitnan");
mH_plot = mH_plot ./ max(mH_plot, [], "omitnan");

sdL_plot = smoothdata(std(allL_disp, 0, 1, "omitnan"), "movmean", 5, "omitnan");
sdH_plot = smoothdata(std(allH_disp, 0, 1, "omitnan"), "movmean", 5, "omitnan");

semL_plot = sdL_plot ./ sqrt(N);
semH_plot = sdH_plot ./ sqrt(N);
%% 8.1) Precompute baseline-corrected shape curves (for optional plotting)
% Baseline correction is applied per-molecule in intensity domain (allL_bs/allH_bs),
% then each row is max-normalized to preserve "shape" comparability.
allL_bc = subtract_linear_baseline_by_ends_rows(allL_bs, options.CalibBaseline_EndPts);
allH_bc = subtract_linear_baseline_by_ends_rows(allH_bs, options.CalibBaseline_EndPts);

denL_bc = max(allL_bc, [], 2, "omitnan");
denH_bc = max(allH_bc, [], 2, "omitnan");
denL_bc(~isfinite(denL_bc) | denL_bc <= 0) = 1;
denH_bc(~isfinite(denH_bc) | denH_bc <= 0) = 1;

allL_disp_bc = allL_bc ./ denL_bc;
allH_disp_bc = allH_bc ./ denH_bc;

mLow_disp_bc  = mean(allL_disp_bc, 1, "omitnan");
mHigh_disp_bc = mean(allH_disp_bc, 1, "omitnan");

mL_plot_bc = smoothdata(mLow_disp_bc,  "movmean", span, "omitnan");
mH_plot_bc = smoothdata(mHigh_disp_bc, "movmean", span, "omitnan");
mL_plot_bc = mL_plot_bc ./ max(mL_plot_bc, [], "omitnan");
mH_plot_bc = mH_plot_bc ./ max(mH_plot_bc, [], "omitnan");

sdL_plot_bc  = smoothdata(std(allL_disp_bc, 0, 1, "omitnan"), "movmean", 5, "omitnan");
sdH_plot_bc  = smoothdata(std(allH_disp_bc, 0, 1, "omitnan"), "movmean", 5, "omitnan");
semL_plot_bc = sdL_plot_bc ./ sqrt(N);
semH_plot_bc = sdH_plot_bc ./ sqrt(N);

if options.ShowDiagnostics
    meanRawL = mean(allL_raw, 1, "omitnan");
    meanRawH = mean(allH_raw, 1, "omitnan");
else
    meanRawL = [];
    meanRawH = [];
end

%% 9) Load references, pick ONE calibration ref
refsAll = load_ref_list(options.RefFiles);
if isempty(refsAll)
    warning("No valid reference spectra loaded.");
    return
end

refNames = {refsAll.shortName};
refNamesChar = cellstr(string(refNames));

calIdx = [];
if options.CalibrationRefShortName ~= ""
    for k = 1:numel(refsAll)
        if refsAll(k).shortName == options.CalibrationRefShortName
            calIdx = k;
            break
        end
    end
end

if isempty(calIdx)
    % 1) If a commonly used calibration file exists, auto-pick it
    idxAuto = find(string({refsAll.shortName}) == "Cy3_exp1.csv", 1, "first");
    if ~isempty(idxAuto)
        calIdx = idxAuto;

    % 2) If only one ref is provided, auto-pick it
    elseif numel(refsAll) == 1
        calIdx = 1;

    % 3) If desktop UI is not available, avoid listdlg and pick the first
    elseif ~usejava("desktop")
        calIdx = 1;

    % 4) Otherwise ask user via list dialog
    else
        [iSel, ok] = listdlg( ...
            "ListString", refNamesChar, ...
            "SelectionMode", "single", ...
            "Name", "Select Calibration Reference", ...
            "PromptString", "Choose ONE reference CSV to fix pixel-to-wavelength calibration:" ...
            );
        if ~ok || isempty(iSel)
            return
        end
        calIdx = iSel;
    end
end


calShort = refsAll(calIdx).shortName;

%% 10) Build calibration experimental spectrum from intensity-mean (valley-offset subtracted)
meanSpecL_u = nan(1, targetLen);
meanSpecH_u = nan(1, targetLen);

maskCntL = cntSpecL > 0;
meanSpecL_u(maskCntL) = sumSpecL(maskCntL) ./ cntSpecL(maskCntL);

maskCntH = cntSpecH > 0;
meanSpecH_u(maskCntH) = sumSpecH(maskCntH) ./ cntSpecH(maskCntH);

yCalExp = smoothdata(meanSpecL_u, "movmean", 3, "omitnan");

peakPix = nLeft + 1;

if options.CalibBaselineCorrect
    yCalExp = subtract_linear_baseline_by_ends_noclip(yCalExp, options.CalibBaseline_EndPts);
end
yCalExp = normalize_vec_1d(yCalExp, "max");

fitRange = fitrange_by_threshold(yCalExp, options.CalibFitFrac, peakPix);

[optSlope, calRmse] = optimize_slope_for_ref( ...
    options.InitialSlope, ...
    pixels, ...
    peakPix, ...
    refsAll(calIdx).lambda, ...
    refsAll(calIdx).inten, ...
    yCalExp, ...
    fitRange, ...
    gLSF, ...
    options.ApplyRefConvolution, ...
    options.CalibAllowScale, ...
    options.CalibBaselineCorrect, ...
    options.CalibBaseline_EndPts ...
    );

yExpCal = smoothdata(meanSpecL_u, "movmean", 3, "omitnan");
yExpCal = yExpCal(:).';
if isempty(yExpCal)
    error("yExpCal is empty. meanSpecL_u is empty or not computed.");
end
if numel(yExpCal) ~= numel(pixels)
    error("Length mismatch: numel(yExpCal)=%d, numel(pixels)=%d.", numel(yExpCal), numel(pixels));
end
fprintf("GUI input: numel(pixels)=%d, numel(yExpCal)=%d\n", numel(pixels), numel(yExpCal));

guiOut = pixel_lambda_calib_gui( ...
    pixels, ...
    yExpCal, ...
    refsAll(calIdx).lambda, ...
    refsAll(calIdx).inten, ...
    gLSF, ...
    nLeft + 1, ...
    optSlope, ...
    refsAll(calIdx).peakLamRef ...
    );

if ~guiOut.ok
    return
end

optSlope = guiOut.slope;
peakPix = guiOut.peakPix;
peakLam = guiOut.peakLam;

lambda_cal = optSlope .* (pixels - peakPix) + peakLam;

fitLamRange = guiOut.lambdaRange;

[useGuiBaseline, useGuiConv, useGuiScale] = read_gui_flags(guiOut, options);

applyConvForRef = options.ApplyRefConvolution;
if ~useGuiConv
    applyConvForRef = false;
end

baselineForRanking = options.RMSEBaselineCorrect;
if useGuiBaseline
    baselineForRanking = true;
end

allowScaleForRanking = useGuiScale;

fprintf("lambda_cal: [%.0f .. %.0f], anyNaN=%d\n", min(lambda_cal), max(lambda_cal), any(isnan(lambda_cal)));
fprintf("Calibration ref (fixed): %s\n", char(calShort));
fprintf("Opt slope: %.6g nm/px, RMSE(cal): %.6g\n", optSlope, calRmse);

%% 10.1) Build wavelength-domain intensity-mean curves for ref workflows
expL_u = smoothdata(meanSpecL_u, "movmean", 3, "omitnan");
expH_u = smoothdata(meanSpecH_u, "movmean", 3, "omitnan");

expL_forOverlay = expL_u;
expH_forOverlay = expH_u;

if useGuiBaseline
    expL_forOverlay = subtract_linear_baseline_by_ends_noclip(expL_forOverlay, options.CalibBaseline_EndPts);
    expH_forOverlay = subtract_linear_baseline_by_ends_noclip(expH_forOverlay, options.CalibBaseline_EndPts);
end

expL_plot_use = normalize_vec_1d(expL_forOverlay, "max");
expH_plot_use = normalize_vec_1d(expH_forOverlay, "max");

%% 10.2) Build calibration ref on lambda_cal grid ONCE
[ref_cal_raw_u, ref_cal_conv_u] = ref_on_lambda_grid( ...
    refsAll(calIdx).lambda, ...
    refsAll(calIdx).inten, ...
    lambda_cal, ...
    gLSF, ...
    applyConvForRef ...
    );

ref_raw_forOverlay = ref_cal_raw_u;
ref_conv_forOverlay = ref_cal_conv_u;

if useGuiBaseline
    ref_raw_forOverlay = subtract_linear_baseline_by_ends_noclip(ref_raw_forOverlay, options.CalibBaseline_EndPts);
    ref_conv_forOverlay = subtract_linear_baseline_by_ends_noclip(ref_conv_forOverlay, options.CalibBaseline_EndPts);
end

ref_cal_raw = normalize_vec_1d(ref_raw_forOverlay, "max");
ref_cal_conv = normalize_vec_1d(ref_conv_forOverlay, "max");

%% 10.5) Pre-normalization diagnostic (optional)
if options.PreNormDiag_Enable
    nRows = 1;
    if options.PreNormDiag_ShowArea
        nRows = 2;
    end

    figs = gobjects(1, 1);
    figs(1) = figure("Color", "w", "Position", [260, 120, 900, 620], "Name", "PreNorm Diagnostic");
    tiledlayout(nRows, 1, "Padding", "compact", "TileSpacing", "compact");

    nexttile;
    hold on;
    grid on;
    box on;

    expL = expL_u;
    expH = expH_u;

    rConv_u = ref_cal_conv_u;
    rRaw_u = ref_cal_raw_u;

    if useGuiBaseline
        expL = subtract_linear_baseline_by_ends_noclip(expL, options.CalibBaseline_EndPts);
        expH = subtract_linear_baseline_by_ends_noclip(expH, options.CalibBaseline_EndPts);
        rConv_u = subtract_linear_baseline_by_ends_noclip(rConv_u, options.CalibBaseline_EndPts);
        rRaw_u = subtract_linear_baseline_by_ends_noclip(rRaw_u, options.CalibBaseline_EndPts);
    end

    fitRangeSafe = fitRange(:);
    fitRangeSafe = fitRangeSafe(isfinite(fitRangeSafe));

    nFit = min(numel(expL), numel(rConv_u));
    fitRangeSafe = fitRangeSafe(fitRangeSafe >= 1 & fitRangeSafe <= nFit);

    y = expL(fitRangeSafe);
    r = rConv_u(fitRangeSafe);

    y = y(:);
    r = r(:);

    valid = isfinite(y) & isfinite(r);
    y = y(valid);
    r = r(valid);

    a = 1;
    if useGuiScale
        rr = dot(r, r);
        if rr > 0
            a = dot(y, r) / rr;
        end
    end

    plot(lambda_cal, expL, "LineWidth", 2, "DisplayName", "Exp Low: mean(specL), no norm");
    plot(lambda_cal, expH, "LineWidth", 2, "DisplayName", "Exp High: mean(specH), no norm");
    plot(lambda_cal, a .* rConv_u, "k-", "LineWidth", 1.6, "DisplayName", sprintf("Cal Ref: conv (scaled, a=%.3g)", a));
    plot(lambda_cal, a .* rRaw_u, "k--", "LineWidth", 1.0, "DisplayName", "Cal Ref: raw (scaled)");

    xlabel("Wavelength (\lambda, nm)");
    ylabel("Intensity (a.u.)");
    title(sprintf("Intensity-mean overlay (GUI baseline=%d, GUI conv=%d, GUI scale=%d)", useGuiBaseline, useGuiConv, useGuiScale), "Interpreter", "none");
    xlim(options.RefSanity_XLim);
    legend("Location", "best", "Interpreter", "none");

    if options.PreNormDiag_ShowArea
        nexttile;
        hold on;
        grid on;
        box on;

        rowSumL = sum(allL_bs, 2, "omitnan");
        rowSumH = sum(allH_bs, 2, "omitnan");

        rowSumL(rowSumL <= 0 | ~isfinite(rowSumL)) = NaN;
        rowSumH(rowSumH <= 0 | ~isfinite(rowSumH)) = NaN;

        allL_area = allL_bs ./ rowSumL;
        allH_area = allH_bs ./ rowSumH;

        meanL_area = smoothdata(mean(allL_area, 1, "omitnan"), "movmean", 3, "omitnan");
        meanH_area = smoothdata(mean(allH_area, 1, "omitnan"), "movmean", 3, "omitnan");

        rConv_area = ref_cal_conv_u;
        rRaw_area = ref_cal_raw_u;

        denC = sum(rConv_area, "omitnan");
        if ~(isfinite(denC) && denC > 0)
            denC = 1;
        end
        denR = sum(rRaw_area, "omitnan");
        if ~(isfinite(denR) && denR > 0)
            denR = 1;
        end

        rConv_area = rConv_area ./ denC;
        rRaw_area = rRaw_area ./ denR;

        plot(lambda_cal, meanL_area, "LineWidth", 2, "DisplayName", "Exp Low: mean(area-norm)");
        plot(lambda_cal, meanH_area, "LineWidth", 2, "DisplayName", "Exp High: mean(area-norm)");
        plot(lambda_cal, rConv_area, "k-", "LineWidth", 1.6, "DisplayName", "Cal Ref: conv (area-norm)");
        plot(lambda_cal, rRaw_area, "k--", "LineWidth", 1.0, "DisplayName", "Cal Ref: raw (area-norm)");

        xlabel("Wavelength (\lambda, nm)");
        ylabel("Area-normalized intensity (sum=1)");
        title("Area-normalization diagnostic");
        xlim(options.RefSanity_XLim);
        legend("Location", "best", "Interpreter", "none");
    end
end

%% 11) Diagnostics (8-panel) [optional]
cB = [0, 0.447, 0.741];
cR = [1, 0, 0];

if options.ShowDiagnostics
    figs = gobjects(1, 1);
    figs(1) = figure("Color", "w", "Position", [50, 50, 1200, 1400], "Name", "Diagnostic View");

    tFS = 10;
    labFS = 9;
    lgdFS = 8;

    xLimP = [min(pixels), max(pixels)];
    xLimL = [min(lambda_cal), max(lambda_cal)];

    titles = [ ...
        "Raw Intensity (Aligned, Low)", "Raw Intensity (Aligned, High)", ...
        "Pixel-norm (Individual, max)", "Wavelength overlay (Exp vs Ref)", ...
        "Pixel-norm (SD, max)", "Wavelength-norm (SD, max)", ...
        "Pixel-norm (SEM, max)", "Wavelength-norm (SEM, max)" ...
        ];

    faintB = lighten_color(cB, 0.85);
    faintR = lighten_color(cR, 0.85);

    [~, valleyIdxVis] = min(mL_plot(1:nLeft));

    for p = 1:8
        ax = subplot(4, 2, p);
        hold(ax, "on");
        grid(ax, "on");
        box(ax, "on");
        axis(ax, "square");

        title(ax, titles(p), "FontSize", tFS, "FontWeight", "bold");

        if p <= 2 || p == 3 || p == 5 || p == 7
            xlabel(ax, "Aligned Pixel", "FontSize", labFS);
            xData = pixels;
            xlim(ax, xLimP);
            xline(ax, valleyIdxVis, "k:", "Alpha", 0.6, "HandleVisibility", "off");
        else
            xlabel(ax, "Wavelength (\lambda, nm)", "FontSize", labFS);
            xData = lambda_cal;
            xlim(ax, xLimL);
        end

        switch p
            case 1
                plot(pixels, allL_raw.', "Color", faintB, "HandleVisibility", "off");
                plot(pixels, meanRawL, "k-", "LineWidth", 1.5, "DisplayName", "Mean Raw");
                ylabel(ax, "Intensity (ADC or a.u.)", "FontSize", labFS);
                legend(ax, "Location", "best", "FontSize", lgdFS);

            case 2
                plot(pixels, allH_raw.', "Color", faintR, "HandleVisibility", "off");
                plot(pixels, meanRawH, "k-", "LineWidth", 1.5, "DisplayName", "Mean Raw");
                ylabel(ax, "Intensity (ADC or a.u.)", "FontSize", labFS);
                legend(ax, "Location", "best", "FontSize", lgdFS);

            case 3
                plot(pixels, allL_disp.', "Color", faintB, "HandleVisibility", "off");
                plot(pixels, mLow_disp, "k--", "LineWidth", 1.2, "DisplayName", "Mean (max-norm)");
                ylabel(ax, "Norm. Intensity", "FontSize", labFS);
                ylim(ax, [-0.05 1.1]);
                legend(ax, "Location", "best", "FontSize", lgdFS);

            case 4
                plot(lambda_cal, ref_cal_conv, "k:", "LineWidth", 1.2, "DisplayName", "Cal Ref (conv, max)");
                if options.ShowCalRefRawInMain
                    plot(lambda_cal, ref_cal_raw, "k--", "LineWidth", 1.0, "DisplayName", "Cal Ref (raw, max)");
                end
                plot(lambda_cal, expL_plot_use, "-", "Color", cB, "LineWidth", 2, "DisplayName", "Exp Low (intensity-mean, max)");
                plot(lambda_cal, expH_plot_use, "-", "Color", cR, "LineWidth", 2, "DisplayName", "Exp High (intensity-mean, max)");
                ylabel(ax, "Norm. Intensity", "FontSize", labFS);
                ylim(ax, [-0.05 1.1]);
                legend(ax, "Location", "best", "FontSize", lgdFS);

            case {5, 6, 7, 8}
                if p == 5 || p == 6
                    errL = sdL_plot;
                    errH = sdH_plot;
                else
                    errL = semL_plot;
                    errH = semH_plot;
                end

                if mod(p, 2) == 0
                    plot(lambda_cal, ref_cal_conv, "k:", "LineWidth", 1.2, "DisplayName", "Cal Ref (conv, max)");
                end

                plot_sh(xData, mL_plot, errL, cB, 0.15, "Low Force (shape)");
                plot_sh(xData, mH_plot, errH, cR, 0.15, "High Force (shape)");

                ylabel(ax, "Norm. Intensity", "FontSize", labFS);
                ylim(ax, [-0.05 1.1]);
                legend(ax, "Location", "best", "FontSize", lgdFS);
        end

        set(ax, "FontSize", 9, "TickDir", "out");
    end
end

%% 12) Paper figure (SEM, shape-based) [optional]
if options.ShowPaperFigure
    figs = gobjects(1, 1);
    figs(1) = figure("Color", "w", "Position", [700, 100, 600, 550], "Name", "Final Paper Figure (shape-based)");
    ax_paper = gca;
    hold(ax_paper, "on");
    grid(ax_paper, "on");
    box(ax_paper, "on");
    axis(ax_paper, "square");

    paperFS = 12;
    paperLW = 1.5;
    paperShadeAlpha = 0.2;

    plot(lambda_cal, ref_cal_conv, "k:", "LineWidth", paperLW, "DisplayName", "Cal Ref (conv, max)");
    if options.ShowCalRefRawInMain
        plot(lambda_cal, ref_cal_raw, "k--", "LineWidth", paperLW, "DisplayName", "Cal Ref (raw, max)");
    end

    plot_sh_paper(lambda_cal, mL_plot, semL_plot, cB, paperShadeAlpha, "Low Force (SEM, shape)", paperLW);
    plot_sh_paper(lambda_cal, mH_plot, semH_plot, cR, paperShadeAlpha, "High Force (SEM, shape)", paperLW);

    xlabel("Wavelength (\lambda, nm)", "FontSize", paperFS, "FontWeight", "bold");
    ylabel("Normalized Intensity", "FontSize", paperFS, "FontWeight", "bold");
    xlim(ax_paper, options.RefSanity_XLim);
    ylim(ax_paper, [-0.15 1.1]);

    legend(ax_paper, "Location", "best", "FontSize", paperFS - 2, "EdgeColor", "none");
    set(ax_paper, "FontSize", paperFS - 1, "LineWidth", 1.2, "TickDir", "out");
    title(ax_paper, sprintf("Calibration ref fixed: %s", char(calShort)), "Interpreter", "none");
end

%% 12.1) Paper figure (baseline-corrected shape) [optional, added]
if options.ShowPaperFigure_BaselineCorrected
    allL_bc = subtract_linear_baseline_by_ends_rows(allL_bs, options.CalibBaseline_EndPts);
    allH_bc = subtract_linear_baseline_by_ends_rows(allH_bs, options.CalibBaseline_EndPts);

    denL = max(allL_bc, [], 2, "omitnan");
    denH = max(allH_bc, [], 2, "omitnan");

    denL(~isfinite(denL) | denL <= 0) = 1;
    denH(~isfinite(denH) | denH <= 0) = 1;

    allL_disp_bc = allL_bc ./ denL;
    allH_disp_bc = allH_bc ./ denH;

    mLow_disp_bc = mean(allL_disp_bc, 1, "omitnan");
    mHigh_disp_bc = mean(allH_disp_bc, 1, "omitnan");

    mL_plot_bc = smoothdata(mLow_disp_bc, "movmean", span, "omitnan");
    mH_plot_bc = smoothdata(mHigh_disp_bc, "movmean", span, "omitnan");

    mL_plot_bc = mL_plot_bc ./ max(mL_plot_bc, [], "omitnan");
    mH_plot_bc = mH_plot_bc ./ max(mH_plot_bc, [], "omitnan");

    sdL_plot_bc = smoothdata(std(allL_disp_bc, 0, 1, "omitnan"), "movmean", 5, "omitnan");
    sdH_plot_bc = smoothdata(std(allH_disp_bc, 0, 1, "omitnan"), "movmean", 5, "omitnan");

    semL_plot_bc = sdL_plot_bc ./ sqrt(N);
    semH_plot_bc = sdH_plot_bc ./ sqrt(N);

    ref_conv_bc = subtract_linear_baseline_by_ends_noclip(ref_cal_conv_u, options.CalibBaseline_EndPts);
    ref_raw_bc = subtract_linear_baseline_by_ends_noclip(ref_cal_raw_u, options.CalibBaseline_EndPts);

    ref_conv_bc = normalize_vec_1d(ref_conv_bc, "max");
    ref_raw_bc = normalize_vec_1d(ref_raw_bc, "max");

    figs = gobjects(1, 1);
    figs(1) = figure("Color", "w", "Position", [1320, 100, 600, 550], "Name", "Final Paper Figure (baseline-corrected shape)");
    ax_bc = gca;
    hold(ax_bc, "on");
    grid(ax_bc, "on");
    box(ax_bc, "on");
    axis(ax_bc, "square");

    paperFS = 12;
    paperLW = 1.5;
    paperShadeAlpha = 0.2;

    plot(lambda_cal, ref_conv_bc, "k:", "LineWidth", paperLW, "DisplayName", "Cal Ref (conv, max; baseline-corr)");
    if options.ShowCalRefRawInMain
        plot(lambda_cal, ref_raw_bc, "k--", "LineWidth", paperLW, "DisplayName", "Cal Ref (raw, max; baseline-corr)");
    end

    plot_sh_paper(lambda_cal, mL_plot_bc, semL_plot_bc, cB, paperShadeAlpha, "Low Force (SEM, shape; baseline-corr)", paperLW);
    plot_sh_paper(lambda_cal, mH_plot_bc, semH_plot_bc, cR, paperShadeAlpha, "High Force (SEM, shape; baseline-corr)", paperLW);

    xlabel("Wavelength (\lambda, nm)", "FontSize", paperFS, "FontWeight", "bold");
    ylabel("Normalized Intensity", "FontSize", paperFS, "FontWeight", "bold");
    xlim(ax_bc, options.RefSanity_XLim);
    ylim(ax_bc, [-0.15 1.1]);

    legend(ax_bc, "Location", "best", "FontSize", paperFS - 2, "EdgeColor", "none");
    set(ax_bc, "FontSize", paperFS - 1, "LineWidth", 1.2, "TickDir", "out");
    title(ax_bc, sprintf("Baseline-corrected (ends). Calibration ref fixed: %s", char(calShort)), "Interpreter", "none");
end

%% 13) Reference comparison (RMSE ranking) on fixed lambda_cal
if options.RefCompare_Enable
    [refCurves, summaryT] = build_and_score_refs( ...
        refsAll, ...
        lambda_cal, ...
        gLSF, ...
        applyConvForRef, ...
        expL_u, ...
        fitRange, ...
        allowScaleForRanking, ...
        baselineForRanking, ...
        options.CalibBaseline_EndPts ...
        );

    fprintf("\nReference comparison (sorted by RMSE conv):\n");
    disp(summaryT);

    if options.SaveRefSummaryCSV
        outCsv = fullfile(dataDir, "ref_comparison_summary.csv");
        writetable(summaryT, outCsv);
        fprintf("Saved: %s\n", outCsv);
    end

    figs = gobjects(1, 1);
    figs(1) = figure("Color", "w", "Position", [250, 150, 900, 600], "Name", "Ref Cy3 Comparison (RMSE)");
    ax3 = gca;
    hold(ax3, "on");
    grid(ax3, "on");
    box(ax3, "on");
    axis(ax3, "square");

    plot(ax3, lambda_cal, expL_plot_use, "LineWidth", 2, "DisplayName", "Exp Low (intensity-mean, max)");
    plot(ax3, lambda_cal, expH_plot_use, "LineWidth", 2, "DisplayName", "Exp High (intensity-mean, max)");

    kTop = min(options.RefCompare_TopK, height(summaryT));
    topSet = summaryT.names(1:kTop);

    text(ax3, 0.02, 0.98, sprintf("Solid: convolved ref. Dashed: raw ref. GUI baseline=%d, GUI conv=%d, GUI scale=%d", useGuiBaseline, useGuiConv, useGuiScale), ...
        "Units", "normalized", ...
        "VerticalAlignment", "top", ...
        "FontSize", 10);

    for k = 1:numel(refCurves)
        nm = refCurves(k).shortName;
        isTop = any(nm == topSet);

        if isTop
            lbl = sprintf("%s (RMSE=%.4g)", char(nm), refCurves(k).rmseConv);
            hConv = plot(ax3, lambda_cal, refCurves(k).conv, "LineWidth", 1.4, "DisplayName", lbl);

            if options.RefCompare_ShowRawTop
                idxBeforeRaw = ax3.ColorOrderIndex;
                plot(ax3, lambda_cal, refCurves(k).raw, "--", "LineWidth", 1.0, ...
                    "Color", hConv.Color, ...
                    "HandleVisibility", "off");
                ax3.ColorOrderIndex = idxBeforeRaw;
            end
        else
            hThin = plot(ax3, lambda_cal, refCurves(k).conv, "LineWidth", 0.7);
            hThin.HandleVisibility = "off";
        end
    end

    xlabel(ax3, "Wavelength (\lambda, nm)", "FontWeight", "bold");
    ylabel(ax3, "Normalized Intensity", "FontWeight", "bold");
    xlim(ax3, options.RefSanity_XLim);
    ylim(ax3, [-0.15 1.1]);

    legend(ax3, "Location", "best", "Interpreter", "none");
    title(ax3, sprintf("Ref comparison (lambda_cal fixed by: %s)", char(calShort)), "Interpreter", "none");
        % --- Added: per-ref windows (Exp vs single ref) ---
    if options.RefCompare_PerRefFigures
        kTop2 = min(options.RefCompare_TopK, height(summaryT));
        topSet2 = summaryT.names(1:kTop2);

        for ii = 1:kTop2
            nm = topSet2(ii);

            idx = find(string({refCurves.shortName}) == nm, 1, "first");
            if isempty(idx)
                continue
            end

            figName = sprintf("Exp vs Ref (%s)", char(nm));
            figOne = figure("Color", "w", "Position", [320 + 30*ii, 140 + 20*ii, 720, 520], "Name", figName);

            axOne = axes(figOne);
            hold(axOne, "on");
            grid(axOne, "on");
            box(axOne, "on");
            axis(axOne, "square");

          % --- Exp curves with SEM (shape-based; consistent with existing semL_plot/semH_plot) ---
          expLW = 1.8;
          expAlpha = 0.20;

          % Choose exp shape curves consistent with ref baseline mode
          % If baselineForRanking==true, refCurves were built after baseline correction,
          % so use baseline-corrected exp SEM for apples-to-apples overlay.
          if baselineForRanking
              mL_use  = mL_plot_bc;   semL_use = semL_plot_bc;
              mH_use  = mH_plot_bc;   semH_use = semH_plot_bc;
              expTag  = "baseline-corr";
          else
              mL_use  = mL_plot;      semL_use = semL_plot;
              mH_use  = mH_plot;      semH_use = semH_plot;
              expTag  = "no-baseline";
          end

          plot_sh_paper(lambda_cal, mL_use, semL_use, cB, expAlpha, sprintf("Exp Low (SEM, shape; %s)", expTag), expLW);
          plot_sh_paper(lambda_cal, mH_use, semH_use, cR, expAlpha, sprintf("Exp High (SEM, shape; %s)", expTag), expLW);



            rmseC = refCurves(idx).rmseConv;
            rmseR = refCurves(idx).rmseRaw;

            lblConv = sprintf("Ref conv (%s), RMSE=%.4g", char(nm), rmseC);
            hConv = plot(axOne, lambda_cal, refCurves(idx).conv, "LineWidth", 1.6, "DisplayName", lblConv);

            if options.RefCompare_PerRefShowRaw
                plot(axOne, lambda_cal, refCurves(idx).raw, "--", "LineWidth", 1.2, "Color", hConv.Color, "DisplayName", sprintf("Ref raw, RMSE=%.4g", rmseR));
            end

            xlabel(axOne, "Wavelength (\lambda, nm)", "FontWeight", "bold");
            ylabel(axOne, "Normalized Intensity", "FontWeight", "bold");
            xlim(axOne, options.RefSanity_XLim);
            ylim(axOne, [-0.15 1.1]);

            noteTxt = sprintf("GUI baseline=%d, GUI conv=%d, GUI scale=%d", useGuiBaseline, useGuiConv, useGuiScale);
            text(axOne, 0.02, 0.98, noteTxt, "Units", "normalized", "VerticalAlignment", "top", "FontSize", 10);

            title(axOne, sprintf("Exp vs %s (conv RMSE=%.4g)", char(nm), rmseC), "Interpreter", "none");
            legend(axOne, "Location", "best", "Interpreter", "none");
        end
    end

end

%% 14) Ref sanity check figure (intensity domain, amplitude scaling)
if options.RefSanity_Enable
    if options.RefSanity_ShowBothBaselineModes
        figs = gobjects(1, 1);
        figs(1) = figure("Color", "w", "Position", [300, 120, 980, 420], "Name", "Ref sanity check (intensity mean)");
        tiledlayout(1, 2, "Padding", "compact", "TileSpacing", "compact");

        nexttile;
        plot_ref_sanity_panel(lambda_cal, expL_u, expH_u, ref_cal_raw_u, ref_cal_conv_u, fitRange, false, options.CalibBaseline_EndPts, useGuiScale);
        title("Baseline OFF (ends-linear not applied)", "Interpreter", "none");
        xlim(options.RefSanity_XLim);

        nexttile;
        plot_ref_sanity_panel(lambda_cal, expL_u, expH_u, ref_cal_raw_u, ref_cal_conv_u, fitRange, true, options.CalibBaseline_EndPts, useGuiScale);
        title(sprintf("Baseline ON (GUI=%d)", useGuiBaseline), "Interpreter", "none");
        xlim(options.RefSanity_XLim);
    else
        figs = gobjects(1, 1);
        figs(1) = figure("Color", "w", "Position", [340, 140, 780, 520], "Name", "Ref sanity check (intensity mean)");
        ax = axes(figs(1));
        hold(ax, "on");
        grid(ax, "on");
        box(ax, "on");

        doBase = useGuiBaseline;
        [expL_plot_int, expH_plot_int, refConv_scaled, refRaw_scaled, a] = compute_intensity_overlay( ...
            expL_u, expH_u, ref_cal_raw_u, ref_cal_conv_u, fitRange, doBase, options.CalibBaseline_EndPts, useGuiScale);

        plot(ax, lambda_cal, expL_plot_int, "LineWidth", 2, "DisplayName", sprintf("Exp Low (mean, baseline=%d)", doBase));
        plot(ax, lambda_cal, expH_plot_int, "LineWidth", 2, "DisplayName", sprintf("Exp High (mean, baseline=%d)", doBase));
        plot(ax, lambda_cal, refConv_scaled, "k-", "LineWidth", 1.6, "DisplayName", sprintf("Ref conv (scaled, a=%.3g)", a));
        plot(ax, lambda_cal, refRaw_scaled, "k--", "LineWidth", 1.0, "DisplayName", "Ref raw (scaled)");

        xlabel(ax, "Wavelength (\lambda, nm)");
        ylabel(ax, "Intensity (a.u.)");
        title(ax, sprintf("Ref sanity (GUI baseline=%d, GUI conv=%d, GUI scale=%d)", useGuiBaseline, useGuiConv, useGuiScale), "Interpreter", "none");
        xlim(ax, options.RefSanity_XLim);
        legend(ax, "Location", "best", "Interpreter", "none");
    end
end

end

%% --- Helper Functions ---

function refs = load_ref_list(refFiles)
nR = numel(refFiles);

refs = repmat(struct( ...
    "path", "", ...
    "shortName", "", ...
    "lambda", [], ...
    "inten", [], ...
    "peakLamRef", NaN ...
    ), nR, 1);

keep = false(nR, 1);

for k = 1:nR
    refPath = string(refFiles(k));
    [~, base, ext] = fileparts(refPath);

    M = readmatrix(refPath);
    if size(M, 2) < 2
        continue
    end

    lam = M(:, 1);
    inten = M(:, 2);

    lam = lam(:);
    inten = inten(:);

    valid = isfinite(lam) & isfinite(inten);
    lam = lam(valid);
    inten = inten(valid);

    if isempty(lam) || isempty(inten)
        continue
    end

    [lam, ord] = sort(lam);
    inten = inten(ord);

    [lamU, ~, ic] = unique(lam, "stable");
    if numel(lamU) < numel(lam)
        intenU = accumarray(ic, inten, [], @mean);
        fprintf("Ref %s: collapsed %d duplicate wavelength entries.\n", string(base) + string(ext), numel(lam) - numel(lamU));
        lam = lamU;
        inten = intenU;
    end

    [~, idxRef] = max(inten, [], "omitnan");
    peakLamRef = lam(idxRef);

    refs(k).path = refPath;
    refs(k).shortName = string(base) + string(ext);
    refs(k).lambda = lam;
    refs(k).inten = inten;
    refs(k).peakLamRef = peakLamRef;

    keep(k) = true;
end

refs = refs(keep);
end

function [useGuiBaseline, useGuiConv, useGuiScale] = read_gui_flags(guiOut, options)
useGuiBaseline = options.CalibBaselineCorrect;
useGuiConv = options.ApplyRefConvolution;
useGuiScale = false;

if isstruct(guiOut)
    if isfield(guiOut, "baselineCorrect")
        useGuiBaseline = logical(guiOut.baselineCorrect);
    end
    if isfield(guiOut, "useConv")
        useGuiConv = logical(guiOut.useConv);
    end
    if isfield(guiOut, "scaleRef")
        useGuiScale = logical(guiOut.scaleRef);
    end
end
end

function [slopeOpt, rmseBest] = optimize_slope_for_ref( ...
    initSlope, ...
    pixels, ...
    peakPix, ...
    lambda_ref, ...
    inten_ref_raw, ...
    yExp, ...
    fitRange, ...
    gLSF, ...
    applyConv, ...
    allowScale, ...
    doBaselineCorr, ...
    nEndBaseline ...
    )

[~, idxRef] = max(inten_ref_raw, [], "omitnan");
peakLamRef = lambda_ref(idxRef);

opts = optimset("MaxFunEvals", 2000, "TolFun", 1e-9);

errFun = @(slope) calculate_rmse_linear( ...
    slope, ...
    pixels, ...
    peakPix, ...
    peakLamRef, ...
    lambda_ref, ...
    inten_ref_raw, ...
    yExp, ...
    fitRange, ...
    gLSF, ...
    applyConv, ...
    allowScale, ...
    doBaselineCorr, ...
    nEndBaseline ...
    );

slopeOpt = fminsearch(errFun, initSlope, opts);
rmseBest = errFun(slopeOpt);
end

function rmse = calculate_rmse_linear( ...
    slope, ...
    pixels, ...
    peakPix, ...
    peakLamRef, ...
    lambda_ref, ...
    inten_ref_raw, ...
    yExp, ...
    fitRange, ...
    gLSF, ...
    applyConv, ...
    allowScale, ...
    doBaselineCorr, ...
    nEndBaseline ...
    )

x_mapped = slope .* (pixels - peakPix) + peakLamRef;

ref_pix = interp1(lambda_ref, inten_ref_raw, x_mapped, "linear", 0);
if applyConv
    ref_pix = nanconv1_same(ref_pix, gLSF);
end

if doBaselineCorr
    ref_pix = subtract_linear_baseline_by_ends_noclip(ref_pix, nEndBaseline);
end
ref_pix = normalize_vec_1d(ref_pix, "max");

y = yExp(fitRange);
r = ref_pix(fitRange);

y = y(:);
r = r(:);

valid = isfinite(y) & isfinite(r);
y = y(valid);
r = r(valid);

if isempty(y) || isempty(r)
    rmse = inf;
    return
end

if allowScale
    rr = dot(r, r);
    if rr > 0
        a = dot(y, r) / rr;
    else
        a = 0;
    end
    r = a .* r;
end

diff = y - r;
rmse = sqrt(mean(diff.^2, "omitnan"));
end

function [ref_raw, ref_conv] = ref_on_lambda_grid(lambda_ref, inten_ref, lambda_grid, gLSF, applyConv)
[lamU, ~, ic] = unique(lambda_ref(:), "stable");
inten_ref = inten_ref(:);

if numel(lamU) < numel(lambda_ref)
    inten_ref = accumarray(ic, inten_ref, [], @mean);
    lambda_ref = lamU;
else
    lambda_ref = lambda_ref(:);
end

ref_raw = interp1(lambda_ref, inten_ref, lambda_grid, "linear", 0);
ref_conv = ref_raw;

if applyConv
    ref_conv = nanconv1_same(ref_conv, gLSF);
end
end

function [refCurves, summaryT] = build_and_score_refs( ...
    refs, ...
    lambda_cal, ...
    gLSF, ...
    applyConv, ...
    yExp_u, ...
    fitRange, ...
    allowScale, ...
    baselineCorrect, ...
    nEndBaseline ...
    )

nR = numel(refs);

refCurves = repmat(struct( ...
    "shortName", "", ...
    "raw", [], ...
    "conv", [], ...
    "rmseRaw", NaN, ...
    "rmseConv", NaN ...
    ), nR, 1);

names = strings(nR, 1);
rmseRaw = nan(nR, 1);
rmseConv = nan(nR, 1);

yFor = yExp_u;
if baselineCorrect
    yFor = subtract_linear_baseline_by_ends_noclip(yFor, nEndBaseline);
end
yFor = normalize_vec_1d(yFor, "max");

for k = 1:nR
    [rRaw_u, rConv_u] = ref_on_lambda_grid(refs(k).lambda, refs(k).inten, lambda_cal, gLSF, applyConv);

    rRaw = rRaw_u;
    rConv = rConv_u;

    if baselineCorrect
        rRaw = subtract_linear_baseline_by_ends_noclip(rRaw, nEndBaseline);
        rConv = subtract_linear_baseline_by_ends_noclip(rConv, nEndBaseline);
    end

    rRaw = normalize_vec_1d(rRaw, "max");
    rConv = normalize_vec_1d(rConv, "max");

    rmseKRaw = rmse_with_optional_scale(yFor, rRaw, fitRange, allowScale);
    rmseKConv = rmse_with_optional_scale(yFor, rConv, fitRange, allowScale);

    refCurves(k).shortName = refs(k).shortName;
    refCurves(k).raw = rRaw;
    refCurves(k).conv = rConv;
    refCurves(k).rmseRaw = rmseKRaw;
    refCurves(k).rmseConv = rmseKConv;

    names(k) = refs(k).shortName;
    rmseRaw(k) = rmseKRaw;
    rmseConv(k) = rmseKConv;
end

summaryT = table(names, rmseConv, rmseRaw);
summaryT = sortrows(summaryT, "rmseConv", "ascend");
end

function rmse = rmse_with_optional_scale(y, r, fitRange, allowScale)
y0 = y(fitRange);
r0 = r(fitRange);

y0 = y0(:);
r0 = r0(:);

valid = isfinite(y0) & isfinite(r0);
y0 = y0(valid);
r0 = r0(valid);

if isempty(y0) || isempty(r0)
    rmse = inf;
    return
end

if allowScale
    rr = dot(r0, r0);
    if rr > 0
        a = dot(y0, r0) / rr;
    else
        a = 0;
    end
    r0 = a .* r0;
end

d = y0 - r0;
rmse = sqrt(mean(d.^2, "omitnan"));
end

function outArr = extract_window(inArr, idxStart, idxEnd, targetLen)
outArr = nan(1, targetLen);

validStart = max(1, idxStart);
validEnd = min(length(inArr), idxEnd);

if validStart > validEnd
    return
end

outIdxStart = validStart - idxStart + 1;
outArr(outIdxStart:outIdxStart + (validEnd - validStart)) = inArr(validStart:validEnd);
end

function g = gaussian_kernel_fwhm_px(fwhm_px)
sigma = fwhm_px / (2 * sqrt(2 * log(2)));
halfWidth = max(1, ceil(4 * sigma));
x = (-halfWidth:halfWidth).';
g = exp(-(x.^2) / (2 * sigma^2));
g = g ./ sum(g);
end

function g = lsf_from_psf_mat(psfMatFile, varName, dispAxis)
S = load(psfMatFile);

if ~isfield(S, varName)
    fns = fieldnames(S);
    msg = "PSF variable '" + varName + "' not found in " + psfMatFile + ". Available: " + strjoin(string(fns), ", ");
    error(msg);
end

psf2d = double(S.(varName));

border = [psf2d(1, :), psf2d(end, :), psf2d(:, 1).', psf2d(:, end).'];
bg = median(border, "omitnan");

psf2d = psf2d - bg;
psf2d(psf2d < 0) = 0;

if dispAxis == "x"
    g = sum(psf2d, 1, "omitnan").';
else
    g = sum(psf2d, 2, "omitnan");
end

g = g(:);
if ~any(g > 0)
    g = [0; 1; 0];
end

g = g ./ sum(g, "omitnan");
end

function y = nanconv1_same(x, g)
x = x(:);
mask = ~isnan(x);

x0 = x;
x0(~mask) = 0;

num = conv(x0, g, "same");
den = conv(double(mask), g, "same");

y = num ./ den;
y(den == 0) = NaN;
end

function y = normalize_vec_1d(y, mode)
switch mode
    case "area"
        denom = sum(y, "omitnan");
    case "max"
        denom = max(y, [], "omitnan");
    otherwise
        denom = max(y, [], "omitnan");
end

if denom <= 0 || ~isfinite(denom)
    denom = 1;
end

y = y ./ denom;
end

function colOut = lighten_color(colIn, fracToWhite)
fracToWhite = min(max(fracToWhite, 0), 1);
colOut = colIn + (1 - colIn) * fracToWhite;
end

function h = plot_sh(x, m, err, col, alphaVal, nameLabel)
% Shaded error band + mean line (interactive-safe)

x = x(:).';
m = m(:).';
err = err(:).';

valid = isfinite(x) & isfinite(m) & isfinite(err);
x = x(valid);
m = m(valid);
err = err(valid);

if isempty(x)
    h = plot(nan, nan);
    return
end

upper = (m + err);
lower = (m - err);

hp = fill([x, fliplr(x)], [upper, fliplr(lower)], col, ...
    "EdgeColor", "none", ...
    "FaceAlpha", alphaVal, ...
    "HandleVisibility", "off");

% --- Critical: prevent plotSelectMode / plot edit from picking the patch ---
hp.HitTest = "off";
if isprop(hp, "PickableParts")
    hp.PickableParts = "none";
end

h = plot(x, m, "Color", col, "LineWidth", 2, "DisplayName", char(nameLabel));
end


function h = plot_sh_paper(x, m, err, col, alphaVal, nameLabel, lineW)
% Paper-style shaded error band + mean line (interactive-safe)

x = x(:).';
m = m(:).';
err = err(:).';

valid = isfinite(x) & isfinite(m) & isfinite(err);
x = x(valid);
m = m(valid);
err = err(valid);

if isempty(x)
    h = plot(nan, nan);
    return
end

upper = (m + err);
lower = (m - err);

hp = fill([x, fliplr(x)], [upper, fliplr(lower)], col, ...
    "EdgeColor", "none", ...
    "FaceAlpha", alphaVal, ...
    "HandleVisibility", "off");

% --- Critical: prevent plotSelectMode / plot edit from picking the patch ---
hp.HitTest = "off";
if isprop(hp, "PickableParts")
    hp.PickableParts = "none";
end

h = plot(x, m, "Color", col, "LineWidth", lineW, "DisplayName", char(nameLabel));
end

function yCorr = subtract_linear_baseline_by_ends_noclip(y, nEnd)
y = y(:).';
n = numel(y);
if n == 0
    yCorr = y;
    return
end

nEnd = max(1, min(nEnd, floor(n / 4)));
iL = 1:nEnd;
iR = (n - nEnd + 1):n;

yL = median(y(iL), "omitnan");
yR = median(y(iR), "omitnan");

if ~isfinite(yL)
    yL = 0;
end
if ~isfinite(yR)
    yR = 0;
end

x = 1:n;
slope = (yR - yL) / max(1, (n - 1));
baseLine = yL + slope .* (x - 1);

yCorr = y - baseLine;
yCorr(~isfinite(yCorr)) = NaN;
end

function Ycorr = subtract_linear_baseline_by_ends_rows(Y, nEnd)
Y = double(Y);

n = size(Y, 2);
if n == 0
    Ycorr = Y;
    return
end

nEnd = max(1, min(nEnd, floor(n / 4)));

iL = 1:nEnd;
iR = (n - nEnd + 1):n;

yL = median(Y(:, iL), 2, "omitnan");
yR = median(Y(:, iR), 2, "omitnan");

yL(~isfinite(yL)) = 0;
yR(~isfinite(yR)) = 0;

x = 1:n;
den = max(1, n - 1);

slope = (yR - yL) ./ den;
baseLine = yL + slope .* (x - 1);

Ycorr = Y - baseLine;
Ycorr(~isfinite(Ycorr)) = NaN;
end

function fitRange = fitrange_by_threshold(y, frac, peakIdx)
y = y(:);
mx = max(y, [], "omitnan");
if ~(isfinite(mx) && mx > 0)
    fitRange = 1:numel(y);
    return
end

thr = frac .* mx;
idx = find(y >= thr);

if isempty(idx)
    fitRange = 1:numel(y);
    return
end

if peakIdx < 1 || peakIdx > numel(y) || ~isfinite(peakIdx)
    peakIdx = round(numel(y) / 2);
end

d = diff(idx);
cuts = find(d > 1);
bStart = [idx(1); idx(cuts + 1)];
bEnd = [idx(cuts); idx(end)];

inBlock = (bStart <= peakIdx) & (peakIdx <= bEnd);
if any(inBlock)
    j = find(inBlock, 1, "first");
    fitRange = bStart(j):bEnd(j);
else
    fitRange = idx(1):idx(end);
end
end

function plot_ref_sanity_panel(lambda_cal, expL_u, expH_u, ref_raw_u, ref_conv_u, fitRange, doBaseline, nEndBaseline, allowScale)
ax = gca;
hold(ax, "on");
grid(ax, "on");
box(ax, "on");

[expL_plot, expH_plot, refConv_scaled, refRaw_scaled, a] = compute_intensity_overlay( ...
    expL_u, expH_u, ref_raw_u, ref_conv_u, fitRange, doBaseline, nEndBaseline, allowScale);

plot(ax, lambda_cal, expL_plot, "LineWidth", 2, "DisplayName", "Exp Low (mean)");
plot(ax, lambda_cal, expH_plot, "LineWidth", 2, "DisplayName", "Exp High (mean)");
plot(ax, lambda_cal, refConv_scaled, "k-", "LineWidth", 1.6, "DisplayName", sprintf("Ref conv (scaled, a=%.3g)", a));
plot(ax, lambda_cal, refRaw_scaled, "k--", "LineWidth", 1.0, "DisplayName", "Ref raw (scaled)");

xlabel(ax, "Wavelength (\lambda, nm)");
ylabel(ax, "Intensity (a.u.)");
legend(ax, "Location", "best", "Interpreter", "none");
end

function [expL_plot, expH_plot, refConv_scaled, refRaw_scaled, a] = compute_intensity_overlay( ...
    expL_u, expH_u, ref_raw_u, ref_conv_u, fitRange, doBaseline, nEndBaseline, allowScale)

if nargin < 8
    allowScale = false;
end

expL = expL_u;
expH = expH_u;
rRaw = ref_raw_u;
rConv = ref_conv_u;

if doBaseline
    expL = subtract_linear_baseline_by_ends_noclip(expL, nEndBaseline);
    expH = subtract_linear_baseline_by_ends_noclip(expH, nEndBaseline);
    rRaw = subtract_linear_baseline_by_ends_noclip(rRaw, nEndBaseline);
    rConv = subtract_linear_baseline_by_ends_noclip(rConv, nEndBaseline);
end

fitRange = fitRange(:);
fitRange = fitRange( ...
    fitRange >= 1 & ...
    fitRange <= numel(expL) & ...
    fitRange <= numel(rConv));

y = expL(fitRange);
r = rConv(fitRange);

y = y(:);
r = r(:);

valid = isfinite(y) & isfinite(r);
y = y(valid);
r = r(valid);

a = 1;

if allowScale
    rr = dot(r, r);
    if rr > 0
        a = dot(y, r) / rr;
    end
end

refConv_scaled = a .* rConv;
refRaw_scaled = a .* rRaw;

expL_plot = expL;
expH_plot = expH;
end
