function [mu_star, Sigm_cc, pi_star, Ey, Vary] = gpla_softmax_pred(gp, x, y, varargin)
%function [Ef, Varf, Ey, Vary, Pyt] = gpla_softmax_pred(gp, x, y, xt, varargin)
%GPLA_SOFTMAX_PRED Predictions with Gaussian Process Laplace
%                approximation with softmax likelihood
%
%  Description
%    [EFT, VARFT] = GPLA_SOFTMAX_PRED(GP, X, Y, XT, OPTIONS) takes
%    a GP structure GP together with a matrix XT of input vectors,
%    matrix X of training inputs and vector Y of training targets,
%    and evaluates the predictive distribution at inputs XT. Returns
%    a posterior mean EFT and variance VARFT of latent variables.
%
%    [EF, VARF, LPYT] = GPLA_SOFTMAX_PRED(GP, X, Y, XT, 'yt', YT, ...)
%    returns also logarithm of the predictive density PYT of the observations YT
%    at input locations XT. This can be used for example in the
%    cross-validation. Here Y has to be vector.
%
%
%     OPTIONS is optional parameter-value pair
%       predcf - is index vector telling which covariance functions are 
%                used for prediction. Default is all (1:gpcfn). See 
%                additional information below.
%       tstind - is a vector/cell array defining, which rows of X belong 
%                to which training block in *IC type sparse models. Deafult 
%                is []. In case of PIC, a cell array containing index 
%                vectors specifying the blocking structure for test data.
%                IN FIC and CS+FIC a vector of length n that points out the 
%                test inputs that are also in the training set (if none,
%                set TSTIND = []).
%       yt     - is optional observed yt in test points
%       z      - optional observed quantity in triplet (x_i,y_i,z_i)
%                Some likelihoods may use this. For example, in
%                case of Poisson likelihood we have z_i=E_i, that
%                is, expected value for ith case.
%       zt     - optional observed quantity in triplet (xt_i,yt_i,zt_i)
%                Some likelihoods may use this. For example, in
%                case of Poisson likelihood we have zt_i=Et_i, that
%                is, expected value for ith case.
%
%  See also
%    GPLA_SOFTMAX_E, GPLA_SOFTMAX_G, GP_PRED, DEMO_MULTICLASS
%
% Copyright (c) 2010 Jaakko Riihim�ki

% This software is distributed under the GNU General Public 
% License (version 3 or later); please refer to the file 
% License.txt, included with the software, for details.

  ip=inputParser;
  ip.FunctionName = 'GPLA_SOFTMAX_PRED';
  ip.addRequired('gp', @isstruct);
  ip.addRequired('x', @(x) ~isempty(x) && isreal(x) && all(isfinite(x(:))))
  ip.addRequired('y', @(x) ~isempty(x) && isreal(x) && all(isfinite(x(:))))
  ip.addOptional('xt', [], @(x) isempty(x) || (isreal(x) && all(isfinite(x(:)))))
  ip.addParamValue('yt', [], @(x) isreal(x) && all(isfinite(x(:))))
  ip.addParamValue('z', [], @(x) isreal(x) && all(isfinite(x(:))))
  ip.addParamValue('zt', [], @(x) isreal(x) && all(isfinite(x(:))))
  ip.addParamValue('predcf', [], @(x) isempty(x) || ...
                   isvector(x) && isreal(x) && all(isfinite(x)&x>0))
  ip.addParamValue('tstind', [], @(x) isempty(x) || iscell(x) ||...
                 (isvector(x) && isreal(x) && all(isfinite(x)&x>0)))
  if numel(varargin)==0 || isnumeric(varargin{1})
    % inputParser should handle this, but it doesn't
    ip.parse(gp, x, y, varargin{:});
  else
    ip.parse(gp, x, y, [], varargin{:});
  end
  xt=ip.Results.xt;
  yt=ip.Results.yt;
  predcf=ip.Results.predcf;
  tstind=ip.Results.tstind;
  if isempty(xt)
    xt=x;
    if isempty(tstind)
      if iscell(gp)
        gptype=gp{1}.type;
      else
        gptype=gp.type;
      end
      switch gptype
        case {'FULL' 'VAR' 'DTC' 'SOR'}
          tstind = [];
        case {'FIC' 'CS+FIC'}
          tstind = 1:size(x,1);
        case 'PIC'
          if iscell(gp)
            tstind = gp{1}.tr_index;
          else
            tstind = gp.tr_index;
          end
      end
    end
    if isempty(yt)
      yt=y;
    end
  end

  Ey=[];
  Vary=[];
  
    [tn, tnin] = size(x);
    
    switch gp.type
        % ============================================================
        % FULL
        % ============================================================
      case 'FULL'
        [e, edata, eprior, f, L, a, E, M, p] = gpla_softmax_e(gp_pak(gp), gp, x, y, 'z', z);

        ntest=size(xt,1);
        K_nf = gp_cov(gp,xt,x,predcf);
        K = gp_trcov(gp, x);
        
        nout=size(y,2);
        f2=reshape(f,tn,nout);
        
        expf2 = exp(f2);
        pi2 = expf2./(sum(expf2, 2)*ones(1,nout));
        
        mu_star=zeros(ntest,nout);
        Sigm_cc=zeros(nout, nout, ntest);
        
        Minv=M\(M'\eye(tn));
        Minv=(Minv+Minv')./2;
        
        for i1=1:nout
            mu_star(:,i1)=(y(:,i1)-pi2(:,i1))'*K_nf';
            b=E(:,:,i1)*K_nf';
            c_cav=Minv*b;
            
            for j1=1:nout
                c=E(:,:,j1)*c_cav; 
                Sigm_cc(i1,j1,:)=sum(c.*K_nf');
            end
            
            kstarstar = gp_trvar(gp,xt,predcf);
            Sigm_cc(i1,i1,:) = squeeze(Sigm_cc(i1,i1,:)) + kstarstar - sum(b.*K_nf')';
        end
        
        S=10000;
        pi_star=zeros(ntest,nout);
        for i1=1:ntest
            Sigm_tmp=(Sigm_cc(:,:,i1)'+Sigm_cc(:,:,i1))./2;
            f_star=mvnrnd(mu_star(i1,:), Sigm_tmp, S);
            
            tmp_star = exp(f_star);
            tmp_star = tmp_star./(sum(tmp_star, 2)*ones(1,size(tmp_star,2)));
            pi_star(i1,:)=log(mean(tmp_star));
            
        end
        
        % ============================================================
        % FIC
        % ============================================================    
      case 'FIC'        % Predictions with FIC sparse approximation for GP
        % ============================================================
        % PIC
        % ============================================================
      case {'PIC' 'PIC_BLOCK'}        % Predictions with PIC sparse approximation for GP
        % ============================================================
        % CS+FIC
        % ============================================================
      case 'CS+FIC'        % Predictions with CS+FIC sparse approximation for GP
    end
    
    % ============================================================
    % Evaluate also the predictive mean and variance of new observation(s)
    % ============================================================
%    if nargout > 2
%        if isempty(yt)
%            [Ey, Vary] = feval(gp.lik.fh.predy, gp.lik, Ef, Varf, [], zt);
%        else
%            [Ey, Vary, Pyt] = feval(gp.lik.fh.predy, gp.lik, Ef, Varf, yt, zt);
%        end
%    end
end