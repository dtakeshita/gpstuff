function [gp_array, P_TH, th, Ef, Varf, pf, ff, H] = gp_ia(gp, x, y, varargin)
%GP_IA Integration approximation with grid, Monte Carlo or CCD integration
%
%  Description
%    [GP_ARRAY, P_TH, EF, VARF, PF, FF] = GP_IA(GP, X, Y, XT, OPTIONS)
%    takes a GP data structure GP with covariates X and
%    observations Y and returns an array of GPs GP_ARRAY and
%    corresponding weights P_TH. If optional test covariates XT is
%    included, GP_IA also returns corresponding mean EF, variance
%    VARF and density PF evaluated at points FF.
%
%    OPTIONS is optional parameter-value pair
%      int_method - the method used for integration
%                    'CCD' for circular composite design (default)
%                    'grid' for grid search along principal axes
%                    'is_normal' for importance sampling using Gaussian
%                      approximation at the mode
%                    'is_t'for importance sampling using Student's t
%                     approximation at the mode
%                    'hmc' for hybrid Monte Carlo sampling (started at the
%                    mode)
%       validate  - perform some checks to investigate approximation error.
%                   1 gives warning only if necessary, 2 gives more details
%       predcf    - index vector telling which covariance functions are
%                   used for prediction. Default is all (1:gpcfn). See
%                   GP_PRED for additional information.
%       tstind    - a vector defining, which rows of X belong to which
%                   training block in *IC type sparse models. Deafult is [].
%      Following options are specific to some methods
%       rotate    - tells whether CCD and grid method first rotate the
%                   parameter space according to Hessian at the mode.
%                   Default is TRUE.
%       autoscale - tells whether automatic scaling is used in CCD and is_*
%                   Default is TRUE.
%       threshold - threshold for drop of log-density in grid search.
%                   Default is 2.5,
%       step_size - step-size for grid search. Default is 1.
%       nsamples  - number of samples for IS and MCMC methods.
%                   Default is 40.
%       t_nu      - degrees of freedom for Student's t-distribution.
%                   Default is 4.
%       qmc         tells whether quasi Monte Carlo samples are used in
%                   importance sampling. Default is TRUE.
%       optimf    - function handle for an optimization function,
%                   which is assumed to have similar input and
%                   output arguments as usual fmin*-functions. 
%                   Default is @fminscg.
%       opt_optim - options structure for the minimization function. 
%                   Use optimset to set these options. By default
%                   options 'GradObj' is 'on', 'LargeScale' is
%                   'off' and 'Display' is 'off'.
%       opt_hmc   - option structure for HMC2 sampling (Default is [])
%       persistence_reset 
%                 - reset the momentum parameter in HMC sampler after 
%                   every repeat'th iteration, default 0.
%       repeat    - number of subiterations in HMC.
%                   Default is 10.
%       display   - defines if information is printed, 1=yes, 0=no.
%                   Default 1.
%       

% Copyright (c) 2009-2010 Ville Pietil�inen, Jarno Vanhatalo
% Copyright (c) 2010 Aki Vehtari

