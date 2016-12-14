function plotDistMap(mesh, distmap, k)
dist = distmap(:,k);
maxD = max(dist);
v = mesh.vertices;
[n, ~] = size(v);
figure; hold on;
for i=1:n
    d = dist(i) / maxD;
    rgb = hsv2rgb([d 1 1]);
    plot3(v(i,1), v(i, 2), v(i, 3), 'bx', 'color', rgb);
end
colorbar;
print('-dpng', strcat('distmap_', num2str(k), '.png'));
end