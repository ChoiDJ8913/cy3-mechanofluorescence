function [Sgnl, Bgnd] = MTView(Peaks, movie1, fileName,filePath,avgLim)
    movie1 = double(movie1);
    h = size(movie1, 1);
    w = size(movie1, 2);
    N = size(movie1, 3);

    avgFrame = mean(movie1, 3);
    % avgLim = [100, 500];

    PeakR = 5; % peak radius
    exR = PeakR + 2;

    minX = min( Peaks(:, 1) ) - exR;
    maxX = max( Peaks(:, 1) ) + exR;
    minY = min( Peaks(:, 2) ) - exR;
    maxY = max( Peaks(:, 2) ) + exR;
    NPeaks = size(Peaks, 1);
    fprintf('Total %3d Peaks \n\n', NPeaks);

    % create the output folder from the file name
    [~, nameOnly, ~] = fileparts(fileName);
    outputFolder = fullfile(filePath, [nameOnly '_Output']);
    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    % show and save the average frame
    figure(1);
    clf;
    imagesc(avgFrame, avgLim);
    title('Peaks');
    hold on;
    for i = 1:NPeaks
        DrawCircle(Peaks(i, 1), Peaks(i, 2), PeakR, true, [1, 1, 1], 1, i);
    end
    hold off;
    axis equal;
    axis( [ minX maxX minY maxY ] );
    colormap(jet(256));
    saveas(gcf, fullfile(outputFolder, 'AverageFrame.png'));

    % compute signal and background intensity
    Sgnl = zeros(NPeaks, N);
    Bgnd = zeros(NPeaks, N);

    [PX, PY] = meshgrid(-exR:exR, -exR:exR);
    PeakI = find(PX.^2 + PY.^2 <= PeakR^2);
    BgndI = find((PX.^2 + PY.^2 >= PeakR^2) & (PX.^2 + PY.^2 <= exR^2));
    for i = 1:NPeaks
        xi = round(Peaks(i, 1));
        yi = round(Peaks(i, 2));
        pkIi = h * (xi + PX(PeakI) - 1) + yi + PY(PeakI);
        bgIi = h * (xi + PX(BgndI) - 1) + yi + PY(BgndI);
        for k = 1:N
            framek = movie1(:, :, k);
            Bgnd(i, k) = mean(framek(bgIi));
            Sgnl(i, k) = mean(framek(pkIi)) - Bgnd(i, k);
        end
    end

    % visualise signal and background intensity
    figure(2);
    clf;
    % subplot(2,1,1)
    imagesc(Bgnd, [min(Bgnd(:)), max(Bgnd(:))]);
    title('Background Intensity');
    xlabel('Time (msec)');
    ylabel('Molecule');
    colorbar('EastOutside');
    colormap(jet(256));
    saveas(gcf, fullfile(outputFolder, 'BackgroundIntensity.png'));

    figure(3);
    clf;
    % subplot(2,1,2)
    imagesc(Sgnl, [min(Sgnl(:)), max(Sgnl(:))]);
    title('Signal Intensity');
    xlabel('Time (msec)');
    ylabel('Molecule');
    colorbar('EastOutside');
    colormap(jet(256));
    saveas(gcf, fullfile(outputFolder, 'SignalIntensity.png'));
    % saveas(gcf, fullfile(outputFolder, 'SignalBackgroundIntensity.png'));

    % save one plot per peak
    % cmap = colormap(hsv(NPeaks));
    for i = 1:NPeaks
        figure(4);
        clf;
        plot(1:N, Bgnd(i, :),'k','LineWidth', 1);
        hold on;
        plot(1:N, Sgnl(i, :), 'r', 'LineWidth', 1);
        hold off;
        xlabel('Time (msec)');
        ylabel('Intensity (a.u.)');
        ylim([-50 550]);
        title(sprintf('Peak %d: (%.1f, %.1f)', i, Peaks(i, 1), Peaks(i, 2)));
        saveas(gca, fullfile(outputFolder, sprintf('Peak_%03d.png', i)));
    end

    % save Fluor.mat
    save(fullfile(outputFolder, 'Fluor.mat'), 'Sgnl', 'Bgnd');

    fprintf('All graphs and data saved in folder: %s\n', outputFolder);
    dat_Sgnl = Sgnl';
    
    return;
end

function [xdata, ydata] = DrawCircle(x, y, r, flag, c, w, i)
    xdata = x + r * cos(2 * pi * (0:0.05:1));
    ydata = y + r * sin(2 * pi * (0:0.05:1));
    i = mat2str(i);
    if nargin < 4
        flag = true;
    end
    if nargin < 5
        c = [1, 1, 1];
    end
    if nargin < 6
        w = 2;
    end

    if flag
        plot(xdata, ydata, '-', 'Color', c, 'LineWidth', w);
        text(xdata(1), ydata(1),i,'Color','w');
    end
    return;
end

