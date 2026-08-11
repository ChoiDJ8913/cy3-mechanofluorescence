% function set_avr_std=ana_MT_avr()
clear;close all
%%
[fileName, pathName] = uigetfile('*.mat');
fullPath = fullfile(pathName, fileName);
disp(fullPath)
S = load(fullPath);

% peak_sample = inputdlg('Peak sample',...
%     'Peak sample', [1 20],{'1'});
% peak_sample = str2double(peak_sample);

% create the output folder from the file name
[~, nameOnly, ~] = fileparts(fileName);
outputFolder = fullfile(pathName, [nameOnly '_Output']);
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

S1 = S.Sgnl;

S1 = S1';

%% 3 step down 800frame
% step_fix = {Target(1:145), Target(156:295), Target(306:445), Target(456:591)};
% avr_step_fix = [mean(step_fix{:,1}), mean(step_fix{:,2}), mean(step_fix{:,3}), mean(step_fix{:,4})];
% std_step_fix = [std(step_fix{:,1}), std(step_fix{:,2}), std(step_fix{:,3}), std(step_fix{:,4})];
% 
% step_down = {Target(146:156), Target(296:305), Target(446:455), Target(592:600)};
% avr_step_down = [mean(step_down{:,1}), mean(step_down{:,2}), mean(step_down{:,3}), mean(step_down{:,4})];
% std_step_down = [std(step_down{:,1}), std(step_down{:,2}), std(step_down{:,3}), std(step_down{:,4})];


% set_avr_std = [avr_step_fix, avr_step_down, std_step_fix, std_step_down];
% save(fullfile(outputFolder,sprintf('Peak_%03d.dat', i)),"set_avr_std","-ascii");
% %% stepping up & down
% for i = 1:size(S1,2)
% 
%     Target = S1(:,i);
%     steps = {Target(1:100), Target(101:200), Target(201:300), Target(301:400), Target(401:500), Target(501:600), ...
%         Target(601:700), Target(701:800)};
%     avr_steps = [mean(steps{:,1}), mean(steps{:,2}), mean(steps{:,3}), mean(steps{:,4}), ...
%         mean(steps{:,5}), mean(steps{:,6}), mean(steps{:,7}), mean(steps{:,8})];
%     std_step = [std(steps{:,1}), std(steps{:,2}), std(steps{:,3}), std(steps{:,4}), ...
%         std(steps{:,5}), std(steps{:,6}), std(steps{:,7}), std(steps{:,8})];
%     set_avr_std = [avr_steps, std_step];
%     save(fullfile(outputFolder,sprintf('Peak_%03d_raw.dat', i)),"Target","-ascii");
%     save(fullfile(outputFolder,sprintf('Peak_%03d.dat', i)),"set_avr_std","-ascii");
% 
%     figure;
%     p = plot(Target,"w");
%     hold on
%     s1 = plot(p.XData(1:100),Target(1:100),"k");
%     s2 = plot(p.XData(101:200),Target(101:200), "r");
%     s3 = plot(p.XData(201:300),Target(201:300));
%     s3.Color = "#EDB120";
%     s4 = plot(p.XData(301:400),Target(301:400));
%     s5 = plot(p.XData(401:500),Target(401:500));
%     s5.Color = "#0072BD";
%     s6 = plot(p.XData(501:600),Target(501:600));
%     s6.Color = "#77AC30";
%     s7 = plot(p.XData(601:700),Target(601:700));
%     s7.Color = "#EDB120";
%     s8 = plot(p.XData(701:800),Target(701:800),'r');
%     ylim([-50 250]);
%     xlabel('Frame');
%     ylabel('Intensity');
%     close gcf
%     saveas(gcf,fullfile(outputFolder, sprintf('Peak_%03d.png', i)));
% end

