%% driver for generating a set of blend shapes from
% a template set: {A0, A1, ..., An}
% a target mesh: B0
% a set of training poses: {S1, S2, ..., Sm} each of which is a set of
% points

close all;
clear all;

maxNumCompThreads(6);

%% load the meshes
tic;
A_path = './Data/Tester_1/Blendshape/';
B_path = './Data/Tester_106/Blendshape/';
S_path = './Data/Tester_106/TrainingPose/';

nshapes = 46; % 46 in total (1..46), use 10 for testing
nposes = 19; % 20 in total (0..19), use 5 for testing

A = cell(nshapes+1, 1);
B = cell(nshapes+1, 1);
B_ref = cell(nshapes+1, 1);
S0 = cell(nposes, 1);   % ground truth training meshes
S = cell(nposes, 1);    % meshes reconstructed from point clouds
P = cell(nposes, 1);    % point clouds

% load the landmarks
landmarks = load('landmarks.mat');
landmarks = landmarks.landmarks + 1;

parfor i=1:nshapes+1
    A{i} = triangulateMesh(loadMesh([A_path, 'shape_', num2str(i-1), '.obj']));
    B_ref{i} = triangulateMesh(loadMesh([B_path, 'shape_', num2str(i-1), '.obj']));    
end
B{1} = B_ref{1};

A0 = A{1};
B0 = B{1};

if 0
    close all;
    for i=1:nshapes
        figure;showMesh(A{i}, ['A_', num2str(i)]);
    end
end

if 0
    close all;
    for i=1:nshapes
        figure;showMesh(B_ref{i}, ['Bref_', num2str(i)]);
    end
end

stationary_indices = find(B{1}.vertices(:,3)<-0.45);

parfor i=1:nposes
    S0{i} = triangulateMesh(loadMesh([S_path, 'pose_', num2str(i), '.obj']));
end
if 0
    close all;
    for i=1:nposes
        figure;showMesh(S0{i}, ['S0_', num2str(i)]);
    end
end
tloading = toc;
fprintf('meshes loaded in %f seconds...\n', tloading);

%% synthesize a set of training poses
synthesizeTrainingPoses = true;
if synthesizeTrainingPoses
	dB_ref = cell(nshapes, 1);
	for i=1:nshapes
		dB_ref{i} = B_ref{i+1}.vertices - B_ref{1}.vertices;
	end

	alpha_ref = cell(nposes, 1);
	parfor j=1:nposes
		fprintf('estimating for pose %d ...', j);
		alpha_ref{j} = estimateWeights(S0{j}, B0, dB_ref, zeros(1, nshapes), zeros(1, nshapes), 0.0, 10, true);
	end

	T = cell(nposes, 1);
	parfor i=1:nposes
		Ti = B0;
		for j=1:nshapes
			Ti.vertices = Ti.vertices + alpha_ref{i}(j) * dB_ref{j};
		end
		Ti = alignMesh(Ti, B0, stationary_indices);		
		T{i} = Ti;
    end
    if 0
        close all;
        for i=1:nposes
            figure;showMesh(T{i}, ['T_', num2str(i)]);
        end
    end
	% replace the training poses with T
	S0 = T;
end

% create point clouds from the training poses
fprintf('sampling point clouds ...\n');
nsamplepoints = 16384;
parfor i=1:nposes
    P{i} = samplePointsFromMesh(S0{i}, nsamplepoints, -0.25);
end
fprintf('done\n');

addpath ./LaplacianDeformation/
% use laplacian deformation to create an initial set of training mesh,
% which is used for estimating the initial set of blendshape weights
parfor i=1:nposes
    S{i} = laplacianDeformation(B0, landmarks, S0{i}.vertices(landmarks,:), P{i});
end
S_init = S;
if 1
    close all;
    for i=1:nposes
        figure;showMeshError(S0{i}, S{i}, ['Error ', num2str(i)]);
    end
end

%% transfer the deformation to get initial set of blendshapes
nfaces = size(B0.faces, 1);
nverts = size(B0.vertices, 1);

