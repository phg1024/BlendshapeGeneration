function points = samplePointsFromMesh(mesh, npoints, cutoff)

npts_perface = 3;
nfaces = npoints / npts_perface;

faces = [];
points = [];
while size(points, 1) < npoints
    fidx = randperm(size(mesh.faces, 1), 1);
    if ismember(fidx, faces)
        continue;
    else
        faces = [faces;fidx];
    end
    verts = mesh.vertices(mesh.faces(fidx,:), :);
    c = mean(verts);
    if c(3) > cutoff
        for i=1:npts_perface
            param = rand(3, 1);
            param = param / sum(param);
            points = [points; sum(verts .* repmat(param, 1, 3))];
        end
    end
end
size(points)

end