%% stepping up & down 600frame
% for i = 1:size(S1,2)
% 
%     Target = S1(:,i);
%     steps = {Target(1:90), Target(110:190), Target(210:290), Target(310:390), Target(410:490), Target(510:end)};
%     avr_steps = [mean(steps{:,1}), mean(steps{:,2}), mean(steps{:,3}), mean(steps{:,4}), ...
%         mean(steps{:,5}), mean(steps{:,6})];
%     std_step = [std(steps{:,1}), std(steps{:,2}), std(steps{:,3}), std(steps{:,4}), ...
%         std(steps{:,5}), std(steps{:,6})];
%     set_avr_std = [avr_steps, std_step];
%     save(fullfile(outputFolder,sprintf('Peak_%03d_raw.dat', i)),"Target","-ascii");
%     save(fullfile(outputFolder,sprintf('Peak_%03d.dat', i)),"set_avr_std","-ascii");
% 
%     figure;
%     p = plot(Target,"w");
%     hold on
%     s1 = plot(p.XData(1:100),Target(1:100),"k");
%     s2 = plot(p.XData(100:200),Target(100:200), "r");
%     s3 = plot(p.XData(200:300),Target(200:300));
%     s3.Color = "#EDB120";
%     s4 = plot(p.XData(300:400),Target(300:400));
%     s5 = plot(p.XData(400:500),Target(400:500));
%     s5.Color = "#0072BD";
%     s6 = plot(p.XData(500:600),Target(500:600));
%     s6.Color = "#77AC30";
%     ylim([-30 350]);
%     xlabel('Frame');
%     ylabel('Intensity');
%     hold off
%     % close gcf
%     saveas(gcf,fullfile(outputFolder, sprintf('Peak_%03d.png', i)));
% end

%% % progressive magnet down 600frame
% for i = 1:size(S1,2)
% 
%     Target = S1(:,i);
%     steps = {Target(1:42), Target(51:92), Target(101:142), Target(151:192), Target(201:242), Target(251:292)...
%         , Target(301:342), Target(351:392), Target(401:442), Target(451:492), Target(501:542), Target(551:600)};
%     avr_steps = [mean(steps{:,1}), mean(steps{:,2}), mean(steps{:,3}), mean(steps{:,4}), ...
%         mean(steps{:,5}), mean(steps{:,6}), mean(steps{:,7}), mean(steps{:,8}), mean(steps{:,9})...
%         , mean(steps{:,10}), mean(steps{:,11}), mean(steps{:,12})];
%     std_step = [std(steps{:,1}), std(steps{:,2}), std(steps{:,3}), std(steps{:,4}), ...
%         std(steps{:,5}), std(steps{:,6}), std(steps{:,7}), std(steps{:,8}), std(steps{:,9})...
%         , std(steps{:,10}), std(steps{:,11}), std(steps{:,12})];
%     set_avr_std = [avr_steps, std_step];
%     save(fullfile(outputFolder,sprintf('Peak_%03d_raw.dat', i)),"Target","-ascii");
%     save(fullfile(outputFolder,sprintf('Peak_%03d.dat', i)),"set_avr_std","-ascii");
% 
%     figure;
%     p = plot(Target,"w");
%     hold on
%     s1 = plot(p.XData(1:50),Target(1:50),"k");
%     s2 = plot(p.XData(51:100),Target(51:100), "r");
%     s3 = plot(p.XData(101:150),Target(101:150));
%     s3.Color = "#EDB120";
%     s4 = plot(p.XData(151:200),Target(151:200));
%     s5 = plot(p.XData(201:250),Target(201:250));
%     s5.Color = "#0072BD";
%     s6 = plot(p.XData(251:300),Target(251:300));
%     s6.Color = "#77AC30";
%     s1 = plot(p.XData(301:350),Target(301:350),"k");
%     s2 = plot(p.XData(351:400),Target(351:400), "r");
%     s3 = plot(p.XData(401:450),Target(401:450));
%     s3.Color = "#EDB120";
%     s4 = plot(p.XData(451:500),Target(451:500));
%     s5 = plot(p.XData(501:550),Target(501:550));
%     s5.Color = "#0072BD";
%     s6 = plot(p.XData(551:600),Target(551:600));
%     s6.Color = "#77AC30";
%     ylim([-10 200]);
%     xlabel('Frame');
%     ylabel('Intensity');
% 
%     saveas(gcf,fullfile(outputFolder, sprintf('Peak_%03d.png', i)));
% end
% 