parfor j=1:nfaces
    A0grad{j} = triangleGradient(A0, j);
    B0grad{j} = triangleGradient(B0, j);
end

B_init = cell(nshapes+1, 1);
B_init{1} = B0;
parfor i=2:nshapes+1
    fprintf('transferring mesh %d ...\n', i);
    B_init{i} = deformationTransfer4(A0, A0grad, B0, B0grad, A{i}, stationary_indices);
    B_init{i} = alignMesh(B_init{i}, B0, stationary_indices);
    
    figure;showMeshError(B_init{i}, B_ref{i}, ['init error ', num2str(i)]);
    savefig(['init_error_', num2str(i), '.fig']);
    
    figure;showMeshOverlay(B_init{i}, B_ref{i}, ['init overlay ', num2str(i)]);
    savefig(['init_overlay_', num2str(i), '.fig']);
end
B = B_init;

%% compute prior
disp('computing prior...');
prior = zeros(nshapes, 9*nfaces);
MB0 = zeros(1, 9*nfaces);
MA0 = zeros(1, 9*nfaces);
for j=1:nfaces
    jstart = (j-1)*9+1; jend = j*9;
    [Bj, dj] = triangleGradient(B0, j);
    MB0(1, jstart:jend) = reshape(Bj, 1, 9);
    MA0j = triangleGradient(A0, j);
    MA0(1, jstart:jend) = reshape(MA0j, 1, 9);
end
MB0_9 = reshape(MB0, 9, nfaces);
MA0_9 = reshape(MA0, 9, nfaces);
kappa = 0.1;
w_prior = zeros(nshapes, nfaces);
parfor i=1:nshapes
    fprintf('computing prior for shape %d...\n', i);
    Ai = A{i+1};
    Pi = zeros(1, nfaces*9);
    w_prior_i = zeros(1, nfaces);
    for j=1:nfaces
        jstart = (j-1)*9+1; jend = j*9;
        MAij = triangleGradient(Ai, j);
        MA0j = reshape(MA0_9(:,j), 3, 3);
        GA0Ai = MAij/MA0j;
        MB0j = reshape(MB0_9(:,j), 3, 3);
        Pij = GA0Ai * MB0j - MB0j;
        MAij_norm = norm(MAij-MA0j);
        w_prior_i(1,j) = (1+MAij_norm)/(kappa+MAij_norm);
        Pi(1,jstart:jend) = reshape(Pij, 1, 9);
    end
    w_prior(i,:) = w_prior_i;
    prior(i,:) = Pi;
end
disp('done.');

% compute delta shapes
dB = cell(nshapes, 1);
for i=1:nshapes
    dB{i} = B{i+1}.vertices - B0.vertices;
end

%% estimate initial blendshape parameters
alpha_init = cell(nposes, 1);
parfor j=1:nposes
    fprintf('estimating for pose %d ...', j);
    alpha_init{j} = estimateWeights(S{j}, B0, dB, zeros(1, nshapes), 0.0, 5, true);
end

% initialization done
return;

B = B_init;
S = S_init;
alpha = alpha_init;

