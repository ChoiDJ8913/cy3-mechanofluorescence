function visualize_bg_subtraction(rawLow, rawHigh, bgLow, bgHigh, roi, savedir, fileID, roiID)
    % roi = [x y w h]
    x = roi(1); y = roi(2); w = roi(3); h = roi(4);
    
    % 추출된 ROI 패치
    rawLow_patch = rawLow(y:y+h-1, x:x+w-1);
    rawHigh_patch = rawHigh(y:y+h-1, x:x+w-1);
    bgLow_patch = bgLow(y:y+h-1, x:x+w-1);
    bgHigh_patch = bgHigh(y:y+h-1, x:x+w-1);

    patchLow = rawLow_patch - bgLow_patch;
    patchHigh = rawHigh_patch - bgHigh_patch;
    residualLow = bgLow_patch - rawLow_patch;
    residualHigh = bgHigh_patch - rawHigh_patch;

    % 컬러맵과 범위 설정
    cmap_main = 'jet';
    cmap_res = 'redblue';  % red-blue diverging colormap
    clim_main = [min([rawLow_patch(:); rawHigh_patch(:); bgLow_patch(:); bgHigh_patch(:)]), ...
                 max([rawLow_patch(:); rawHigh_patch(:); bgLow_patch(:); bgHigh_patch(:)])];
    clim_sub = [0, 2500];
    clim_res = [-3000, 0];

    % Figure 생성
    figure('Color','w','Position',[100 100 1600 800]);

    % Row 1: Low
    plot_image(rawLow_patch,     1, 'Raw ROI (Low)',            clim_main, cmap_main);
    plot_image(bgLow_patch,      2, 'Interpolated BG (Low)',    clim_main, cmap_main);
    plot_image(patchLow,         3, 'BG Subtracted ROI (Low)',  clim_sub,  cmap_main);
    plot_image(residualLow,      4, 'Residual (Low)',           clim_res,  cmap_res);

    % Row 2: High
    plot_image(rawHigh_patch,    5, 'Raw ROI (High)',           clim_main, cmap_main);
    plot_image(bgHigh_patch,     6, 'Interpolated BG (High)',   clim_main, cmap_main);
    plot_image(patchHigh,        7, 'BG Subtracted ROI (High)', clim_sub,  cmap_main);
    plot_image(residualHigh,     8, 'Residual (High)',          clim_res,  cmap_res);

    % 저장
    saveas(gcf, fullfile(savedir, sprintf('%s_ROI%d_BG_check.png', fileID, roiID)));
    close;
end

% === 서브함수 정의 ===
function plot_image(data, pos, titleStr, climit, cmap)
    subplot(2,4,pos);
    imagesc(data);
    axis image off;
    title(titleStr);
    colormap(gca, cmap);
    clim(climit);
    colorbar;
end
