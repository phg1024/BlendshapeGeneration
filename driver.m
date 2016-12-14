%% driver file
close all;
ttotal = tic;
if 1
    S0_path = './Data/Tester_1/Blendshape/shape_0.obj';
    S1_path = './Data/Tester_1/Blendshape/shape_22.obj';
    T0_path = './Data/Tester_106/Blendshape/shape_0.obj';
    T1_path = './Data/Tester_106/Blendshape/shape_22.obj';
else
    S0_path = 'horse-poses/horse-01.obj';
    S1_path = 'horse-poses/horse-03.obj';
    T0_path = S0_path;
    T1_path = S1_path;
end

S0 = triangulateMesh(loadMesh(S0_path));
S1 = triangulateMesh(loadMesh(S1_path));
T0 = triangulateMesh(loadMesh(T0_path));
T1 = triangulateMesh(loadMesh(T1_path));

doTransfer;
toc(ttotal)