% iters_outerloop = 1;
% MAXITERS_OUTERLOOP = 5;
% while iters_outerloop < MAXITERS_OUTERLOOP
%     fprintf('outer loop iteration %d\n', iters_outerloop);
%     iters_outerloop = iters_outerloop + 1;
    % compute deformation gradients for S
    Sgrad = cell(nfaces, 1);
    parfor j=1:nfaces
        Smat = zeros(nposes, 9);
        for i=1:nposes
            Sij = triangleGradient(S{i}, j);
            Smat(i,:) = reshape(Sij, 1, 9);
        end
        Sgrad{j} = Smat;
    end
    
    %% refine blendshapes as well as blendshape weights
    converged = false;
    ALPHA_THRES = 1e-6;
    B_THRES = 1e-6;
    beta_max = 0.5; beta_min = 0.1;
    gamma_max = 0.01; gamma_min = 0.01;
    eta_max = 10.0; eta_min = 1.0;
    iters = 0; maxIters = 10;
    B_error = zeros(maxIters, nshapes);
    S_error = zeros(maxIters, nposes);
    while ~converged && iters < maxIters
        fprintf('iteration %d ...\n', iters);
        converged = true;
        iters = iters + 1;
        
        % refine blendshapes
        beta = sqrt(iters/maxIters) * (beta_min - beta_max) + beta_max;
        gamma = gamma_max + iters/maxIters*(gamma_min-gamma_max);
        eta = eta_max + iters/maxIters*(eta_min-eta_max);
        B_new = refineBlendShapes(S, Sgrad, B, alpha, beta, gamma, prior, w_prior, stationary_indices);
        B_norm = zeros(1, nshapes);
        for i=1:nshapes
            B_norm(i) = norm(B{i+1}.vertices-B_new{i}, 2);
            B{i+1}.vertices = B_new{i};
            B_error(iters, i) = sqrt(max(sum((B{i+1}.vertices-B_ref{i+1}.vertices).^2, 2)));
            B{i+1} = alignMesh(B{i+1}, B{1}, stationary_indices);
        end
        fprintf('max(B_error) = %.6f\n', max(B_error(iters, :)));
        converged = converged & (max(B_norm) < B_THRES);
        
        if 0
            close all;
            % compare the new blendshapes with the reference
            for i=1:nshapes
                figure;showMeshError(B{i+1}, B_ref{i+1}, ['error ', num2str(i)]);
                savefig(['error_', num2str(i), '.fig']);close;
                figure;showMeshOverlay(B{i+1}, B_ref{i+1}, ['overlay', num2str(i)]);
                savefig(['overlay_', num2str(i), '.fig']);close;
                figure;
                subplot(1, 2, 1);showMeshError(B{i+1}, B_ref{i+1}, ['error ', num2str(i)]);
                subplot(1, 2, 2);showMeshOverlay(B{i+1}, B_ref{i+1}, ['overlay ', num2str(i)]);
            end
        end
        
        % update delta shapes
        for i=1:nshapes
            dB{i} = B{i+1}.vertices - B0.vertices;
        end
        
        % update weights
        alpha_new = cell(nposes, 1);
        parfor j=1:nposes
            alpha_new{j} = estimateWeights(S{j}, B0, dB, alpha{j}, alpha_ref{j}, eta, 2);
            %alpha_new{j} = estimateWeights(S{j}, B0, dB, zeros(1, nshapes), 5);
        end
        alpha_norm = norm(cell2mat(alpha) - cell2mat(alpha_new));
        disp(alpha_norm);
        alpha = alpha_new;
        converged = converged & (alpha_norm < ALPHA_THRES);
        
        for i=1:nposes
            Ti = B0;
            for j=1:nshapes
                Ti.vertices = Ti.vertices + alpha{i}(j) * dB{j};
            end
            %Ti = alignMesh(Ti, S0{i});
            S_error(iters, i) = sqrt(max(sum((Ti.vertices-S0{i}.vertices).^2, 2)));
            
            % update the reconstructed mesh
            S{i} = Ti;
        end
        fprintf('Emax = %.6f\tEmean = %.6f\n', max(S_error(iters,:)), mean(S_error(iters,:)));
        
        
        % The reconstructed mesh are updated using the new set of blendshape
        % weights, need to use laplacian deformation to refine them again
        parfor i=1:nposes
            S{i} = laplacianDeformation(S{i}, landmarks, S0{i}.vertices(landmarks,:), P{i}, 1);
        end
        % compute deformation gradients for S
        Sgrad = cell(nfaces, 1);
        parfor j=1:nfaces
            Smat = zeros(nposes, 9);
            for i=1:nposes
                Sij = triangleGradient(S{i}, j);
                Smat(i,:) = reshape(Sij, 1, 9);
            end
            Sgrad{j} = Smat;
        end
    end
    
