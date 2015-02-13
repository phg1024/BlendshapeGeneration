function showImageAndDepth(I, D, L)
figure;imshow(I/255.0);
hold on;
plot(L(1,:), L(2,:), 'x');
hold off;

figure;imshow(D/2048.0);
hold on;
plot(L(1,:), L(2,:), 'x');
hold off;
end