% function [ Sgnl, Bgnd ] = MTView(Peaks, movie1, fileName)
% movie1 = double(movie1);
% %movie1 = movie1(:, :, 40:550 );
% % movie1(:, :, 1:50 ) = []; % frames to trim
% h = size(movie1, 1);
% w = size(movie1, 2);
% N = size(movie1, 3);
% 
% %avgFrame = max(movie1, [], 3);
% avgFrame = mean( movie1, 3 );
% avgLim = [ 200 1500 ];
% 
% PeakR = 5; % peak radius
% exR = PeakR + 2;
% % load('Peaks.mat');
% NPeaks = size(Peaks, 1);
% fprintf( 'Total %3d Peaks \n\n', NPeaks ) ;
% 
% minX = min( Peaks(:, 1) ) - exR;
% maxX = max( Peaks(:, 1) ) + exR;
% minY = min( Peaks(:, 2) ) - exR;
% maxY = max( Peaks(:, 2) ) + exR;
% 
% figure(1);
% clf;
% imagesc( avgFrame, avgLim );
% title('Peaks');
% hold on;
% for i = 1:NPeaks
% 	DrawCircle( Peaks(i, 1), Peaks(i, 2), PeakR, true, [ 1 1 1 ], 1 );
% end
% hold off;
% axis equal;
% colormap(jet(256));
% axis( [ minX maxX minY maxY ] );
% 
% Sgnl = zeros( NPeaks, N );
% Bgnd = zeros( NPeaks, N );
% 
% [ PX, PY ] = meshgrid( -exR:exR, -exR:exR );
% PeakI = find( PX.^2 + PY.^2 <= PeakR^2 );
% BgndI = find( ( PX.^2 + PY.^2 >= PeakR^2 ) .* ( PX.^2 + PY.^2 <= exR^2 ) );
% for i = 1:NPeaks
% 	xi = round( Peaks(i, 1) );
% 	yi = round( Peaks(i, 2) );
% 	pkIi = h * ( xi+PX(PeakI) -1 ) + yi+PY(PeakI);
%  	bgIi = h * ( xi+PX(BgndI) -1 ) + yi+PY(BgndI);
% 	for k = 1:N
% 		framek = movie1(:, :, k);
% 		Bgnd( i, k ) = mean(framek(bgIi));
% 		Sgnl( i, k ) = mean(framek(pkIi)) - Bgnd( i, k );
% 	end
% end
% 
% save( 'Fluor.mat', 'Sgnl', 'Bgnd' );
% 
% if 0
% cmap = colormap( hsv(NPeaks) );
% figure(2);
% clf;
% hold on;
% for i = 1:NPeaks
% 	plot( 1:N, Bgnd(i, :), 'Color', cmap(i, :), 'LineWidth', 2 );
% end
% hold off;
% xlabel('Frame');
% ylabel('Background (a.u.)');
% end
% 
% sortB = sort( Bgnd(:), 'ascend' );
% BLim = [ sortB(ceil(0.05*end)) sortB(ceil(0.95*end)) ];
% figure(2);
% clf;
% imagesc( Bgnd, BLim );
% title('Background Intensity');
% %axis equal;
% xlabel( 'Frame' );
% ylabel( 'Molecule' );
% colorbar('EastOutside');
% colormap(jet(256));
% sortS = sort( Sgnl(:), 'ascend' );
% SLim = [ sortS(ceil(0.01*end)) sortS(ceil(0.99*end)) ];
% SLim = [ 0 1.5*sortS(ceil(0.9*end)) ];
% figure(3);
% clf;
% imagesc( Sgnl, SLim );
% title('Signal Intensity');
% %axis equal;
% xlabel( 'Frame' );
% ylabel( 'Molecule' );
% colorbar('EastOutside');
% colormap(jet(256));
% 
% 
% figure(1);
% hold on;
% hPeak = plot(  NaN ,  NaN , 'w', 'LineWidth', 3 );
% hold off;
% colormap(jet(256));
% 
% figure(4);
% clf;
% hold on;
% hBgnd = plot( 1:N, NaN * zeros(1, N), 'k', 'LineWidth', 2 );
% hSgnl = plot( 1:N, NaN * zeros(1, N), 'r', 'LineWidth', 2 );
% hold off;
% 
% for i = 1:NPeaks
% 	[ xdata, ydata ] = DrawCircle( Peaks(i, 1), Peaks(i, 2), exR, false );
% 	set( hPeak, 'XData', xdata, 'YData', ydata );
% 
% 	str = sprintf( 'Peaks No. [%3d/%3d] ( %.1f, %.1f ) \n', i, NPeaks, Peaks(i, 1), Peaks(i, 2) );
% 	disp(str);
% 	figure(4);
% 	title(str);
% 	set( hBgnd, 'YData', Bgnd(i, :) );
% 	set( hSgnl, 'YData', Sgnl(i, :) );
% 
% 	ans = input( 'Continue? ', 's' );
% end
% 
% 
% return;
% 
% 
% function [ xdata, ydata ] = DrawCircle(x, y, r, flag, c, w)
% xdata = x + r*cos(2*pi*(0:0.05:1));
% ydata = y + r*sin(2*pi*(0:0.05:1));
% if nargin < 4
% 	flag = true;
% end
% if nargin < 5
% 	c = [ 1 1 1 ];
% end
% if nargin < 6
% 	w = 2;
% end
% 
% if flag
% 	plot( xdata, ydata, '-', 'Color', c, 'LineWidth', w );
% end
% return;
