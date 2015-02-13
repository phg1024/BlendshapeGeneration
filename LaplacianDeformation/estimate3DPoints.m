function P = estimate3DPoints(L, D)
npts = size(L, 2);
z = zeros(1, npts);
for i=1:npts
    xp = L(2, i); xp = round(xp);
    yp = L(1, i); yp = round(yp);
    z(i) = D(xp, yp);               % unit: mm
end

L(1,:) = L(1,:) - 320.0;
L(2,:) = L(2,:) - 240.0;
f = 525.0;
L = L / f;
x = L(1,:) .* z;       % convert to mm
y = L(2,:) .* z;       % convert to mm
idx = find(z~=0);
plot3(x(idx), y(idx), z(idx), 'x');
axis vis3d;
P = [x; y; z];
end