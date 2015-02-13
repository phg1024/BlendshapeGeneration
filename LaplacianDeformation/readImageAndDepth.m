function [I, D, L] = readImageAndDepth(filename)
fid = fopen(filename, 'rb');
[pathstr, name, ext] = fileparts(filename);

nfrms = fread(fid, 1, 'int32');
I = fread(fid, 640*480*3, 'uint8');
D = fread(fid, 640*480, 'uint16');
fclose(fid);

I0 = reshape(I, 3, 640, 480);
I = zeros(480, 640, 3);
I(:,:,1) = reshape(I0(1,:,:), 640, 480)';
I(:,:,2) = reshape(I0(2,:,:), 640, 480)';
I(:,:,3) = reshape(I0(3,:,:), 640, 480)';
D = reshape(D, 640, 480)';

fid = fopen([pathstr, '/', name, '.', 'land'], 'r');
npts = fscanf(fid, '%d', 1);
L = fscanf(fid, '%f %f\n', [2, npts]);
L(1,:) = L(1,:) * 640;
L(2,:) = (1-L(2,:)) * 480;
end