% This software is distributed under the GNU General Public
% Licence (version 2 or later); please refer to the file
% Licence.txt, included with the software, for details.

  ip=inputParser;
  ip.FunctionName = 'GP_IA';
  ip.addRequired('gp', @isstruct);
  ip.addRequired('x', @(x) ~isempty(x) && isreal(x) && all(isfinite(x(:))))
  ip.addRequired('y', @(x) ~isempty(x) && isreal(x) && all(isfinite(x(:))))
  ip.addOptional('xt',[], @(x) isreal(x) && all(isfinite(x(:))))
  ip.addParamValue('yt', [], @(x) isreal(x) && all(isfinite(x(:))))
  ip.addParamValue('z', [], @(x) isreal(x) && all(isfinite(x(:))))
  ip.addParamValue('int_method', 'CCD', @(x) ischar(x) && ...
                   ismember(x,{'CCD','grid','is_normal','is_t','hmc'}))
  ip.addParamValue('predcf', [], @(x) isempty(x) || ...
                   isvector(x) && isreal(x) && all(isfinite(x)&x>0))
  ip.addParamValue('tstind', [], @(x) isempty(x) || ...
                   isvector(x) && isreal(x) && all(isfinite(x)&x>0))
  ip.addParamValue('rotate', true, @(x) islogical(x) && isscalar(x))
  ip.addParamValue('autoscale', true, @(x) islogical(x) && isscalar(x))
  ip.addParamValue('validate', 1, @(x) ismember(x,[1 2]))
  ip.addParamValue('threshold', 2.5, @(x) isscalar(x) && isreal(x) && ...
                   isfinite(x) && x>0)
  ip.addParamValue('step_size', 1, @(x) isscalar(x) && isreal(x) && ...
                   isfinite(x) && x>0)
  ip.addParamValue('t_nu', 4, @(x) isscalar(x) && isreal(x) && ...
                   isfinite(x) && x>=1)
  ip.addParamValue('nsamples', 40, @(x) isscalar(x) && isreal(x) && ...
                   isfinite(x) && x>=1)
  ip.addParamValue('repeat', 10, @(x) isscalar(x) && isreal(x) && ...
                   isfinite(x) && x>=1)
  ip.addParamValue('f0', 1.3, @(x) isscalar(x) && isreal(x) && ...
                   isfinite(x) && x>0)
  ip.addParamValue('qmc', true, @(x) islogical(x) && isscalar(x))
  ip.addParamValue('optimf', @fminscg, @(x) isa(x,'function_handle'))
  ip.addParamValue('opt_optim', [], @isstruct)
  ip.addParamValue('opt_hmc', [], @isstruct);
  ip.addParamValue('persistence_reset', 0, @(x) ~isempty(x) && isreal(x));
  ip.addParamValue('display', 1, @(x) isreal(x) && all(isfinite(x(:))))
  ip.parse(gp, x, y, varargin{:});
  xt=ip.Results.xt;
  % integration parameters
  int_method=ip.Results.int_method;
  opt.rotate=ip.Results.rotate;
  opt.autoscale=ip.Results.autoscale;
  opt.validate=ip.Results.validate;
  opt.threshold=ip.Results.threshold;
  opt.step_size=ip.Results.step_size;
  opt.t_nu=ip.Results.t_nu;
  opt.nsamples=ip.Results.nsamples;
  opt.f0=ip.Results.f0;
  opt.qmc=ip.Results.qmc;
  % optimisation and sampling parameters
  optimf=ip.Results.optimf;
  opt_optim=ip.Results.opt_optim;
  opt_hmc=ip.Results.opt_hmc;
  opt.persistence_reset=ip.Results.persistence_reset;
  opt.repeat=ip.Results.repeat;
  opt.display=ip.Results.display;
  % pass these forward
  options=struct();
  if ~isempty(ip.Results.yt);options.yt=ip.Results.yt;end
  if ~isempty(ip.Results.z);options.z=ip.Results.z;end
  if ~isempty(ip.Results.predcf);options.predcf=ip.Results.predcf;end
  if ~isempty(ip.Results.tstind);options.tstind=ip.Results.tstind;end

  % ===========================
  % Which latent method is used
  % ===========================
  if isfield(gp, 'latent_method')
    switch gp.latent_method
      case 'EP'
        fh_e = @gpep_e;
        fh_g = @gpep_g;
        fh_p = @ep_pred;
      case 'Laplace'
        fh_e = @gpla_e;
        fh_g = @gpla_g;
        fh_p = @la_pred;
    end
  else
    fh_e = @gp_e;
    fh_g = @gp_g;
    fh_p = @gp_pred;
  end

  optdefault.GradObj='on';
  optdefault.LargeScale='off';
  optdefault.Display='off';
  opt_optim=optimset(optdefault,opt_optim);
  %if isempty(opt_scg) && isempty(opt_fminunc)
  %    opt_scg = scg2_opt;
  %    opt_scg.tolfun = 1e-3;
  %    opt_scg.tolx = 1e-3;
  %    opt_scg.display = -1;
  %elseif isempty(opt_scg)
  %    opt_fminunc=optimset(opt_fminunc,'GradObj','on','LargeScale', 'on','Display','off');
  %end

  % ====================================
  % Find the mode of the hyperparameters
  % ====================================
  w = gp_pak(gp);
  w = optimf(@(ww) gp_eg(ww, gp, x, y, options), w, opt_optim);
  gp = gp_unpak(gp,w);
  
  % Number of parameters
  nParam = length(w);

  gp_array={}; % Array of gp-models with different hyperparameters
  Ef_grid = []; % Predicted means with different hyperparameters
  Varf_grid = []; % Variance of predictions with different hyperparameters
  p_th=[]; % List of the weights of different hyperparameters (un-normalized)
  th=[]; % List of hyperparameters

  switch int_method
    case {'grid', 'CCD'}
      
      % ===============================
      % New variable z for exploration
      % ===============================
      
      H = hessian(w);
      Sigma = inv(H);
      
      % Some jitter may be needed to get positive semi-definite covariance
      if any(eig(Sigma)<0)
        jitter = 0;
        while any(eig(Sigma)<0)
          jitter = jitter + eye(size(H,1))*0.01;
          Sigma = Sigma + jitter;
        end
        warning(sprintf('gp_ia -> singular Hessian. Jitter of %.4f added.', jitter))
      end
      
      if ~opt.rotate
        Sigma=diag(diag(Sigma));
      end
      
      [V,D] = eig(full(Sigma));
      z = (V*sqrt(D))'.*opt.step_size;
      
      % =======================================
      % Exploration of possible hyperparameters
      % =======================================
      
      checked = zeros(1,nParam); % List of locations already visited
      candidates = zeros(1,nParam); % List of locations with enough density
      
      switch int_method
        case 'grid'
          % density in the mode
          p_th(1) = -feval(fh_e,w,gp,x,y,options);
          if ~isempty(xt)
            % predictions in the mode if needed
            [Ef_grid(1,:), Varf_grid(end+1,:)]=feval(fh_p,gp,x,y,xt,options);
          end
          
          % Put the mode to th-array and gp-model in the mode to gp_array
          th(1,:) = w;
          gp = gp_unpak(gp,w);
          gp_array{end+1} = gp;
          
          while ~isempty(candidates)
            % Repeat until there are no hyperparameters with high enough
            % density that are not checked yet
            % Loop through the dimensions
            for i1 = 1 : nParam
              % One step to the positive direction of dimension i1
              pos = zeros(1,nParam); pos(i1)=1;
              
              % Check if the neighbour in the direction of pos is
              % already checked
              if ~any(sum(abs(repmat(candidates(1,:)+pos,size(checked,1),1)-checked),2)==0)
                % The parameters in the neighbour
                % p_th(end+1) = -feval(fh_e,w_p,gp,x,y);
                w_p = w + candidates(1,:)*z + z(i1,:);
                th(end+1,:) = w_p;
                
                gp = gp_unpak(gp,w_p);
                gp_array{end+1} = gp;
                
                % density
                p_th(end+1) = -feval(fh_e,w_p,gp,x,y,options);
                if ~isempty(xt)
                  % predictions if needed
                  [Ef_grid(end+1,:), Varf_grid(end+1,:)]=...
                      feval(fh_p,gp,x,y,xt,options);
                end
                
                % If the density is high enough, put the location in to the
                % candidates list. The neighbours of that
                % location will be studied lated
                if (p_th(1)-p_th(end))<opt.threshold
                  candidates(end+1,:) = candidates(1,:)+pos;
                end
                
                % Put the recently studied point to the checked list
                checked(end+1,:) = candidates(1,:)+pos;
              end
              
              neg = zeros(1,nParam); neg(i1)=-1;
              if ~any(sum(abs(repmat(candidates(1,:)+neg,size(checked,1),1)-checked),2)==0)
                w_n = w + candidates(1,:)*z - z(i1,:);
                th(end+1,:) = w_n;
                
                gp = gp_unpak(gp,w_n);
                gp_array{end+1} = gp;
                
                % density
                p_th(end+1) = -feval(fh_e,w_n,gp,x,y,options);
                if ~isempty(xt)
                  % predictions if needed
                  [Ef_grid(end+1,:), Varf_grid(end+1,:)]=...
                      feval(fh_p,gp,x,y,xt,options);
                end
                
                if (p_th(1)-p_th(end))<opt.threshold
                  candidates(end+1,:) = candidates(1,:)+neg;
                end
                checked(end+1,:) = candidates(1,:)+neg;
              end
            end
            candidates(1,:)=[];
          end
          
          % Convert densities from the log-space and normalize them
          p_th = p_th(:)-min(p_th);
          P_TH = exp(p_th)/sum(exp(p_th));
          
        case 'CCD'
          % Walsh indeces (see Sanchez and Sanchez (2005))
          walsh = [1 2 4 8 15 16 32 51 64 85 106 128 150 171 219 237 ...
                   247 256 279 297 455 512 537 557 597 643 803 863 898 ...
                   1024 1051 1070 1112 1169 1333 1345 1620 1866 2048 ...
                   2076 2085 2158 2372 2456 2618 2800 2873 3127 3284 ...
                   3483 3557 3763 4096 4125 4135 4176 4435 4459 4469 ...
                   4497 4752 5255 5732 5801 5915 6100 6369 6907 7069 ...
                   8192 8263 8351 8422 8458 8571 8750 8858 9124 9314 ...
                   9500 10026 10455 10556 11778 11885 11984 13548 14007 ...
                   14514 14965 15125 15554 16384 16457 16517 16609 ...
                   16771 16853 17022 17453 17891 18073 18562 18980 ...
                   19030 19932 20075 20745 21544 22633 23200 24167 ...
                   25700 26360 26591 26776 28443 28905 29577 32705];
          
          % How many design points
          ii = sum(nParam >= [1 2 3 4 6 7 9 12 18 22 30 39 53 70 93]);
          H0 = 1;
          
          % Design matrix
          for i1 = 1 : ii
            H0 = [H0 H0 ; H0 -H0];
          end
          
          % Radius of the sphere (greater than 1)
          if isempty(opt.f0)
            f0=1.3;
          else
            f0 = opt.f0;
          end
          
          % Design points
          points = H0(:,1+walsh(1:nParam));
          % Center point
          points = [zeros(1,nParam); points];
          % Points on the main axis
          for i1 = 1 : nParam
            points(end+1,:)=zeros(1,nParam);
            points(end,i1)=sqrt(nParam);
            points(end+1,:)=zeros(1,nParam);
            points(end,i1)=-sqrt(nParam);
          end
          
          if ~opt.autoscale
            points = f0*points;
          else
            for j = 1 : nParam*2
              % Here temp is one of the points on the main axis in either
              % positive or negative direction.
              temp = zeros(1,nParam);
              if mod(j,2) == 1
                dir = 1;
              else
                dir = -1;
              end
              ind = ceil(j/2);
              temp(ind)=dir;
              
              % Find the scaling parameter so that when we move 2 stds
              % from the mode, the log density drops by 2
              % No gradient and single-variable, so use fminbnd
              optim1=optimset('TolX',0.1);
              target=feval(fh_e,w,gp,x,y,options)+2;
              t = fminbnd(@(t) (target-feval(fh_e,w+t*temp*z,gp,x,y,options)).^2, f0/4, f0*4, optim1);
              sd(points(:,ind)*dir>0, ind) = 0.5*t/sqrt(nParam);
            end
            % Each point is scaled with corresponding scaling parameter
            % and desired radius
            points = f0*sd.*points;
          end
          
          % Put the points into hyperparameter-space
          th = points*z+repmat(w,size(points,1),1);
          
          p_th=[]; gp_array={};
          for i1 = 1 : size(th,1)
            gp = gp_unpak(gp,th(i1,:));
            gp_array{end+1} = gp;
            
            % density
            p_th(end+1) = -feval(fh_e,th(i1,:),gp,x,y,options);
            if ~isempty(xt)
              % predictions if needed
              [Ef_grid(end+1,:), Varf_grid(end+1,:)]=...
                  feval(fh_p,gp,x,y,xt,options);
            end
          end
          
          p_th=p_th-min(p_th);
          p_th=exp(p_th);
          p_th=p_th/sum(p_th);
          
          
          % Calculate the area weights for the integration and scale
          % densities of the design points with these weights
          delta_k = 1/((2*pi)^(-nParam/2)*exp(-.5*nParam*f0^2)*(size(points,1)-1)*f0^2);
          delta_0 = (2*pi)^(nParam/2)*(1-1/f0^2);
          
          delta_k=delta_k/delta_0;
          delta_0=1;
          
          p_th=p_th.*[delta_0,repmat(delta_k,1,size(th,1)-1)];
          P_TH=p_th/sum(p_th);
          P_TH=P_TH(:);
      end
      
    case {'is_normal' 'is_normal_qmc' 'is_t'}
      
      % Covariance of the gaussian approximation
      H = full(hessian(w));
      Sigma = inv(H);
      Scale = Sigma;
      [V,D] = eig(full(Sigma));
      z = (V*sqrt(D))'.*opt.step_size;
      P0 =  -feval(fh_e,w,gp,x,y,options);
      
      % Some jitter may be needed to get positive semi-definite covariance
      if any(eig(Sigma)<0)
        jitter = 0;
        while any(eig(Sigma)<0)
          jitter = jitter + eye(size(H,1))*0.01;
          Sigma = Sigma + jitter;
        end
        warning('gp_ia -> singular Hessian. Jitter of %.4f added.', jitter)
      end
      
      N = opt.nsamples;
      
      switch int_method
        case 'is_normal'
          % Normal samples
          
          if opt.qmc
            th  = repmat(w,N,1)+(chol(Sigma)'*(sqrt(2).*erfinv(2.*hammersley(size(Sigma,1),N) - 1)))';
            p_th_appr = mvnpdf(th, w, Sigma);
          else
            th = mvnrnd(w,Sigma,N);
            p_th_appr = mvnpdf(th, w, Sigma);
          end
          
          
          if opt.autoscale
            
            if opt.qmc
              e = (sqrt(2).*erfinv(2.*hammersley(size(Sigma,1),N) - 1))';
            else
              e = randn(N,size(Sigma,1));
            end
            
            % Scaling of the covariance (see Geweke, 1989, Bayesian
            % inference in econometric models using Monte Carlo integration
            delta = -6:.5:6;
            for i0 = 1 : nParam
              for i1 = 1 : length(delta)
                ttt = zeros(1,nParam);
                ttt(i0)=1;
                phat = (-feval(fh_e,w+(delta(i1)*chol(Sigma)'*ttt')',gp,x,y,options));
                fi(i1) = abs(delta(i1)).*(2.*(P0-phat)).^(-.5);
                
                pp(i1) = exp(phat);
                pt(i1) = mvnpdf(delta(i1)*chol(Sigma)'*ttt', 0, Sigma);
              end
              
              q(i0) = max(fi(delta>0));
              r(i0) = max(fi(delta<0));
              
            end
            
            %% Samples one by one
            for i3 = 1 : N
              C = 0;
              for i2 = 1 : nParam
                if e(i3,i2)<0
                  eta(i3,i2) = e(i3,i2)*r(i2);
                  C = C + log(r(i2));
                else
                  eta(i3,i2) = e(i3,i2)*q(i2);
                  C = C + log(q(i2));
                end
                
              end
              p_th_appr(i3) = exp(-C-.5*e(i3,:)*e(i3,:)');
              th(i3,:)=w+(chol(Scale)'*eta(i3,:)')';
            end
          end
          
        case 'is_t'
          % Student-t Samples
          nu = opt.t_nu;
          chi2 = repmat(chi2rnd(nu, [1 N]), nParam, 1);
          Scale = (nu-2)./nu.*Sigma;
          Scale = Sigma;
          
          if opt.qmc
            e = (sqrt(2).*erfinv(2.*hammersley(size(Sigma,1),N) - 1))';
            th = repmat(w,N,1) + ( chol(Scale)' * e' .* sqrt(nu./chi2) )';
          else
            th = repmat(w,N,1) + ( chol(Scale)' * randn(nParam, N).*sqrt(nu./chi2) )';
          end
          
          p_th_appr = mt_pdf(th - repmat(w,N,1), Sigma, nu);
          
          if opt.autoscale
            delta = -6:.5:6;
            for i0 = 1 : nParam
              ttt = zeros(1,nParam);
              ttt(i0)=1;
              for i1 = 1 : length(delta)
                phat = exp(-feval(fh_e,w+(delta(i1)*chol(Scale)'*ttt')',gp,x,y,options));
                
                fi(i1) = nu^(-.5).*abs(delta(i1)).*(((exp(P0)/phat)^(2/(nu+nParam))-1).^(-.5));
                rel(i1) = (exp(-feval(fh_e,w+(delta(i1)*chol(Scale)'*ttt')',gp,x,y,options)))/ ...
                          mt_pdf((delta(i1)*chol(Scale)'*ttt')', Scale, nu);
                pp(i1) = phat;
                pt(i1) = mt_pdf((delta(i1)*chol(Scale)'*ttt')', Scale, nu);
              end
              
              q(i0) = max(fi(delta>0));
              r(i0) = max(fi(delta<0));
              
              scl = ones(1,length(delta));
              scl(1:floor(length(delta)/2))=repmat(r(i0),1,floor(length(delta)/2));
              scl(ceil(length(delta)/2):end)=repmat(q(i0),1,ceil(length(delta)/2));
            end
            
            %% Samples
            if opt.qmc
              e = (sqrt(2).*erfinv(2.*hammersley(size(Sigma,1),N) - 1))';
            else
              e = randn(N,size(Sigma,1));
            end
            
            for i3 = 1 : N
              C = 0;
              for i2 = 1 : nParam
                chi(i2) = chi2rnd(nu);
                if e(i3,i2)<0
                  eta(i3,i2) = e(i3,i2)*r(i2)*(sqrt(nu/chi(i2)));
                  C = C -log(r(i2));
                else
                  eta(i3,i2) = e(i3,i2)*q(i2)*(sqrt(nu/chi(i2)));
                  C = C  -log(q(i2));
                end
              end
              p_th_appr(i3) = exp(C - ((nu+nParam)/2)*log(1+sum((e(i3,:)./sqrt(chi)).^2)));
              th(i3,:)=w+(chol(Scale)'*eta(i3,:)')';
            end
          end
      end
      gp_array=cell(N,1);
      
      % Densities of the samples in target distribution and predictions,
      % if needed.
      for j = 1 : N
        gp_array{j}=gp_unpak(gp,th(j,:));
        % density
        p_th(j) = -feval(fh_e,th(j,:),gp_array{j},x,y,options);
        if ~isempty(xt)
          % predictions if needed
          [Ef_grid(j,:), Varf_grid(j,:)]=...
              feval(fh_p,gp_array{j},x,y,xt,options);
        end
      end
      p_th = exp(p_th-min(p_th));
      p_th = p_th/sum(p_th);
      
      % (Scaled) Densities of the samples in the approximation of the
      % target distribution
      p_th_appr = p_th_appr/sum(p_th_appr);
      
      % Importance weights for the samples
      iw = p_th(:)./p_th_appr(:);
      iw = iw/sum(iw);
      
      % Return the importance weights
      P_TH = iw;
      
    case {'hmc'}
      
      if isempty('opt_hmc')
        opt_hmc = hmc2_opt;
      end
      
      if isfield(opt_hmc, 'rstate')
        if ~isempty(opt_hmc.rstate)
          hmc_rstate = opt_hmc.rstate;
        else
          hmc2('state', sum(100*clock))
          hmc_rstate=hmc2('state');
        end
      else
        hmc2('state', sum(100*clock))
        hmc_rstate=hmc2('state');
      end
      
      if opt.display
        fprintf('Starting the HMC sampler\n')
        fprintf(' cycle  etr      ');
        fprintf('hrej     \n')
      end
      
      ri = 0;
      % -------------- Start sampling ----------------------------
      for j=1:opt.nsamples
        
        if opt.persistence_reset
          hmc_rstate.mom = [];
        end
        
        
        hmcrej = 0;
        for l=1:opt.repeat
          
          % ----------- Sample hyperparameters with HMC ---------------------
          ww = gp_pak(gp);
          hmc2('state',hmc_rstate)              % Set the state
          [ww, energies, diagnh] = hmc2(fh_e, ww, opt_hmc, fh_g, gp, x, y, options);
          hmc_rstate=hmc2('state');             % Save the current state
          hmcrej=hmcrej+diagnh.rej/opt.repeat;
          if isfield(diagnh, 'opt')
            opt_hmc = diagnh.opt;
          end
          opt_hmc.rstate = hmc_rstate;
          ww=ww(end,:);
          gp = gp_unpak(gp, ww);
          
          etr = feval(fh_e,ww,gp,x,y,options);
          
        end % ------------- for l=1:opt.repeat -------------------------
        
        th(j,:) = ww;
        gp_array{j} = gp_unpak(gp, ww);
        
        % density
        p_th(j) = 1;
        if ~isempty(xt)
          % predictions if needed
          [Ef_grid(j,:), Varf_grid(j,:)]=...
              feval(fh_p,gp_array{j},x,y,xt,options);
        end
        
        % ----------- Set record -----------------------
        ri=ri+1;
        
        % Display some statistics  THIS COULD BE DONE IN NICER WAY ALSO (V.P.)
        if opt.display
          fprintf(' %4d  %.3f  ',ri, etr);
          fprintf(' %.1e  ',hmcrej);
          fprintf('\n');
        end
      end
      P_TH = p_th(:)./length(p_th);
  end

  % =================================================================
  % If targets are given as inputs, make predictions to those targets
  % =================================================================

  if ~isempty(xt) && nargout > 2
    
    % ====================================================================
    % Grid of 501 points around 10 stds to both directions around the mode
    % ====================================================================
    ff = zeros(size(Ef_grid,2),501);
    
    for j = 1 : size(Ef_grid,2);
      ff(j,:) = Ef_grid(1,j)-10*sqrt(Varf_grid(1,j)) : 20*sqrt(Varf_grid(1,j))/500 : Ef_grid(1,j)+10*sqrt(Varf_grid(1,j));
    end
    
    % Calculate the density in each grid point by integrating over
    % different models
    pf = zeros(size(Ef_grid,2),501);
    for j = 1 : size(Ef_grid,2)
      pf(j,:) = sum(normpdf(repmat(ff(j,:),size(Ef_grid,1),1), repmat(Ef_grid(:,j),1,size(ff,2)), repmat(sqrt(Varf_grid(:,j)),1,size(ff,2))).*repmat(P_TH,1,size(ff,2)));
    end
    
    % Normalize distributions
    pf = pf./repmat(sum(pf,2),1,size(pf,2));
    
    % Widths of each grid point
    dx = diff(ff,1,2);
    dx(:,end+1)=dx(:,end);
    
    % Calculate mean and variance of the disrtibutions
    Ef = sum(ff.*pf,2)./sum(pf,2);
    Varf = sum(pf.*(repmat(Ef,1,size(ff,2))-ff).^2,2)./sum(pf,2);
  end

  % ====================================================================
  % If validation of the approximation is used perform tests
  % ====================================================================
  % - validate the integration over hyperparameters
  % - Check the number of effective parameters in GP:s
  % - Check the normal approximations if Laplace approximation or EP
  % has been used
  if opt.validate>0 && ~isempty(Ef_grid)
    % Check the importance weights if used
    % Check also that the integration over theta has converged
    switch int_method
      case {'is_normal' 'is_normal_qmc' 'is_t'}
        pth_w = P_TH./sum(P_TH);
        meff = 1./sum(pth_w.^2);
        
        if opt.validate>1
          figure
          plot(cumsum(sort(pth_w)))
          title('The cumulative mass of importance weights')
          ylabel('cumulative weight, \Sigma_{i=1}^k w_i')
          xlabel('i, the i''th largest integration point')
          
          fprintf('\n \n')
          fprintf('The effective number of importance samples is %.2f out of total %.2f samples \n', meff, length(P_TH))
        end
% $$$                 fprintf('Validating the integration over hyperparameters...  \n')
% $$$
% $$$                 Ef2(:,1) = Ef;
% $$$                 Varf2(:,1) = Varf;
% $$$
% $$$                 for i3 = 1:floor(size(Ef_grid,1)./2)
% $$$                     pf2 = zeros(size(Ef_grid,2),501);
% $$$                     for j = 1 : size(Ef_grid,2)
% $$$                         pf2(j,:) = sum(normpdf(repmat(ff(j,:),size(Ef_grid,1)-i3,1), repmat(Ef_grid(1:end-i3,j),1,size(ff,2)), repmat(sqrt(Varf_grid(1:end-i3,j)),1,size(ff,2))).*repmat(P_TH(1:end-i3)./sum(P_TH(1:end-i3)),1,size(ff,2)));
% $$$                     end
% $$$
% $$$
% $$$                     % Normalize distributions
% $$$                     pf2 = pf2./repmat(sum(pf2,2),1,size(pf2,2));
% $$$
% $$$                     % Widths of each grid point
% $$$                     dx = diff(ff,1,2);
% $$$                     dx(:,end+1)=dx(:,end);
% $$$
% $$$                     % Calculate mean and variance of the disrtibutions
% $$$                     Ef2(:,i3+1) = sum(ff.*pf2,2)./sum(pf2,2);
% $$$                     Varf2(:,i3+1) = sum(pf2.*(repmat(Ef2(:,i3),1,size(ff,2))-ff).^2,2)./sum(pf2,2);
% $$$                 end
% $$$                 for i = 1:size(Varf2,2)-1
% $$$                     KL(:,i) = 0.5*log(Varf2(:,i+1)./Varf2(:,i)) + 0.5 * ( (Ef2(:,i) - Ef2(:,i+1)).^2 + Varf2(:,i) - Varf2(:,i+1) )./Varf2(:,i+1);
% $$$                 end
% $$$
% $$$                 KL = fliplr(KL);
% $$$                 if sum(KL(:,end)) < 0.5 % This is a limit whithout good justification
% $$$                     fprintf('The sum of KL-divergences between latent value marginals with %d and %d \n', size(Ef_grid,1), size(Ef_grid,1)-1)
% $$$                     fprintf('integration points is:  %.4e\n', sum(KL(:,end)));
% $$$                     fprintf('The integration seems to have converged.\n')
% $$$                 else
% $$$                     fprintf('The sum of KL-divergences between latent value marginals with %d and %d \n', size(Ef_grid,1), size(Ef_grid,1)-1)
% $$$                     fprintf('integration points is:  %.4e\n', sum(KL(:,end)));
% $$$                     fprintf('Check the integration. There might be problems. \n')
% $$$                 end
% $$$                             figure
% $$$             plot(size(Ef_grid,1)-size(KL,2)+1:size(Ef_grid,1), sum(KL))
% $$$             title('The convergence of the integration over hyperparameters')
% $$$             ylabel('\Sigma_{i=1}^n KL(q_m(f_i)||q_{m-1}(f_i))')
% $$$             xlabel('m, the number of integration points in hyperparam. space')
    end
    
    % Evaluate the number of effective latent variables in GPs
    for i3 = 1:length(gp_array)
      p_eff(i3) = gp_peff(gp_array{i3}, x, y, options);
    end
    
    if opt.validate>1
      figure
      plot(p_eff./size(x,1))
      title('The number of effective latent variables vs. number of latent variables')
      ylabel('p_{eff} / size(f,1)')
      xlabel('m, the index of integration point in hyperparam. space')
      
      fprintf('\n \n')
    end
    
    if max(p_eff./size(x,1)) < 0.5 % This is a limit whithout good justification
      if opt.validate>1
        fprintf('The maximum number of effective latent variables vs. the number of latent \n')
        fprintf('variables is %.4e at integration point %d .\n', max(p_eff./size(x,1)), find(p_eff == max(p_eff)))
        fprintf('The Normal approximations for the conditional posteriors seem reliable.\n')
      end
    else
      fprintf('The maximum number of effective latent variables vs. the number of latent \n')
      fprintf('variables is %.4e at integration point %d .\n', max(p_eff./size(x,1)), find(p_eff == max(p_eff)))
      fprintf('The Normal approximations for the conditional posteriors should be checked.\n')
    end
    
    fprintf('\n \n')
  end

  % Add the integration weights into the gp_array
  for i = 1:length(gp_array)
    gp_array{i}.ia_weight = P_TH(i);
  end

  function p = mt_pdf(x,Sigma,nu)
    d = length(Sigma);
    for i1 = 1 : size(x,1);
      p(i1) = gamma((nu+1)/2) ./ gamma(nu/2) .* nu^(d/2) .* pi^(d/2) ...
              .* det(Sigma)^(-.5) .* (1+(1/nu) .* (x(i1,:))*inv(Sigma)*(x(i1,:))')^(-.5*(nu+d));
    end
  end

  function H = hessian(w0)
  % Compute Hessian using finite differences, which is can be slow
  % if number of parameters is high
    
    m = length(w);
    e0 = feval(fh_e,w0,gp,x,y,options);
    delta = 1e-4;
    H = -1*ones(m,m);
    
    % Compute first using gradients
    % If Hessian is singular try computing with
    % larger step-size
    while any(eig(H)<0) && delta < 1e-2
      for i = 1:m
        for j = i:m
          w1 = w0; w2 = w0;
          w1(j) = w1(j) + delta;
          w2(j) = w2(j) - delta;
          
          g1 = feval(fh_g,w1,gp,x,y,options);
          g2 = feval(fh_g,w2,gp,x,y,options);
          
          H(i,j) = (g1(i)-g2(i))./(2.*delta);
          H(j,i) = H(i,j);
        end
      end
      delta = delta + 1e-3;
    end
    
    % If the Hessian is still singular or the delta is too large
    % try to compute with finite differences for energies.
    if any(eig(H)<0) || delta > 1e-2
      delta = 1e-4;
      for i=1:m
        w1 = w0; w4 = w0;
        w1(i) = [w1(i)+2*delta];
        w4(i) = [w4(i)-2*delta];
        
        e1 = feval(fh_e,w1,gp,x,y,options);
        e4 = feval(fh_e,w4,gp,x,y,options);
        
        H(i,i) = (e1 - 2*e0 + e4)./(4.*delta.^2);
        for j = i+1:m
          w1 = w0; w2 = w0; w3 = w0; w4 = w0;
          w1([i j]) = [w1(i)+delta w1(j)+delta];
          w2([i j]) = [w2(i)-delta w2(j)+delta];
          w3([i j]) = [w3(i)+delta w3(j)-delta];
          w4([i j]) = [w4(i)-delta w4(j)-delta];
          
          e1 = feval(fh_e,w1,gp,x,y,options);
          e2 = feval(fh_e,w2,gp,x,y,options);
          e3 = feval(fh_e,w3,gp,x,y,options);
          e4 = feval(fh_e,w4,gp,x,y,options);
          
          H(i,j) = (e1 - e2 - e3 + e4)./(4.*delta.^2);
          H(j,i) = H(i,j);
        end
      end
    end
    
    % even this does not work so print error
    if any(eig(H)<0)
      warning('GP_IA -> HESSIAN: the Hessian matrix is singular. Check the optimization.')
    end
    
  end

end