%% progressive magnet down 800frame
for i = 1:size(S1,2)

    Target = S1(:,i);
    steps = {Target(1:92), Target(105:192), Target(201:292), Target(301:392), Target(401:492), Target(501:592)...
        , Target(601:692), Target(701:end)};
    avr_steps = [mean(steps{:,1}), mean(steps{:,2}), mean(steps{:,3}), mean(steps{:,4}), ...
        mean(steps{:,5}), mean(steps{:,6}), mean(steps{:,7}), mean(steps{:,8})];
    std_step = [std(steps{:,1}), std(steps{:,2}), std(steps{:,3}), std(steps{:,4}), ...
        std(steps{:,5}), std(steps{:,6}), std(steps{:,7}), std(steps{:,8})];
    set_avr_std = [avr_steps, std_step];
    save(fullfile(outputFolder,sprintf('Peak_%03d_raw.dat', i)),"Target","-ascii");
    save(fullfile(outputFolder,sprintf('Peak_%03d.dat', i)),"set_avr_std","-ascii");

    figure;
    p = plot(Target,"w");
    hold on
    s1 = plot(p.XData(1:100),Target(1:100),"k");
    s2 = plot(p.XData(101:200),Target(101:200), "r");
    s3 = plot(p.XData(201:300),Target(201:300));
    s3.Color = "#EDB120";
    s4 = plot(p.XData(301:400),Target(301:400));
    s5 = plot(p.XData(401:500),Target(401:500));
    s5.Color = "#0072BD";
    s6 = plot(p.XData(501:600),Target(501:600));
    s6.Color = "#77AC30";
    s7 = plot(p.XData(601:700),Target(601:700),"b");
    s8 = plot(p.XData(701:800),Target(701:800), "k");
    ylim([-10 200]);
    xlabel('Frame');
    ylabel('Intensity');

    saveas(gcf,fullfile(outputFolder, sprintf('Peak_%03d.png', i)));
end

%% progressive magnet down 900frame
% for i = 1:size(S1,2)
% 
%     Target = S1(:,i);
%     steps = {Target(1:92), Target(111:192), Target(211:292), Target(311:392), Target(411:492), Target(511:592)...
%         , Target(615:687), Target(711:787), Target(811:end)};
%     avr_steps = [mean(steps{:,1}), mean(steps{:,2}), mean(steps{:,3}), mean(steps{:,4}), ...
%         mean(steps{:,5}), mean(steps{:,6}), mean(steps{:,7}), mean(steps{:,8}), mean(steps{:,9})];
%     std_step = [std(steps{:,1}), std(steps{:,2}), std(steps{:,3}), std(steps{:,4}), ...
%         std(steps{:,5}), std(steps{:,6}), std(steps{:,7}), std(steps{:,8}), std(steps{:,9})];
%     set_avr_std = [avr_steps, std_step];
%     save(fullfile(outputFolder,sprintf('Peak_%03d_raw.dat', i)),"Target","-ascii");
%     save(fullfile(outputFolder,sprintf('Peak_%03d.dat', i)),"set_avr_std","-ascii");
% 
%     figure;
%     p = plot(Target,"w");
%     hold on
%     s1 = plot(p.XData(1:100),Target(1:100),"k");
%     s2 = plot(p.XData(101:200),Target(101:200), "r");
%     s3 = plot(p.XData(201:300),Target(201:300));
%     s3.Color = "#EDB120";
%     s4 = plot(p.XData(301:400),Target(301:400));
%     s5 = plot(p.XData(401:500),Target(401:500));
%     s5.Color = "#0072BD";
%     s6 = plot(p.XData(501:600),Target(501:600));
%     s6.Color = "#77AC30";
%     s7 = plot(p.XData(601:700),Target(601:700),"b");
%     s8 = plot(p.XData(701:800),Target(701:800), "m");
%     s9 = plot(p.XData(801:end),Target(801:end), "k");
%     ylim([-10 200]);
%     xlabel('Frame');
%     ylabel('Intensity');
% 
%     saveas(gcf,fullfile(outputFolder, sprintf('Peak_%03d.png', i)));
% end