% ROI Viewer GUI - Step 5: Add side-by-side raw + normalized 1D plots
function roi_viewer_gui()
% === Create GUI Window ===
fig = uifigure('Name','ROI Viewer','Position',[100 100 1350 800]);

% === Folder Selection Button ===
btnFolder = uibutton(fig, 'Text','Select Folder', 'Position',[20 700 90 22], ...
    'ButtonPushedFcn', @(btn,~) select_folder());

% === Save 1D Signal Data 버튼 추가 ===
btnSave1D = uibutton(fig, 'Text','Save 1D Data', ...
    'Position',[140 600 120 22], ...
    'ButtonPushedFcn', @(btn,~) save_1d_signal_data());

% === 배경 보간 위치 설정 (전/후 비교용) ===
lblBGPos = uilabel(fig, 'Text','Background Position:', 'Position',[20 730 120 22]);
bgPosGroup = uidropdown(fig, 'Position',[150 730 150 22], ...
    'Items', {'Before ROI (full image)','After ROI (within ROI)','Compare'}, 'Value', 'Before ROI (full image)', ...
    'ValueChangedFcn', @(dd,~) update_display());

% === Dropdown: ROI file selection ===
lblFile = uilabel(fig, 'Text','ROI File:', 'Position',[130 700 60 12]);
ddFile = uidropdown(fig, 'Position',[200 700 300 22], 'Items', {}, 'ValueChangedFcn', @(dd,~) load_roi_file(dd.Value));

% === Dropdown: ROI ID selection ===
lblROI = uilabel(fig, 'Text','ROI:', 'Position',[520 700 40 22]);
ddROI = uidropdown(fig, 'Position',[570 700 100 22], 'Items', {}, 'ValueChangedFcn', @(dd,~) update_display());

% === Background Subtraction Controls ===
cbBG = uicheckbox(fig, 'Text','Subtract Background', 'Position',[700 700 150 22], ...
    'Value', true, 'ValueChangedFcn', @(cb,~) update_display());

lblBGMethod = uilabel(fig, 'Text','Method:', 'Position',[870 700 50 22]);
ddBGMethod = uidropdown(fig, 'Position',[930 700 140 22], ...
    'Items', {'min','gauss','polyfit2d'}, 'Value', 'min', ...
    'ValueChangedFcn', @(dd,~) update_display());

% === Normalize Checkbox ===
cbNorm = uicheckbox(fig, 'Text','Normalize 1D', 'Position',[1090 700 120 22], 'Value', false, 'ValueChangedFcn', @(cb,~) update_display());

% === rowBand Slider ===
lblSlider = uilabel(fig, 'Text','rowBand:', 'Position',[20 660 60 22]);
lblBandVal = uilabel(fig, 'Text','rowBand = 5','Position',[90 620 150 22]);
sliderRow = uislider(fig, 'Position',[90 670 150 3], 'Limits',[1 5], 'Value', 5, ...
    'MajorTicks', 1:5, ...
    'ValueChangingFcn', @(sld,event) update_row_band_value(event.Value), ...
    'ValueChangedFcn', @(sld,~) update_display());

% === rowCenter Slider ===
lblRowCenter = uilabel(fig, 'Text','rowCenter:', 'Position',[260 660 70 22]);
sliderCenter = uislider(fig, 'Position',[340 670 200 3], 'Limits',[1 100], 'Value', 50, ...
    'MajorTicks', 1:10:100, ...
    'ValueChangingFcn', @(sld,event) update_row_center_value(event.Value), ...
    'ValueChangedFcn', @(sld,~) update_display());

% === rowCenter value label ===
lblRowVal = uilabel(fig, 'Text','rowCenter = 1','Position',[340 620 200 40]);

% === Tab Group ===
tabGroup = uitabgroup(fig, 'Position',[20 300 1210 240]);

tab2D = uitab(tabGroup, 'Title', '2D View');
tab3D = uitab(tabGroup, 'Title', '3D View');