%     % The reconstructed mesh are updated using the new set of blendshape
%     % weights, need to use laplacian deformation to refine them again
%     parfor i=1:nposes
%         S{i} = laplacianDeformation(S{i}, landmarks, S0{i}.vertices(landmarks,:), P{i});
%     end    
% end

plotLines(S_error, 'iteration', 'S error', 'pose id', 'error', [1.0, ones(1,8)*0.5, 1.0]);
plotLines(B_error, 'iteration', 'B error', 'blendshape id', 'error', [1.0, ones(1,8)*0.5, 1.0]);
figure;imagesc(S_error);title('S error');
figure;imagesc(B_error);title('B error');

% compare the weights
figure;plot(cell2mat(alpha)');
figure;plot(cell2mat(alpha_init)');
figure;plot(cell2mat(alpha_ref)');

return;


% the error between initial blendshapes with the reference
close all;
for i=1:nshapes
    figure;
    subplot(1, 2, 1);showMeshOverlay(B_init{i+1}, B_ref{i+1}, ['overlay', num2str(i)]);
    subplot(1, 2, 2);showMeshError(B_init{i+1}, B_ref{i+1}, ['error', num2str(i)]);
    set(gcf,'units','normalized','outerposition',[0 0 1 1])    
    savefig(['comp_init_ref_', num2str(i), '.fig']);
    print('-dpng','-r600',['comp_init_ref_', num2str(i)]);    
end

% the error between the refined blendshapes
close all;
for i=1:nshapes
    figure;
    subplot(1, 2, 1);showMeshOverlay(B{i+1}, B_ref{i+1}, ['overlay', num2str(i)]);
    subplot(1, 2, 2);showMeshError(B{i+1}, B_ref{i+1}, ['error', num2str(i)]);
    set(gcf,'units','normalized','outerposition',[0 0 1 1])    
    savefig(['comp_refined_ref_', num2str(i), '.fig']);
    print('-dpng','-r600',['comp_refined_ref_', num2str(i)]);      
end

% compare the new blendshapes with the reference
for i=1:nshapes
    figure;
    subplot(1, 3, 1);showMesh(B_init{i+1}, ['initial shape ', num2str(i)]);
    subplot(1, 3, 2);showMesh(B{i+1}, ['refined shape ', num2str(i)]);
    subplot(1, 3, 3);showMesh(B_ref{i+1}, ['reference shape ', num2str(i)]);
    set(gcf,'units','normalized','outerposition',[0 0 1 1])    
    savefig(['comp_', num2str(i), '.fig']);
    print('-dpng','-r600',['comp_', num2str(i)]);
end

for i=1:nshapes+1
    figure;showMesh(A{i}, ['template shape ', num2str(i-1)], true);close;
end

figure;
for i=1:nshapes+1
    subplot(6, 8, i); showMesh(A{i}, [num2str(i-1)]);
end

figure;
for i=1:nshapes+1
    subplot(6, 8, i); showMesh(B{i}, [num2str(i-1)]);
end

figure;
for i=1:nshapes+1
    subplot(6, 8, i); showMesh(B_init{i}, [num2str(i-1)]);
end


figure;
for i=1:nshapes+1
    subplot(6, 8, i); showMesh(B_ref{i}, [num2str(i-1)]);
end

figure;
for i=1:nposes
    subplot(3, 7, i); showMesh(S{i}, [num2str(i)]);
end

for i=1:nshapes+1
    figure;showMesh(B_init{i}, ['initial shape ', num2str(i-1)], true);close;
end
for i=1:nshapes+1
    figure;showMesh(B{i}, ['refined shape ', num2str(i-1)], true);close;
end
for i=1:nshapes+1
    figure;showMesh(B_ref{i}, ['reference shape ', num2str(i-1)], true);close;
end

return;

%% show the fitting error
B_set = {B, B_init, B_ref};
S_set = {};
alpha_set = {};
Fnames = {'refined_fit', 'init_fit', 'ref_fit'};
for fid = 1:numel(B_set)
    B_cur = B_set{fid};
    % update delta shapes
    for i=1:nshapes
        dB{i} = B_cur{i+1}.vertices - B0.vertices;
    end
    
    alpha_new = cell(nposes, 1);
    parfor j=1:nposes
        alpha_new{j} = estimateWeights(S{j}, B0, dB, zeros(1, nshapes), zeros(1, nshapes), 0.001, 10);
    end
    alpha_set{fid} = alpha_new;
    
    S_set{fid} = {};
    for i=1:nposes
        Ti = B0;
        for j=1:nshapes
            Ti.vertices = Ti.vertices + alpha_new{i}(j) * dB{j};
        end
        S_set{fid}{i} = Ti;
        %Ti = alignMesh(Ti, S{i}, stationary_indices);
        S_error_max(fid, i) = sqrt(max(sum((Ti.vertices-S{i}.vertices).^2, 2)));
        S_error_mean(fid, i) = sqrt(mean(sum((Ti.vertices-S{i}.vertices).^2, 2)));
        if 0
            figure;
            subplot(1, 2, 1);showMeshOverlay(Ti, S{i}, 'overlay');
            subplot(1, 2, 2);showMeshError(Ti, S{i}, 'error', [0.075, 0]);
            set(gcf,'units','normalized','outerposition',[0 0 1 1])
            savefig([Fnames{fid}, '_pose_', num2str(i), '.fig']);
            print('-dpng','-r300',[Fnames{fid}, '_pose_', num2str(i)])
        end
    end
end

B_error_mean = zeros(3, nshapes);
B_error_max = zeros(3, nshapes);
for fid = 1:numel(B_set)
    B_cur = B_set{fid};
    for j=2:nshapes+1
        B_error_vec = sqrt(sum((B_cur{j}.vertices - B_ref{j}.vertices).^2, 2));
        B_error_mean(fid, j) = mean(B_error_vec);
        B_error_max(fid, j) = max(B_error_vec);
    end
end

figure;plot(S_error_mean');legend('refined', 'init', 'ref');title('Comparison of mean error');xlabel('pose id');ylabel('error');
figure;plot(S_error_max');legend('refined', 'init', 'ref');title('Comparison of max error');xlabel('pose id');ylabel('error');

figure;plot(B_error_mean');legend('refined', 'init');title('Comparison of mean error');xlabel('blendshape id');ylabel('error');
figure;plot(B_error_max');legend('refined', 'init');title('Comparison of max error');xlabel('blendshape id');ylabel('error');

return;

%% plot the weights
close all;
fighandle = figure;
for i=1:nposes
    subplot(5, 4, i);
    hold on;
    plot(alpha_set{1}{i}, 'r');
    plot(alpha_set{2}{i}, 'g');
    plot(alpha_set{3}{i}, 'b');
	plot(alpha_ref{i}, 'k');
    title(['pose ', num2str(i)]);
    %set(fighandle, 'Position', [100, 100, 800, 256]);
    %print('-dpng','-r300',['weights_', num2str(i)]);
end
legend('refined', 'init', 'ref', 'ground truth');

%% plot the reconstructed meshes
close all;
for fid=1:3
	figure;
	T = S_set{fid};
	for i=1:nposes
		subplot(3, 7, i); showMesh(T{i}, [num2str(i)]);
	end
end

close all;
for fid=1:3
	figure;
	T = B_set{fid};
	for i=2:nshapes+1
		subplot(6, 8, i-1); showMeshError(T{i}, B_ref{i}, [num2str(i-1)], [0.05, 0], false);
	end
	h = colorbar;
	colormap jet(256);
	caxis([0 0.05]);
	set(h, 'Position', [.9314 .11 .0181 .8150])
end

close all;
for fid=1:3
	figure;
	T = S_set{fid};
	for i=1:nposes
		subplot(3, 7, i); showMeshError(T{i}, S{i}, [num2str(i)], [0.05, 0], false);
	end
	h = colorbar;
	colormap jet(256);
	caxis([0 0.05]);
	set(h, 'Position', [.9314 .11 .0181 .8150])
end