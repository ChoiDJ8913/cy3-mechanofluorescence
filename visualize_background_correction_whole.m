function visualize_background_correction_whole(meanLow, meanHigh, bgLow_full, bgHigh_full, savedir, fileID)
% VISUALIZE_BACKGROUND_CORRECTION_WHOLE
%   전체 이미지 수준에서 BG 보간 품질 확인용 시각화
%   각 조건별 mean / BG / subtracted 이미지 3종 시각화

    correctedLow  = meanLow - bgLow_full;
    correctedHigh = meanHigh - bgHigh_full;
    correctedLow(correctedLow < 0) = 0;
    correctedHigh(correctedHigh < 0) = 0;
    zlim_max = max(meanLow(:));
    clim_cor = max(correctedLow(:));
    % === Plot ===
    f1 = figure('Name','Full Image BG Correction','Position',[100 100 1400 600],'Color','w');

    subplot(2,3,1); imagesc(meanLow); axis image off; title('meanLow'); colorbar; clim([0 zlim_max]); colormap('jet');
    subplot(2,3,2); imagesc(bgLow_full); axis image off; title('bgLow\_full'); colorbar; clim([0 zlim_max]); colormap('jet');
    subplot(2,3,3); imagesc(correctedLow); axis image off; title('meanLow - bgLow'); colorbar; clim([0 clim_cor]); colormap('jet');

    subplot(2,3,4); imagesc(meanHigh); axis image off; title('meanHigh'); colorbar; clim([0 zlim_max]); colormap('jet');
    subplot(2,3,5); imagesc(bgHigh_full); axis image off; title('bgHigh\_full'); colorbar; clim([0 zlim_max]); colormap('jet');
    subplot(2,3,6); imagesc(correctedHigh); axis image off; title('meanHigh - bgHigh'); colorbar; clim([0 clim_cor]); colormap('jet');

    sgtitle(sprintf('[%s] Full Image BG Correction', fileID), 'FontWeight','bold');

    % === Save ===
    saveas(f1, fullfile(savedir, [fileID '_full_BG_correction_2D.png']));
    close(f1);

        % === Plot ===
    f2 = figure('Name','Full Image BG Correction','Position',[100 100 1400 600],'Color','w');

    subplot(2,3,1); s1=surf(meanLow); s1.EdgeColor ='none'; title('meanLow'); colorbar; zlim([0 zlim_max]); clim([0 zlim_max]); colormap('jet');
    subplot(2,3,2); s2=surf(bgLow_full); s2.EdgeColor ='none'; title('bgLow\_full'); colorbar; zlim([0 zlim_max]); clim([0 zlim_max]); colormap('jet');
    subplot(2,3,3); s3=surf(correctedLow); s3.EdgeColor ='none'; title('meanLow - bgLow'); colorbar; clim([0 clim_cor]); colormap('jet');

    subplot(2,3,4); s4=surf(meanHigh); s4.EdgeColor ='none'; title('meanHigh'); colorbar; zlim([0 zlim_max]); clim([0 zlim_max]); colormap('jet');
    subplot(2,3,5); s5=surf(bgHigh_full); s5.EdgeColor ='none'; title('bgHigh\_full'); colorbar; zlim([0 zlim_max]); clim([0 zlim_max]); colormap('jet');
    subplot(2,3,6); s6=surf(correctedHigh); s6.EdgeColor ='none'; title('meanHigh - bgHigh'); colorbar; clim([0 clim_cor]); colormap('jet');

    sgtitle(sprintf('[%s] Full Image BG Correction', fileID), 'FontWeight','bold');

    % === Save ===
    saveas(f2, fullfile(savedir, [fileID '_full_BG_correction_3D.png']));
    close(f2);
end