% === Axes for image and plot ===
axLow = uiaxes(tab2D, 'Position',[50 10 320 200]); axLow.Title.String = 'imageLow';
axHigh = uiaxes(tab2D, 'Position',[400 10 320 200]); axHigh.Title.String = 'imageHigh';
axDelta = uiaxes(tab2D, 'Position',[750 10 320 200]); axDelta.Title.String = '\Delta image (High - Low)';
axSurfLow = uiaxes(tab3D, 'Position',[50 10 320 200]); axSurfLow.Title.String = 'Surf - Low';
axSurfHigh = uiaxes(tab3D, 'Position',[400 10 320 200]); axSurfHigh.Title.String = 'Surf - High';
axSurfDelta = uiaxes(tab3D, 'Position',[750 10 320 200]); axSurfDelta.Title.String = 'Surf - \Delta';

axPlotRaw = uiaxes(fig, 'Position',[80 40 500 240]);
axPlotRaw.Title.String = '1D Spectrum (Raw)';
xlabel(axPlotRaw, 'Pixel'); ylabel(axPlotRaw, 'Intensity');
axPlotNorm = uiaxes(fig, 'Position',[630 40 500 240]);
axPlotNorm.Title.String = '1D Spectrum (Normalized)';
xlabel(axPlotNorm, 'Pixel'); ylabel(axPlotNorm, 'Norm. Intensity');

% === save figure informaiton ===
btnSave = uibutton(fig, 'Text','Save Figure', ...
    'Position',[20 600 100 22], ...
    'ButtonPushedFcn', @(btn,~) save_current_roi_figure());

% === App Data ===
setappdata(fig, 'roiInfo', []);
setappdata(fig, 'ddROI', ddROI);
setappdata(fig, 'axLow', axLow);
setappdata(fig, 'axHigh', axHigh);
setappdata(fig, 'axDelta', axDelta);
setappdata(fig, 'axPlotRaw', axPlotRaw);
setappdata(fig, 'axSurfLow', axSurfLow);
setappdata(fig, 'axSurfHigh', axSurfHigh);
setappdata(fig, 'axSurfDelta', axSurfDelta);
setappdata(fig, 'axPlotNorm', axPlotNorm);
setappdata(fig, 'roiFolder', fullfile(pwd, 'Saved_ROIs'));
setappdata(fig, 'ddFile', ddFile);
setappdata(fig, 'cbBG', cbBG);
setappdata(fig, 'ddBGMethod', ddBGMethod);
setappdata(fig, 'cbNorm', cbNorm);
setappdata(fig, 'sliderRow', sliderRow);
setappdata(fig, 'lblBandVal', lblBandVal);
setappdata(fig, 'sliderCenter', sliderCenter);
setappdata(fig, 'lblRowVal', lblRowVal);
setappdata(fig, 'bgPosGroup', bgPosGroup);

