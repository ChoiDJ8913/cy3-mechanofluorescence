%% cy3_panel_B_fig3.m
clear; clc;

T = readtable('5ns4_xyz.xlsx','VariableNamingRule','preserve');
T.Properties.VariableNames = {'cy3','atom','x','y','z'};
xyz     = [T.x, T.y, T.z];
n       = size(xyz,1);
atomStr = string(T.atom);

% distance-based bonds (1.0-1.65 A) - all atoms used
D = squareform(pdist(xyz));
[r,c] = find(D > 1.0 & D < 1.65 & tril(ones(n),-1));

iCAZ = find(atomStr == "CAZ");
iCBA = find(atomStr == "CBA");

%% Figure
fig = figure('Color','w');
fig.Units='centimeters'; fig.Position=[2 2 8.5 7.5];
ax = axes('Parent',fig);
hold(ax,'on'); grid(ax,'on'); box(ax,'on'); axis(ax,'equal');
view(ax,-37.5,30);

% bonds
for k = 1:numel(r)
    plot3(ax,[xyz(r(k),1) xyz(c(k),1)], ...
             [xyz(r(k),2) xyz(c(k),2)], ...
             [xyz(r(k),3) xyz(c(k),3)], ...
        '-','Color',[0.55 0.55 0.55],'LineWidth',1.0,'HandleVisibility','off');
end

% atoms
scatter3(ax,xyz(:,1),xyz(:,2),xyz(:,3),20,'o', ...
    'MarkerFaceColor',[0.40 0.40 0.40],'MarkerEdgeColor',[0.40 0.40 0.40], ...
    'HandleVisibility','off');

% CAZ-CBA dashed green
col_cc = [0.18 0.63 0.18];
plot3(ax,[xyz(iCAZ,1) xyz(iCBA,1)],[xyz(iCAZ,2) xyz(iCBA,2)],[xyz(iCAZ,3) xyz(iCBA,3)], ...
    '--','Color',col_cc,'LineWidth',1.8,'HandleVisibility','off');
scatter3(ax,xyz(iCAZ,1),xyz(iCAZ,2),xyz(iCAZ,3),80,'o', ...
    'MarkerFaceColor',col_cc,'MarkerEdgeColor',col_cc,'HandleVisibility','off');
scatter3(ax,xyz(iCBA,1),xyz(iCBA,2),xyz(iCBA,3),80,'o', ...
    'MarkerFaceColor',col_cc,'MarkerEdgeColor',col_cc,'HandleVisibility','off');

% C labels
text(ax,xyz(iCAZ,1)+0.2,xyz(iCAZ,2),xyz(iCAZ,3)+0.4,'C', ...
    'FontName','Arial','FontSize',8,'FontWeight','bold','Color',col_cc);
text(ax,xyz(iCBA,1)-0.5,xyz(iCBA,2),xyz(iCBA,3)-0.4,'C', ...
    'FontName','Arial','FontSize',8,'FontWeight','bold','Color',col_cc);

% formatting
xlabel(ax,'X (Å)','FontName','Arial','FontSize',7);
ylabel(ax,'Y (Å)','FontName','Arial','FontSize',7);
zlabel(ax,'Z (Å)','FontName','Arial','FontSize',7);
ax.FontName='Arial'; ax.FontSize=7; ax.LineWidth=0.75;

annotation(fig,'textbox',[0.01 0.91 0.07 0.08],'String','B', ...
    'FontName','Arial','FontSize',10,'FontWeight','bold', ...
    'EdgeColor','none','FitBoxToText','on');

hold(ax,'off');
rotate3d(ax,'on');

exportgraphics(fig,'fig3_panelB.pdf','ContentType','vector');
exportgraphics(fig,'fig3_panelB.png','Resolution',600);