refresh_file_list();

    function update_row_center_value(val)
        lblRowVal = getappdata(fig, 'lblRowVal');
        lblRowVal.Text = sprintf('rowCenter = %d', round(val));
    end

    function update_row_band_value(val)
        lblBandVal = getappdata(fig, 'lblBandVal');
        lblBandVal.Text = sprintf('rowBand = %d', round(val));
    end

    function select_folder()
        folder = uigetdir(pwd, 'Select ROI Folder');
        if folder == 0, return; end
        setappdata(fig, 'roiFolder', folder);
        refresh_file_list();
    end

    function refresh_file_list()
        folder = getappdata(fig, 'roiFolder');
        f = dir(fullfile(folder, '*_ROIs.mat'));
        files = {f.name};
        if isempty(files)
            files = {'<no ROI files>'};
        end
        ddFile = getappdata(fig, 'ddFile');
        ddFile.Items = files;
        if ~strcmp(files{1}, '<no ROI files>')
            ddFile.Value = files{1};
            load_roi_file(files{1});
        else
            ddFile.Value = files{1};
            setappdata(fig, 'roiInfo', []);
            ddROI.Items = {};
        end
    end

    function load_roi_file(filename)
        folder = getappdata(fig, 'roiFolder');
        if contains(filename, '<no')
            return;
        end
        data = load(fullfile(folder, filename));
        roiInfo = data.roiInfo;
        setappdata(fig, 'roiInfo', roiInfo);
        roiIDs = arrayfun(@(r) num2str(r.roiID), roiInfo, 'UniformOutput', false);
        ddROI = getappdata(fig, 'ddROI');
        ddROI.Items = roiIDs;
        ddROI.Value = roiIDs{1};

        % === Set sliderCenter range based on image height ===
        roiH = size(roiInfo(1).imageLow, 1);
        sliderCenter = getappdata(fig, 'sliderCenter');
        sliderCenter.Limits = [1 roiH];
        sliderCenter.Value = round(roiH / 2);
        if roiH <= 20
            step = 2;
        elseif roiH <= 50
            step = 5;
        else
            step = 10;
        end
        sliderCenter.MajorTicks = 1:step:roiH;

        update_display();
    end

    function save_current_roi_figure()
        roiInfo = getappdata(fig, 'roiInfo');
        if isempty(roiInfo), return; end

        ddROI = getappdata(fig, 'ddROI');
        roiID = str2double(ddROI.Value);
        info = roiInfo(roiID);

        [file, path] = uiputfile('ROI_*.png', 'Save ROI Figure As');
        if isequal(file, 0), return; end

        f = figure('Visible','off', 'Color','w', 'Position',[100 100 1200 600]);

        subplot(2,3,1); imagesc(info.imageLow); axis image; colormap('hot'); title('imageLow');
        subplot(2,3,2); imagesc(info.imageHigh); axis image; colormap('hot'); title('imageHigh');
        subplot(2,3,3); imagesc(info.imageHigh - info.imageLow); axis image; colormap('jet'); title('High - Low');


        % rowBand + center 반영
        sliderRow = getappdata(fig, 'sliderRow');
        sliderCenter = getappdata(fig, 'sliderCenter');
        rowCenter = round(sliderCenter.Value);
        rowBand = round(sliderRow.Value);
        rowRange = max(1, rowCenter - rowBand):min(size(info.imageLow,1), rowCenter + rowBand);

        profLow = sum(info.imageLow(rowRange,:),1);
        profHigh = sum(info.imageHigh(rowRange,:),1);

        subplot(2,1,2);
        plot(profLow, 'k-', 'LineWidth', 1.5); hold on;
        plot(profHigh, 'r-', 'LineWidth', 1.5);
        legend('Low Force', 'High Force'); title('1D Spectrum');

        saveas(f, fullfile(path, file));
        close(f);
    end

    function save_1d_signal_data()
        roiInfo = getappdata(fig, 'roiInfo');
        if isempty(roiInfo), return; end

        ddROI = getappdata(fig, 'ddROI');
        roiID = str2double(ddROI.Value);
        info = roiInfo(roiID);

        % rowCenter, rowBand 슬라이더 값 가져오기
        sliderRow = getappdata(fig, 'sliderRow');
        sliderCenter = getappdata(fig, 'sliderCenter');
        rowCenter = round(sliderCenter.Value);
        rowBand = round(sliderRow.Value);
        rowRange = max(1, rowCenter - rowBand):min(size(info.imageLow,1), rowCenter + rowBand);

        % 백그라운드 제거
        method = getappdata(fig, 'ddBGMethod').Value;
        low = info.imageLow;
        high = info.imageHigh;

        switch method
            case 'interp'
                [X,Y] = meshgrid(1:size(low,2), 1:size(low,1));
                maskLow = low < prctile(low(:), 20);
                maskHigh = high < prctile(high(:), 20);
                bgLow = scatteredInterpolant(X(maskLow), Y(maskLow), low(maskLow), 'linear', 'nearest');
                bgHigh = scatteredInterpolant(X(maskHigh), Y(maskHigh), high(maskHigh), 'linear', 'nearest');
                low = low - bgLow(X,Y);
                high = high - bgHigh(X,Y);
                low(low<0) = 0; high(high<0) = 0;
            case 'min'
                low = low - min(low(:));
                high = high - min(high(:));
            case 'gauss'
                low = low - imgaussfilt(low, 2);
                high = high - imgaussfilt(high, 2);
            case 'polyfit2d'
                [X, Y] = meshgrid(1:size(low,2), 1:size(low,1));
                F_low = fit([X(:), Y(:)], low(:), 'poly22');
                F_high = fit([X(:), Y(:)], high(:), 'poly22');
                low = low - reshape(F_low(X(:), Y(:)), size(low));
                high = high - reshape(F_high(X(:), Y(:)), size(high));
                low(low<0) = 0; high(high<0) = 0;
            case 'median20'
                bgLow = median(low(low < prctile(low(:), 20)));
                bgHigh = median(high(high < prctile(high(:), 20)));
                low = low - bgLow; high = high - bgHigh;
                low(low<0) = 0; high(high<0) = 0;
        end

        % 신호 계산
        profLow = mean(low(rowRange,:),1);
        profHigh = mean(high(rowRange,:),1);

        % 저장 구조 정의
        signalData.roiID = roiID;
        signalData.rowCenter = rowCenter;
        signalData.rowBand = rowBand;
        signalData.rowRange = rowRange;
        signalData.profLow = profLow;
        signalData.profHigh = profHigh;
        signalData.normLow = profLow / max(profLow);
        signalData.normHigh = profHigh / max(profHigh);
        signalData.diff = profHigh - profLow;
        signalData.imageLow = info.imageLow;
        signalData.imageHigh = info.imageHigh;

        % 저장 경로 선택
        saveDir = uigetdir('D:\MT\roi_selected_fig', 'Select folder to save signal data');
        if saveDir == 0, return; end

        % 저장 파일명 구성
        ddFile = getappdata(fig, 'ddFile');
        roiFolder = getappdata(fig, 'roiFolder');
        folderParts = split(roiFolder, filesep);
        parentFolder = folderParts{end-1};
        fileTag = replace(ddFile.Value, {'\\', '/'}, '_');
        saveName = sprintf('%s__%s_ROI%d_signalData.mat', parentFolder, fileTag, roiID);

        % === 저장 실행 ===
        save(fullfile(saveDir, saveName), 'signalData');
        uialert(fig, sprintf('Saved: %s', saveName), '1D Signal Saved');
    end

    function update_display()
        roiInfo = getappdata(fig, 'roiInfo');
        if isempty(roiInfo), return; end

        ddROI        = getappdata(fig, 'ddROI');
        roiID        = str2double(ddROI.Value);
        info         = roiInfo(roiID);
        axLow        = getappdata(fig, 'axLow');
        axHigh       = getappdata(fig, 'axHigh');
        axDelta      = getappdata(fig, 'axDelta');
        axSurfLow    = getappdata(fig, 'axSurfLow');
        axSurfHigh   = getappdata(fig, 'axSurfHigh');
        axSurfDelta  = getappdata(fig, 'axSurfDelta');
        axPlotRaw    = getappdata(fig, 'axPlotRaw');
        axPlotNorm   = getappdata(fig, 'axPlotNorm');
        cbBG         = getappdata(fig, 'cbBG');
        ddBGMethod   = getappdata(fig, 'ddBGMethod');
        cbNorm       = getappdata(fig, 'cbNorm');
        sliderRow    = getappdata(fig, 'sliderRow');
        sliderCenter = getappdata(fig, 'sliderCenter');
        bgPosGroup   = getappdata(fig, 'bgPosGroup');

        method  = ddBGMethod.Value;
        bgMode  = bgPosGroup.Value;
        low_raw = info.imageLow;
        high_raw = info.imageHigh;


        if cbBG.Value
            [low, high] = apply_background_subtraction(low_raw, high_raw, method);
        else
            low = low_raw;
            high = high_raw;
        end

        delta = high - low;

        % === Row 중심 설정 ===
        rowCenter = round(sliderCenter.Value);
        rowBand = round(sliderRow.Value);
        rowRange = max(1, rowCenter - rowBand):min(size(low,1), rowCenter + rowBand);

        % === 프로파일 계산 ===
        profLow = mean(low(rowRange,:), 1);
        profHigh = mean(high(rowRange,:), 1);
        if cbNorm.Value
            profLow = profLow / max(profLow);
            profHigh = profHigh / max(profHigh);
        end

        % === 2D 이미지 ===
        imagesc(axLow, low); axis(axLow,'image'); colormap(axLow,'jet'); hold(axLow,'on');
        yline(axLow, rowCenter, '-w', 'LineWidth', 1.5);
        for r = rowRange
            if r ~= rowCenter, yline(axLow, r, '--c', 'LineWidth', 1); end
        end
        hold(axLow,'off');

        imagesc(axHigh, high); axis(axHigh,'image'); colormap(axHigh,'jet'); hold(axHigh,'on');
        for r = rowRange
            yline(axHigh, r, '--c', 'LineWidth', 0.5);
        end
        yline(axHigh, rowCenter, '-w', 'LineWidth', 1.5);
        hold(axHigh,'off');

        imagesc(axDelta, delta); axis(axDelta,'image'); colormap(axDelta,'redblue'); colorbar(axDelta);

        % === 3D Surface ===
        surf(axSurfLow, double(low)); view(axSurfLow, 3); colormap(axSurfLow,'jet'); shading(axSurfLow, 'interp'); title(axSurfLow,'Surf - Low');
        surf(axSurfHigh, double(high)); view(axSurfHigh, 3); colormap(axSurfHigh,'jet'); shading(axSurfHigh, 'interp'); title(axSurfHigh,'Surf - High');
        surf(axSurfDelta, double(delta)); view(axSurfDelta, 3); colormap(axSurfDelta,'redblue'); shading(axSurfDelta, 'interp'); title(axSurfDelta,'Surf - \Delta');

        % === 1D Plot ===
        plot(axPlotRaw, profLow, 'k-', 'LineWidth', 1.5); hold(axPlotRaw, 'on');
        plot(axPlotRaw, profHigh, 'r-', 'LineWidth', 1.5); hold(axPlotRaw, 'off');
        legend(axPlotRaw, {'Low Force','High Force'}); xlabel(axPlotRaw,'Pixel'); ylabel(axPlotRaw,'Intensity');ylim([(min(profLow)-30) max(profLow)]);

        plot(axPlotNorm, profLow / max(profLow), '-k', 'LineWidth', 1.5); hold(axPlotNorm, 'on');
        plot(axPlotNorm, profHigh / max(profHigh), '-r', 'LineWidth', 1.5); hold(axPlotNorm, 'off');
        legend(axPlotNorm, {'Low-norm','High-norm'}); xlabel(axPlotNorm,'Pixel'); ylabel(axPlotNorm,'Normalized Intensity');ylim([(min(profLow / max(profLow))-30) max(profHigh / max(profHigh))]);

        % === 키보드 이벤트 등록 ===
        fig.KeyPressFcn = @(src, event) handle_keypress(event);

        function handle_keypress(event)
            ddROI = getappdata(fig, 'ddROI');
            items = ddROI.Items;
            if isempty(items), return; end

            currentIndex = find(strcmp(ddROI.Value, items));
            if isempty(currentIndex), return; end

            switch event.Key
                case {'rightarrow','downarrow'}
                    nextIndex = min(currentIndex + 1, numel(items));
                    ddROI.Value = items{nextIndex};
                    update_display();
                case {'leftarrow','uparrow'}
                    prevIndex = max(currentIndex - 1, 1);
                    ddROI.Value = items{prevIndex};
                    update_display();
            end
        end
    end
end